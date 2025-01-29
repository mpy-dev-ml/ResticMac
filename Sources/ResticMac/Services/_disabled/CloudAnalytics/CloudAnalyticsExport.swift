import Foundation
import UniformTypeIdentifiers

actor CloudAnalyticsExport {
    private let persistence: CloudAnalyticsPersistence
    private let dateFormatter: ISO8601DateFormatter
    private let byteFormatter: ByteCountFormatter
    private let numberFormatter: NumberFormatter
    
    init(persistence: CloudAnalyticsPersistence) {
        self.persistence = persistence
        
        self.dateFormatter = ISO8601DateFormatter()
        
        self.byteFormatter = ByteCountFormatter()
        self.byteFormatter.countStyle = .file
        
        self.numberFormatter = NumberFormatter()
        self.numberFormatter.numberStyle = .decimal
        self.numberFormatter.maximumFractionDigits = 2
    }
    
    // MARK: - Export Functions
    
    func exportAnalytics(
        for repository: Repository,
        timeRange: TimeRange,
        format: ExportFormat,
        destination: URL
    ) async throws {
        let data = try await gatherAnalyticsData(for: repository, timeRange: timeRange)
        let exportData = try formatData(data, format: format)
        try exportData.write(to: destination)
    }
    
    func generateReport(
        for repository: Repository,
        timeRange: TimeRange
    ) async throws -> AnalyticsReport {
        let data = try await gatherAnalyticsData(for: repository, timeRange: timeRange)
        let trends = try await analyseTrends(for: repository, timeRange: timeRange)
        
        return AnalyticsReport(
            repository: repository,
            timeRange: timeRange,
            data: data,
            trends: trends,
            generatedAt: Date()
        )
    }
    
    // MARK: - Data Gathering
    
    private func gatherAnalyticsData(
        for repository: Repository,
        timeRange: TimeRange
    ) async throws -> AnalyticsData {
        async let storageMetrics = persistence.loadStorageMetrics(for: repository, timeRange: timeRange)
        async let transferMetrics = persistence.loadTransferMetrics(for: repository, timeRange: timeRange)
        async let costMetrics = persistence.loadCostMetrics(for: repository, timeRange: timeRange)
        async let snapshotMetrics = persistence.loadSnapshotMetrics(for: repository, timeRange: timeRange)
        
        return AnalyticsData(
            storageRecords: try await storageMetrics,
            transferRecords: try await transferMetrics,
            costRecords: try await costMetrics,
            snapshotRecords: try await snapshotMetrics
        )
    }
    
    private func analyseTrends(
        for repository: Repository,
        timeRange: TimeRange
    ) async throws -> AnalyticsTrends {
        let analytics = CloudAnalytics()
        
        async let storageTrends = analytics.analyseStorageTrends(for: repository, timeRange: timeRange)
        async let transferTrends = analytics.analyseTransferTrends(for: repository, timeRange: timeRange)
        async let costTrends = analytics.analyseCostTrends(for: repository, timeRange: timeRange)
        async let snapshotTrends = analytics.analyseSnapshotTrends(for: repository, timeRange: timeRange)
        
        return AnalyticsTrends(
            storage: try await storageTrends,
            transfer: try await transferTrends,
            cost: try await costTrends,
            snapshots: try await snapshotTrends
        )
    }
    
    // MARK: - Data Formatting
    
    private func formatData(_ data: AnalyticsData, format: ExportFormat) throws -> Data {
        switch format {
        case .csv:
            return try formatCSV(data)
        case .json:
            return try formatJSON(data)
        case .markdown:
            return try formatMarkdown(data)
        }
    }
    
    private func formatCSV(_ data: AnalyticsData) throws -> Data {
        var csv = "Timestamp,Metric Type,Value,Unit\n"
        
        // Storage Metrics
        for record in data.storageRecords {
            csv += "\(dateFormatter.string(from: record.timestamp)),Storage,\(record.metrics.totalBytes),bytes\n"
            csv += "\(dateFormatter.string(from: record.timestamp)),Compressed,\(record.metrics.compressedBytes),bytes\n"
            csv += "\(dateFormatter.string(from: record.timestamp)),Deduplicated,\(record.metrics.deduplicatedBytes),bytes\n"
        }
        
        // Transfer Metrics
        for record in data.transferRecords {
            csv += "\(dateFormatter.string(from: record.timestamp)),Uploaded,\(record.metrics.uploadedBytes),bytes\n"
            csv += "\(dateFormatter.string(from: record.timestamp)),Downloaded,\(record.metrics.downloadedBytes),bytes\n"
            csv += "\(dateFormatter.string(from: record.timestamp)),Transfer Rate,\(record.metrics.averageTransferSpeed),bytes/s\n"
        }
        
        // Cost Metrics
        for record in data.costRecords {
            csv += "\(dateFormatter.string(from: record.timestamp)),Storage Cost,\(record.metrics.storageUnitCost),currency\n"
            csv += "\(dateFormatter.string(from: record.timestamp)),Transfer Cost,\(record.metrics.transferUnitCost),currency\n"
        }
        
        // Snapshot Metrics
        for record in data.snapshotRecords {
            csv += "\(dateFormatter.string(from: record.timestamp)),Snapshots,\(record.metrics.totalSnapshots),count\n"
            csv += "\(dateFormatter.string(from: record.timestamp)),Average Size,\(record.metrics.averageSnapshotSize),bytes\n"
        }
        
        return csv.data(using: .utf8) ?? Data()
    }
    
    private func formatJSON(_ data: AnalyticsData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(data)
    }
    
    private func formatMarkdown(_ data: AnalyticsData) throws -> Data {
        var markdown = "# Cloud Analytics Report\n\n"
        
        // Storage Section
        markdown += "## Storage Metrics\n\n"
        markdown += "| Timestamp | Total Size | Compressed | Deduplicated |\n"
        markdown += "|-----------|------------|------------|-------------|\n"
        
        for record in data.storageRecords {
            markdown += "| \(dateFormatter.string(from: record.timestamp)) | "
            markdown += "\(byteFormatter.string(fromByteCount: record.metrics.totalBytes)) | "
            markdown += "\(byteFormatter.string(fromByteCount: record.metrics.compressedBytes)) | "
            markdown += "\(byteFormatter.string(fromByteCount: record.metrics.deduplicatedBytes)) |\n"
        }
        
        // Transfer Section
        markdown += "\n## Transfer Metrics\n\n"
        markdown += "| Timestamp | Uploaded | Downloaded | Average Speed |\n"
        markdown += "|-----------|----------|------------|---------------|\n"
        
        for record in data.transferRecords {
            markdown += "| \(dateFormatter.string(from: record.timestamp)) | "
            markdown += "\(byteFormatter.string(fromByteCount: record.metrics.uploadedBytes)) | "
            markdown += "\(byteFormatter.string(fromByteCount: record.metrics.downloadedBytes)) | "
            markdown += "\(byteFormatter.string(fromByteCount: Int64(record.metrics.averageTransferSpeed)))/s |\n"
        }
        
        // Cost Section
        markdown += "\n## Cost Metrics\n\n"
        markdown += "| Timestamp | Storage Cost | Transfer Cost | Total Cost |\n"
        markdown += "|-----------|--------------|---------------|------------|\n"
        
        for record in data.costRecords {
            let storageCost = numberFormatter.string(from: NSNumber(value: record.metrics.storageUnitCost)) ?? "0"
            let transferCost = numberFormatter.string(from: NSNumber(value: record.metrics.transferUnitCost)) ?? "0"
            let totalCost = numberFormatter.string(from: NSNumber(value: record.metrics.totalCost)) ?? "0"
            
            markdown += "| \(dateFormatter.string(from: record.timestamp)) | "
            markdown += "$\(storageCost) | $\(transferCost) | $\(totalCost) |\n"
        }
        
        // Snapshot Section
        markdown += "\n## Snapshot Metrics\n\n"
        markdown += "| Timestamp | Total Snapshots | Average Size | Retention Days |\n"
        markdown += "|-----------|-----------------|--------------|---------------|\n"
        
        for record in data.snapshotRecords {
            markdown += "| \(dateFormatter.string(from: record.timestamp)) | "
            markdown += "\(record.metrics.totalSnapshots) | "
            markdown += "\(byteFormatter.string(fromByteCount: record.metrics.averageSnapshotSize)) | "
            markdown += "\(record.metrics.retentionDays) |\n"
        }
        
        return markdown.data(using: .utf8) ?? Data()
    }
}

