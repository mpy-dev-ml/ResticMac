import Foundation
import OSLog
import TabularData

actor CloudAnalyticsExportUtils {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsExportUtils")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    
    init(persistence: CloudAnalyticsPersistence, monitor: CloudAnalyticsMonitor) {
        self.persistence = persistence
        self.monitor = monitor
    }
    
    // MARK: - Data Export
    
    func exportAnalytics(
        for repository: Repository,
        format: ExportFormat,
        timeRange: DateInterval? = nil
    ) async throws -> URL {
        let tracker = await monitor.trackOperation("export_analytics")
        defer { tracker.stop() }
        
        do {
            // Gather metrics
            let metrics = try await gatherMetrics(for: repository, timeRange: timeRange)
            
            // Convert to specified format
            let exportData = try await convertToFormat(metrics, format: format)
            
            // Save to file
            let exportURL = try createExportFile(
                for: repository,
                format: format,
                data: exportData
            )
            
            logger.info("Successfully exported analytics for repository: \(repository.id)")
            return exportURL
            
        } catch {
            logger.error("Failed to export analytics: \(error.localizedDescription)")
            throw ExportError.exportFailed(error: error)
        }
    }
    
    // MARK: - Batch Export
    
    func exportAllRepositories(
        format: ExportFormat,
        timeRange: DateInterval? = nil
    ) async throws -> [URL] {
        let repositories = try await persistence.getAllRepositories()
        var exportURLs: [URL] = []
        
        for repository in repositories {
            let url = try await exportAnalytics(
                for: repository,
                format: format,
                timeRange: timeRange
            )
            exportURLs.append(url)
        }
        
        return exportURLs
    }
    
    // MARK: - Format Conversion
    
    private func convertToFormat(_ metrics: AnalyticsMetrics, format: ExportFormat) async throws -> Data {
        switch format {
        case .json:
            return try await convertToJSON(metrics)
        case .csv:
            return try await convertToCSV(metrics)
        case .excel:
            return try await convertToExcel(metrics)
        case .sql:
            return try await convertToSQL(metrics)
        }
    }
    
    private func convertToJSON(_ metrics: AnalyticsMetrics) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(metrics)
    }
    
    private func convertToCSV(_ metrics: AnalyticsMetrics) async throws -> Data {
        var csvString = "timestamp,metric_type,value,unit\n"
        
        // Storage metrics
        for point in metrics.storageHistory {
            csvString += "\(point.timestamp.ISO8601Format()),total_bytes,\(point.value.totalBytes),bytes\n"
            csvString += "\(point.timestamp.ISO8601Format()),compressed_bytes,\(point.value.compressedBytes),bytes\n"
            csvString += "\(point.timestamp.ISO8601Format()),deduplicated_bytes,\(point.value.deduplicatedBytes),bytes\n"
        }
        
        // Transfer metrics
        for point in metrics.transferHistory {
            csvString += "\(point.timestamp.ISO8601Format()),uploaded_bytes,\(point.value.uploadedBytes),bytes\n"
            csvString += "\(point.timestamp.ISO8601Format()),downloaded_bytes,\(point.value.downloadedBytes),bytes\n"
            csvString += "\(point.timestamp.ISO8601Format()),transfer_speed,\(point.value.averageTransferSpeed),bytes/s\n"
        }
        
        // Cost metrics
        for point in metrics.costHistory {
            csvString += "\(point.timestamp.ISO8601Format()),storage_cost,\(point.value.storageUnitCost),currency\n"
            csvString += "\(point.timestamp.ISO8601Format()),transfer_cost,\(point.value.transferUnitCost),currency\n"
            csvString += "\(point.timestamp.ISO8601Format()),total_cost,\(point.value.totalCost),currency\n"
        }
        
        return csvString.data(using: .utf8) ?? Data()
    }
    
    private func convertToExcel(_ metrics: AnalyticsMetrics) async throws -> Data {
        var dataFrame = DataFrame()
        
        // Add columns
        dataFrame.addColumn(Column(name: "Timestamp", contents: [Date]()))
        dataFrame.addColumn(Column(name: "Metric Type", contents: [String]()))
        dataFrame.addColumn(Column(name: "Value", contents: [Double]()))
        dataFrame.addColumn(Column(name: "Unit", contents: [String]()))
        
        // Add data rows
        for point in metrics.storageHistory {
            dataFrame.append(row: [
                "Timestamp": point.timestamp,
                "Metric Type": "Storage",
                "Value": Double(point.value.totalBytes),
                "Unit": "bytes"
            ])
        }
        
        // Convert to Excel
        let excelData = try dataFrame.writeExcel()
        return excelData
    }
    
    private func convertToSQL(_ metrics: AnalyticsMetrics) async throws -> Data {
        var sql = """
        CREATE TABLE IF NOT EXISTS analytics_metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME,
            metric_type TEXT,
            value REAL,
            unit TEXT
        );
        
        """
        
        // Add insert statements
        for point in metrics.storageHistory {
            sql += """
            INSERT INTO analytics_metrics (timestamp, metric_type, value, unit)
            VALUES (
                '\(point.timestamp.ISO8601Format())',
                'storage',
                \(point.value.totalBytes),
                'bytes'
            );
            
            """
        }
        
        return sql.data(using: .utf8) ?? Data()
    }
    
    // MARK: - Helper Methods
    
    private func gatherMetrics(
        for repository: Repository,
        timeRange: DateInterval?
    ) async throws -> AnalyticsMetrics {
        let storageHistory = try await persistence.getStorageMetricsHistory(for: repository)
        let transferHistory = try await persistence.getTransferMetricsHistory(for: repository)
        let costHistory = try await persistence.getCostMetricsHistory(for: repository)
        
        // Filter by time range if specified
        let filteredStorage = timeRange.map { range in
            storageHistory.filter { range.contains($0.timestamp) }
        } ?? storageHistory
        
        let filteredTransfer = timeRange.map { range in
            transferHistory.filter { range.contains($0.timestamp) }
        } ?? transferHistory
        
        let filteredCost = timeRange.map { range in
            costHistory.filter { range.contains($0.timestamp) }
        } ?? costHistory
        
        return AnalyticsMetrics(
            storageHistory: filteredStorage,
            transferHistory: filteredTransfer,
            costHistory: filteredCost
        )
    }
    
    private func createExportFile(
        for repository: Repository,
        format: ExportFormat,
        data: Data
    ) throws -> URL {
        let exportDir = try exportDirectory()
        let timestamp = Date().ISO8601Format()
        let filename = "analytics_export_\(repository.id)_\(timestamp).\(format.fileExtension)"
        let fileURL = exportDir.appendingPathComponent(filename)
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    private func exportDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let exportDir = appSupport.appendingPathComponent("ResticMac/Exports/Analytics", isDirectory: true)
        
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        
        return exportDir
    }
}

// MARK: - Supporting Types

enum ExportFormat {
    case json
    case csv
    case excel
    case sql
    
    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .csv: return "csv"
        case .excel: return "xlsx"
        case .sql: return "sql"
        }
    }
}

enum ExportError: Error {
    case exportFailed(error: Error)
    case invalidFormat
    case invalidTimeRange
}

struct AnalyticsMetrics: Codable {
    let storageHistory: [TimeSeriesPoint<StorageMetrics>]
    let transferHistory: [TimeSeriesPoint<TransferMetrics>]
    let costHistory: [TimeSeriesPoint<CostMetrics>]
}

// MARK: - DataFrame Extensions

extension DataFrame {
    func writeExcel() throws -> Data {
        // Implement Excel conversion using a suitable library
        // This is a placeholder that would need actual implementation
        return Data()
    }
}
