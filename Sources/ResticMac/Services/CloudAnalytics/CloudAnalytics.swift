import Foundation
import os.log

actor CloudAnalytics {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalytics")
    private let persistence: CloudAnalyticsPersistence
    private var repositoryStats: [String: RepositoryAnalytics] = [:]
    private var costCalculators: [CloudProvider: CloudCostCalculator] = [:]
    
    init() {
        self.persistence = CloudAnalyticsPersistence()
        setupCostCalculators()
    }
    
    private func setupCostCalculators() {
        costCalculators = [
            .s3: AWSCostCalculator(),
            .b2: B2CostCalculator(),
            .azure: AzureCostCalculator(),
            .gcs: GCSCostCalculator(),
            .sftp: SFTPCostCalculator(),
            .rest: RESTCostCalculator()
        ]
    }
    
    struct RepositoryAnalytics {
        let repositoryId: String
        let provider: CloudProvider
        var storageMetrics: StorageMetrics
        var transferMetrics: TransferMetrics
        var costMetrics: CostMetrics
        var snapshotMetrics: SnapshotMetrics
        let lastUpdated: Date
        
        var monthlyStorageCost: Double {
            costMetrics.storageUnitCost * Double(storageMetrics.totalBytes)
        }
        
        var monthlyTransferCost: Double {
            costMetrics.transferUnitCost * Double(transferMetrics.totalTransferredBytes)
        }
        
        var totalMonthlyCost: Double {
            monthlyStorageCost + monthlyTransferCost
        }
    }
    
    struct StorageMetrics {
        var totalBytes: Int64
        var compressedBytes: Int64
        var deduplicatedBytes: Int64
        var packFiles: Int
        var blobCount: Int
        var treeCount: Int
        
        var compressionRatio: Double {
            guard totalBytes > 0 else { return 1.0 }
            return Double(compressedBytes) / Double(totalBytes)
        }
        
        var deduplicationRatio: Double {
            guard totalBytes > 0 else { return 1.0 }
            return Double(deduplicatedBytes) / Double(totalBytes)
        }
        
        var effectiveStorageRatio: Double {
            guard totalBytes > 0 else { return 1.0 }
            return Double(deduplicatedBytes) / Double(totalBytes)
        }
    }
    
    struct TransferMetrics {
        var totalTransferredBytes: Int64
        var uploadedBytes: Int64
        var downloadedBytes: Int64
        var failedTransfers: Int
        var successfulTransfers: Int
        var averageTransferSpeed: Double
        var transferHistory: [TransferRecord]
        
        struct TransferRecord {
            let timestamp: Date
            let bytesTransferred: Int64
            let direction: TransferDirection
            let duration: TimeInterval
            let success: Bool
            
            enum TransferDirection {
                case upload
                case download
            }
        }
        
        var successRate: Double {
            let total = failedTransfers + successfulTransfers
            guard total > 0 else { return 1.0 }
            return Double(successfulTransfers) / Double(total)
        }
    }
    
    struct CostMetrics {
        var storageUnitCost: Double  // Cost per byte per month
        var transferUnitCost: Double // Cost per byte transferred
        var operationCosts: [String: Double]
        var billingCycle: DateInterval
        var costHistory: [CostRecord]
        
        struct CostRecord {
            let date: Date
            let storageCost: Double
            let transferCost: Double
            let operationsCost: Double
        }
        
        var totalCost: Double {
            costHistory.reduce(0) { $0 + $1.storageCost + $1.transferCost + $1.operationsCost }
        }
    }
    
    struct SnapshotMetrics {
        var totalSnapshots: Int
        var snapshotsPerDay: Double
        var averageSnapshotSize: Int64
        var largestSnapshot: Int64
        var oldestSnapshot: Date
        var newestSnapshot: Date
        var retentionDays: Int
        var snapshotHistory: [SnapshotRecord]
        
        struct SnapshotRecord {
            let timestamp: Date
            let size: Int64
            let fileCount: Int
            let tags: [String]
        }
        
        var retentionPeriod: TimeInterval {
            guard let oldest = snapshotHistory.min(by: { $0.timestamp < $1.timestamp })?.timestamp,
                  let newest = snapshotHistory.max(by: { $0.timestamp < $1.timestamp })?.timestamp else {
                return 0
            }
            return newest.timeIntervalSince(oldest)
        }
    }
    
    func updateAnalytics(for repository: Repository) async throws {
        guard let provider = repository.cloudProvider else {
            throw CloudError.invalidConfiguration(provider: .s3, reason: "Not a cloud repository")
        }
        
        // Get repository statistics
        let stats = try await getRepositoryStats(repository)
        try await persistence.saveStorageMetrics(stats, for: repository)
        
        // Get transfer metrics
        let transfers = try await getTransferMetrics(repository)
        try await persistence.saveTransferMetrics(transfers, for: repository)
        
        // Calculate costs
        let costs = try await calculateCosts(
            provider: provider,
            storage: stats,
            transfers: transfers
        )
        try await persistence.saveCostMetrics(costs, for: repository)
        
        // Get snapshot metrics
        let snapshots = try await getSnapshotMetrics(repository)
        try await persistence.saveSnapshotMetrics(snapshots, for: repository)
        
        // Update repository analytics
        let analytics = RepositoryAnalytics(
            repositoryId: repository.path.absoluteString,
            provider: provider,
            storageMetrics: stats,
            transferMetrics: transfers,
            costMetrics: costs,
            snapshotMetrics: snapshots,
            lastUpdated: Date()
        )
        
        repositoryStats[repository.path.absoluteString] = analytics
        
        // Log update
        logger.info("Updated analytics for repository: \(repository.path.absoluteString, privacy: .private)")
    }
    
    private func getRepositoryStats(_ repository: Repository) async throws -> StorageMetrics {
        // Implementation would use ResticService to get repository stats
        // For now, return placeholder metrics
        return StorageMetrics(
            totalBytes: 0,
            compressedBytes: 0,
            deduplicatedBytes: 0,
            packFiles: 0,
            blobCount: 0,
            treeCount: 0
        )
    }
    
    private func getTransferMetrics(_ repository: Repository) async throws -> TransferMetrics {
        // Implementation would track transfer history
        // For now, return placeholder metrics
        return TransferMetrics(
            totalTransferredBytes: 0,
            uploadedBytes: 0,
            downloadedBytes: 0,
            failedTransfers: 0,
            successfulTransfers: 0,
            averageTransferSpeed: 0,
            transferHistory: []
        )
    }
    
    private func calculateCosts(
        provider: CloudProvider,
        storage: StorageMetrics,
        transfers: TransferMetrics
    ) async throws -> CostMetrics {
        guard let calculator = costCalculators[provider] else {
            throw CloudError.invalidConfiguration(provider: provider, reason: "No cost calculator available")
        }
        
        return try await calculator.calculateCosts(storage: storage, transfers: transfers)
    }
    
    private func getSnapshotMetrics(_ repository: Repository) async throws -> SnapshotMetrics {
        // Implementation would use ResticService to get snapshot metrics
        // For now, return placeholder metrics
        return SnapshotMetrics(
            totalSnapshots: 0,
            snapshotsPerDay: 0,
            averageSnapshotSize: 0,
            largestSnapshot: 0,
            oldestSnapshot: Date(),
            newestSnapshot: Date(),
            retentionDays: 0,
            snapshotHistory: []
        )
    }
    
    func getAnalytics(for repository: Repository) async throws -> RepositoryAnalytics {
        guard let analytics = repositoryStats[repository.path.absoluteString] else {
            throw CloudError.resourceNotFound(
                provider: repository.cloudProvider ?? .s3,
                path: repository.path.absoluteString
            )
        }
        return analytics
    }
    
    func getStorageForecast(for repository: Repository, months: Int = 12) async throws -> [ForecastPoint] {
        guard let analytics = repositoryStats[repository.path.absoluteString] else {
            throw CloudError.resourceNotFound(
                provider: repository.cloudProvider ?? .s3,
                path: repository.path.absoluteString
            )
        }
        
        // Calculate growth rate based on snapshot history
        let growthRate = calculateGrowthRate(analytics.snapshotMetrics)
        
        // Generate forecast points
        var forecast: [ForecastPoint] = []
        let currentSize = Double(analytics.storageMetrics.totalBytes)
        
        for month in 0...months {
            let projectedSize = currentSize * pow(1 + growthRate, Double(month))
            let point = ForecastPoint(
                date: Calendar.current.date(byAdding: .month, value: month, to: Date()) ?? Date(),
                projectedBytes: Int64(projectedSize),
                projectedCost: projectedSize * analytics.costMetrics.storageUnitCost
            )
            forecast.append(point)
        }
        
        return forecast
    }
    
    private func calculateGrowthRate(_ metrics: SnapshotMetrics) -> Double {
        // Calculate monthly growth rate based on snapshot history
        // This is a simplified calculation
        return 0.05 // 5% monthly growth as placeholder
    }
    
    struct ForecastPoint {
        let date: Date
        let projectedBytes: Int64
        let projectedCost: Double
    }
    
    // MARK: - Trend Analysis
    
    func analyseStorageTrends(for repository: Repository, timeRange: TimeRange) async throws -> TrendAnalysis {
        let metrics = try await persistence.loadStorageMetrics(for: repository, timeRange: timeRange)
        return calculateTrends(from: metrics) { record in
            Double(record.metrics.totalBytes)
        }
    }
    
    func analyseTransferTrends(for repository: Repository, timeRange: TimeRange) async throws -> TrendAnalysis {
        let metrics = try await persistence.loadTransferMetrics(for: repository, timeRange: timeRange)
        return calculateTrends(from: metrics) { record in
            Double(record.metrics.totalTransferredBytes)
        }
    }
    
    func analyseCostTrends(for repository: Repository, timeRange: TimeRange) async throws -> TrendAnalysis {
        let metrics = try await persistence.loadCostMetrics(for: repository, timeRange: timeRange)
        return calculateTrends(from: metrics) { record in
            record.metrics.totalCost
        }
    }
    
    func analyseSnapshotTrends(for repository: Repository, timeRange: TimeRange) async throws -> TrendAnalysis {
        let metrics = try await persistence.loadSnapshotMetrics(for: repository, timeRange: timeRange)
        return calculateTrends(from: metrics) { record in
            Double(record.metrics.totalSnapshots)
        }
    }
    
    private func calculateTrends<T: TimestampedRecord>(
        from records: [T],
        valueExtractor: (T) -> Double
    ) -> TrendAnalysis {
        guard records.count >= 2 else {
            return TrendAnalysis(
                changeRate: 0,
                trend: .stable,
                confidence: 0,
                seasonality: nil
            )
        }
        
        let values = records.map(valueExtractor)
        let timestamps = records.map { $0.timestamp.timeIntervalSince1970 }
        
        // Calculate rate of change
        let changeRate = calculateChangeRate(values: values, timestamps: timestamps)
        
        // Determine trend direction
        let trend = determineTrend(changeRate: changeRate)
        
        // Calculate confidence
        let confidence = calculateConfidence(values: values)
        
        // Detect seasonality
        let seasonality = detectSeasonality(values: values, timestamps: timestamps)
        
        return TrendAnalysis(
            changeRate: changeRate,
            trend: trend,
            confidence: confidence,
            seasonality: seasonality
        )
    }
    
    private func calculateChangeRate(values: [Double], timestamps: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        
        let n = Double(values.count)
        let sumX = timestamps.reduce(0, +)
        let sumY = values.reduce(0, +)
        let sumXY = zip(timestamps, values).map(*).reduce(0, +)
        let sumX2 = timestamps.map { $0 * $0 }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        return slope
    }
    
    private func determineTrend(changeRate: Double) -> TrendDirection {
        let threshold = 0.01 // 1% change threshold
        
        if changeRate > threshold {
            return .increasing
        } else if changeRate < -threshold {
            return .decreasing
        } else {
            return .stable
        }
    }
    
    private func calculateConfidence(values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        let standardDeviation = sqrt(variance)
        
        // Calculate coefficient of variation
        return 1.0 - (standardDeviation / mean)
    }
    
    private func detectSeasonality(values: [Double], timestamps: [Double]) -> Seasonality? {
        guard values.count >= 14 else { return nil } // Need at least 2 weeks of data
        
        // Check for weekly patterns
        let weeklyCorrelation = calculateAutocorrelation(values: values, lag: 7)
        if weeklyCorrelation > 0.7 {
            return .weekly
        }
        
        // Check for monthly patterns
        let monthlyCorrelation = calculateAutocorrelation(values: values, lag: 30)
        if monthlyCorrelation > 0.7 {
            return .monthly
        }
        
        return nil
    }
    
    private func calculateAutocorrelation(values: [Double], lag: Int) -> Double {
        guard values.count > lag else { return 0 }
        
        let n = values.count - lag
        let mean = values.reduce(0, +) / Double(values.count)
        
        var numerator = 0.0
        var denominator = 0.0
        
        for i in 0..<n {
            let x1 = values[i] - mean
            let x2 = values[i + lag] - mean
            numerator += x1 * x2
            denominator += x1 * x1
        }
        
        return numerator / denominator
    }
}

