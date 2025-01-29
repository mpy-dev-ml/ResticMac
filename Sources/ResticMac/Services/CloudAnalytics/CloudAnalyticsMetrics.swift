import Foundation

public struct TransferMetrics: Equatable, Sendable {
    let uploadedBytes: Int64
    let downloadedBytes: Int64
    let averageTransferSpeed: Double
    let successRate: Double
    let timestamp: Date
}

public struct CostMetrics: Equatable, Sendable {
    let storageUnitCost: Double
    let transferUnitCost: Double
    let totalCost: Double
    let timestamp: Date
}

public struct SnapshotMetrics: Equatable, Sendable {
    let totalSnapshots: Int
    let averageSnapshotSize: Int64
    let retentionDays: Int
    let timestamp: Date
}

public struct StorageMetrics: Equatable, Sendable {
    let totalBytes: Int64
    let compressedBytes: Int64
    let deduplicatedBytes: Int64
}

public struct AnalyticsData {
    var storageMetrics: [StorageMetrics]
    var transferMetrics: [TransferMetrics]
    var costMetrics: [CostMetrics]
    var snapshotMetrics: [SnapshotMetrics]
    
    init(
        storageMetrics: [StorageMetrics] = [],
        transferMetrics: [TransferMetrics] = [],
        costMetrics: [CostMetrics] = [],
        snapshotMetrics: [SnapshotMetrics] = []
    ) {
        self.storageMetrics = storageMetrics
        self.transferMetrics = transferMetrics
        self.costMetrics = costMetrics
        self.snapshotMetrics = snapshotMetrics
    }
}

public struct FilterChain: Identifiable {
    public let id: UUID
    let operations: [FilterOperation]
    let metadata: [String: String]
    
    init(
        id: UUID = UUID(),
        operations: [FilterOperation],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.operations = operations
        self.metadata = metadata
    }
}

public struct FilterResult {
    let data: AnalyticsData
    let metadata: [String: String]
}

public enum FilterOperation {
    case timeRange(DateInterval)
    case dataTypes([MetricType])
    case threshold(ThresholdCondition)
    case pattern(PatternMatcher)
    case aggregation(AggregationFunction)
    case transformation(DataTransformation)
    case sort(SortCriteria)
    case group(GroupingKey)
}

public enum MetricType {
    case storage
    case transfer
    case cost
    case snapshot
}

public struct ThresholdCondition {
    let value: Double
    let comparison: ComparisonOperator
    
    enum ComparisonOperator {
        case lessThan
        case greaterThan
        case equalTo
        case notEqualTo
        case lessThanOrEqual
        case greaterThanOrEqual
    }
    
    func evaluate(_ value: Double) -> Bool {
        switch comparison {
        case .lessThan:
            return value < self.value
        case .greaterThan:
            return value > self.value
        case .equalTo:
            return value == self.value
        case .notEqualTo:
            return value != self.value
        case .lessThanOrEqual:
            return value <= self.value
        case .greaterThanOrEqual:
            return value >= self.value
        }
    }
}

public struct PatternMatcher {
    let pattern: String
    let caseSensitive: Bool
    
    func matches(_ value: Any) -> Bool {
        guard let stringValue = String(describing: value) as? NSString else {
            return false
        }
        
        let options: NSString.CompareOptions = caseSensitive ? [] : .caseInsensitive
        return stringValue.range(of: pattern, options: options).location != NSNotFound
    }
}

public enum AggregationFunction {
    case sum
    case average
    case minimum
    case maximum
    case count
    
    func aggregate<T: Numeric>(_ values: [T]) -> T {
        switch self {
        case .sum:
            return values.reduce(0, +)
        case .average:
            return values.isEmpty ? 0 : values.reduce(0, +) / T(values.count)
        case .minimum:
            return values.min() ?? 0
        case .maximum:
            return values.max() ?? 0
        case .count:
            return T(values.count)
        }
    }
}

public enum DataTransformation {
    case normalize
    case standardize
    case log
    case scale(factor: Double)
    
    func transform(_ values: [Double]) -> [Double] {
        switch self {
        case .normalize:
            let min = values.min() ?? 0
            let max = values.max() ?? 1
            let range = max - min
            return values.map { range == 0 ? 0 : ($0 - min) / range }
            
        case .standardize:
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
            let stdDev = sqrt(variance)
            return values.map { stdDev == 0 ? 0 : ($0 - mean) / stdDev }
            
        case .log:
            return values.map { $0 > 0 ? log($0) : 0 }
            
        case .scale(let factor):
            return values.map { $0 * factor }
        }
    }
}

public struct SortCriteria {
    let keyPath: String
    let ascending: Bool
    
    func sort<T>(_ values: [T]) -> [T] where T: Comparable {
        ascending ? values.sorted() : values.sorted(by: >)
    }
}

public struct GroupingKey {
    let keyPath: String
    
    func group<T>(_ values: [T]) -> [String: [T]] {
        Dictionary(grouping: values) { String(describing: $0) }
    }
}

public struct FilterOptions {
    let cacheResults: Bool
    let parallelProcessing: Bool
    let timeoutInterval: TimeInterval?
    
    init(
        cacheResults: Bool = true,
        parallelProcessing: Bool = false,
        timeoutInterval: TimeInterval? = nil
    ) {
        self.cacheResults = cacheResults
        self.parallelProcessing = parallelProcessing
        self.timeoutInterval = timeoutInterval
    }
}
