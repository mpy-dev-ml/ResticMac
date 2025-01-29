import Foundation
import SwiftUI

public enum CloudProvider: String, Sendable {
    case aws
    case azure
    case gcp
    case b2
    case sftp
    case local
    case iCloud
    case dropbox
    
    var displayName: String {
        switch self {
        case .aws: return "Amazon Web Services"
        case .azure: return "Microsoft Azure"
        case .gcp: return "Google Cloud Platform"
        case .b2: return "Backblaze B2"
        case .sftp: return "SFTP"
        case .local: return "Local Storage"
        case .iCloud: return "iCloud"
        case .dropbox: return "Dropbox"
        }
    }
}

public struct StorageMetrics {
    let totalBytes: Int64
    let compressedBytes: Int64
    let deduplicatedBytes: Int64
    let uploadedBytes: Int64
    let downloadedBytes: Int64
    let averageTransferSpeed: Double
    let successRate: Double
}

public struct TimeSeriesPoint<T> {
    let timestamp: Date
    let value: T
}

public struct TrendAnalysis {
    let confidence: Double
    let sampleSize: Int
    let outlierCount: Int
}

public enum ValidationError: LocalizedError {
    case inconsistentData(String)
    case suspiciousValue(String)
    case invalidValue(String)
    case emptyData(String)
    case invalidTimeSequence(String)
    case duplicateData(String)
    
    public var errorDescription: String? {
        switch self {
        case .inconsistentData(let message),
             .suspiciousValue(let message),
             .invalidValue(let message),
             .emptyData(let message),
             .invalidTimeSequence(let message),
             .duplicateData(let message):
            return message
        }
    }
}

public struct MockAnalyticsData {
    // Add properties as needed for testing
}

public struct MockPredictionInput {
    // Add properties as needed for testing
}

public struct ChartData: Sendable {
    let parallelData: [ParallelDataPoint]
    let nodes: [Node]
    let links: [Link]
    let bubbleData: [BubbleDataPoint]
}

public struct ParallelDataPoint: Identifiable, Sendable {
    public let id: UUID
    let values: [String: Double]
    let category: String
}

public struct Node: Identifiable, Sendable {
    public let id: UUID
    let name: String
    let value: Double
}

public struct Link: Identifiable, Sendable {
    public let id: UUID
    let source: UUID
    let target: UUID
    let value: Double
}

public struct BubbleDataPoint: Identifiable, Sendable {
    public let id: UUID
    let x: Double
    let y: Double
    let size: Double
    let category: String
}

public struct InteractiveChartOptions: Sendable {
    let dimensions: [String]
    let lineStyle: LineStyle
    let nodeWidth: CGFloat
    let nodePadding: CGFloat
    
    public struct LineStyle: Sendable {
        let width: CGFloat
        let opacity: Double
        let color: Color
    }
}

public enum EntryType: String, Codable, Sendable {
    case file
    case directory
    case symlink
}

public struct RepositoryStats: Codable, Sendable {
    let totalSize: Int64
    let totalFiles: Int
    let uniqueFiles: Int
    let deduplicationRatio: Double
}

public struct RepositoryHealth: Codable, Sendable {
    let isHealthy: Bool
    let issues: [String]
    let lastCheck: Date
    let integrityScore: Double
}

public protocol OutputFormat: Sendable {
    func format(_ data: Data) -> String
}

public struct JSONOutputFormat: OutputFormat {
    public func format(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let string = String(data: formatted, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return string
    }
}

public struct PlainTextOutputFormat: OutputFormat {
    public func format(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }
}