// MARK: - Trend Analysis Types

struct TrendAnalysis {
    let changeRate: Double
    let trend: TrendDirection
    let confidence: Double
    let seasonality: Seasonality?
    
    var isReliable: Bool {
        confidence > 0.8
    }
}

enum TrendDirection {
    case increasing
    case decreasing
    case stable
    
    var description: String {
        switch self {
        case .increasing: return "Increasing"
        case .decreasing: return "Decreasing"
        case .stable: return "Stable"
        }
    }
}

enum Seasonality {
    case weekly
    case monthly
    
    var description: String {
        switch self {
        case .weekly: return "Weekly pattern"
        case .monthly: return "Monthly pattern"
        }
    }
}

// MARK: - Cost Calculators

protocol CloudCostCalculator {
    func calculateCosts(storage: CloudAnalytics.StorageMetrics, transfers: CloudAnalytics.TransferMetrics) async throws -> CloudAnalytics.CostMetrics
}

struct AWSCostCalculator: CloudCostCalculator {
    func calculateCosts(
        storage: CloudAnalytics.StorageMetrics,
        transfers: CloudAnalytics.TransferMetrics
    ) async throws -> CloudAnalytics.CostMetrics {
        // AWS S3 Standard pricing (example values)
        let storageUnitCost = 0.023 / (1024.0 * 1024.0 * 1024.0) // $0.023 per GB
        let transferUnitCost = 0.09 / (1024.0 * 1024.0 * 1024.0) // $0.09 per GB
        
        return CloudAnalytics.CostMetrics(
            storageUnitCost: storageUnitCost,
            transferUnitCost: transferUnitCost,
            operationCosts: [:],
            billingCycle: DateInterval(start: Date(), duration: 2_592_000), // 30 days
            costHistory: []
        )
    }
}