// MARK: - Supporting Types

enum ExportFormat: String, CaseIterable {
    case csv = "CSV"
    case json = "JSON"
    case markdown = "Markdown"
    
    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .markdown: return "md"
        }
    }
    
    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .markdown: return .markdown
        }
    }
}

struct AnalyticsData: Codable {
    let storageRecords: [StorageRecord]
    let transferRecords: [TransferRecord]
    let costRecords: [CostRecord]
    let snapshotRecords: [SnapshotRecord]
}

struct AnalyticsTrends: Codable {
    let storage: TrendAnalysis
    let transfer: TrendAnalysis
    let cost: TrendAnalysis
    let snapshots: TrendAnalysis
}

struct AnalyticsReport: Codable {
    let repository: Repository
    let timeRange: TimeRange
    let data: AnalyticsData
    let trends: AnalyticsTrends
    let generatedAt: Date
    
    var summary: String {
        """
        Cloud Analytics Report
        Repository: \(repository.path.lastPathComponent)
        Time Range: \(timeRange.displayName)
        Generated: \(generatedAt)
        
        Storage Trend: \(trends.storage.trend.description) (\(String(format: "%.1f%%", trends.storage.changeRate * 100)) change)
        Transfer Trend: \(trends.transfer.trend.description) (\(String(format: "%.1f%%", trends.transfer.changeRate * 100)) change)
        Cost Trend: \(trends.cost.trend.description) (\(String(format: "%.1f%%", trends.cost.changeRate * 100)) change)
        Snapshot Trend: \(trends.snapshots.trend.description) (\(String(format: "%.1f%%", trends.snapshots.changeRate * 100)) change)
        """
    }
}