struct B2CostCalculator: CloudCostCalculator {
    func calculateCosts(
        storage: CloudAnalytics.StorageMetrics,
        transfers: CloudAnalytics.TransferMetrics
    ) async throws -> CloudAnalytics.CostMetrics {
        // B2 pricing (example values)
        let storageUnitCost = 0.005 / (1024.0 * 1024.0 * 1024.0) // $0.005 per GB
        let transferUnitCost = 0.01 / (1024.0 * 1024.0 * 1024.0) // $0.01 per GB
        
        return CloudAnalytics.CostMetrics(
            storageUnitCost: storageUnitCost,
            transferUnitCost: transferUnitCost,
            operationCosts: [:],
            billingCycle: DateInterval(start: Date(), duration: 2_592_000),
            costHistory: []
        )
    }
}

struct AzureCostCalculator: CloudCostCalculator {
    func calculateCosts(
        storage: CloudAnalytics.StorageMetrics,
        transfers: CloudAnalytics.TransferMetrics
    ) async throws -> CloudAnalytics.CostMetrics {
        // Azure Blob Storage pricing (example values)
        let storageUnitCost = 0.0184 / (1024.0 * 1024.0 * 1024.0) // $0.0184 per GB
        let transferUnitCost = 0.087 / (1024.0 * 1024.0 * 1024.0) // $0.087 per GB
        
        return CloudAnalytics.CostMetrics(
            storageUnitCost: storageUnitCost,
            transferUnitCost: transferUnitCost,
            operationCosts: [:],
            billingCycle: DateInterval(start: Date(), duration: 2_592_000),
            costHistory: []
        )
    }
}

struct GCSCostCalculator: CloudCostCalculator {
    func calculateCosts(
        storage: CloudAnalytics.StorageMetrics,
        transfers: CloudAnalytics.TransferMetrics
    ) async throws -> CloudAnalytics.CostMetrics {
        // Google Cloud Storage pricing (example values)
        let storageUnitCost = 0.020 / (1024.0 * 1024.0 * 1024.0) // $0.020 per GB
        let transferUnitCost = 0.08 / (1024.0 * 1024.0 * 1024.0) // $0.08 per GB
        
        return CloudAnalytics.CostMetrics(
            storageUnitCost: storageUnitCost,
            transferUnitCost: transferUnitCost,
            operationCosts: [:],
            billingCycle: DateInterval(start: Date(), duration: 2_592_000),
            costHistory: []
        )
    }
}

struct SFTPCostCalculator: CloudCostCalculator {
    func calculateCosts(
        storage: CloudAnalytics.StorageMetrics,
        transfers: CloudAnalytics.TransferMetrics
    ) async throws -> CloudAnalytics.CostMetrics {
        // SFTP costs would be custom to the provider
        return CloudAnalytics.CostMetrics(
            storageUnitCost: 0,
            transferUnitCost: 0,
            operationCosts: [:],
            billingCycle: DateInterval(start: Date(), duration: 2_592_000),
            costHistory: []
        )
    }
}

struct RESTCostCalculator: CloudCostCalculator {
    func calculateCosts(
        storage: CloudAnalytics.StorageMetrics,
        transfers: CloudAnalytics.TransferMetrics
    ) async throws -> CloudAnalytics.CostMetrics {
        // REST costs would be custom to the provider
        return CloudAnalytics.CostMetrics(
            storageUnitCost: 0,
            transferUnitCost: 0,
            operationCosts: [:],
            billingCycle: DateInterval(start: Date(), duration: 2_592_000),
            costHistory: []
        )
    }
}
