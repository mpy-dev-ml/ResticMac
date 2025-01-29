import Foundation
import OSLog
import TabularData

actor CloudAnalyticsExporter {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsExporter")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    
    init(persistence: CloudAnalyticsPersistence, monitor: CloudAnalyticsMonitor) {
        self.persistence = persistence
        self.monitor = monitor
    }
    
    // MARK: - Data Export
    
    func exportData(
        _ data: ExportableData,
        to format: ExportFormat,
        options: ExportOptions = ExportOptions()
    ) async throws -> URL {
        let tracker = await monitor.trackOperation("export_data")
        defer { tracker.stop() }
        
        do {
            // Create export directory
            let exportURL = try createExportDirectory()
            
            // Generate filename
            let filename = generateFilename(for: data, format: format)
            let fileURL = exportURL.appendingPathComponent(filename)
            
            // Export data
            switch format {
            case .csv:
                try await exportToCSV(data, to: fileURL, options: options)
            case .excel:
                try await exportToExcel(data, to: fileURL, options: options)
            case .json:
                try await exportToJSON(data, to: fileURL, options: options)
            case .xml:
                try await exportToXML(data, to: fileURL, options: options)
            }
            
            logger.info("Exported data to: \(fileURL.path)")
            return fileURL
            
        } catch {
            logger.error("Export failed: \(error.localizedDescription)")
            throw ExportError.exportFailed(error: error)
        }
    }
    
    // MARK: - Batch Export
    
    func exportBatch(
        _ items: [ExportableData],
        to format: ExportFormat,
        options: BatchExportOptions = BatchExportOptions()
    ) async throws -> URL {
        let tracker = await monitor.trackOperation("batch_export")
        defer { tracker.stop() }
        
        do {
            // Create export directory
            let exportURL = try createExportDirectory()
            
            // Export each item
            var exportedFiles: [URL] = []
            for item in items {
                let fileURL = try await exportData(
                    item,
                    to: format,
                    options: options.itemOptions
                )
                exportedFiles.append(fileURL)
            }
            
            // Create archive if requested
            if options.createArchive {
                let archiveURL = try await createArchive(
                    containing: exportedFiles,
                    at: exportURL,
                    options: options
                )
                
                // Clean up individual files
                try cleanupExportedFiles(exportedFiles)
                
                return archiveURL
            }
            
            return exportURL
            
        } catch {
            logger.error("Batch export failed: \(error.localizedDescription)")
            throw ExportError.batchExportFailed(error: error)
        }
    }
    
    // MARK: - Format-Specific Exports
    
    private func exportToCSV(
        _ data: ExportableData,
        to url: URL,
        options: ExportOptions
    ) async throws {
        // Convert data to DataFrame
        let dataFrame = try await createDataFrame(from: data)
        
        // Configure CSV options
        var csvOptions = CSVWritingOptions()
        csvOptions.delimiter = options.csvOptions?.delimiter ?? ","
        csvOptions.includeHeader = options.csvOptions?.includeHeader ?? true
        csvOptions.dateFormat = options.csvOptions?.dateFormat ?? .iso8601
        
        // Write CSV
        try dataFrame.writeCSV(to: url, options: csvOptions)
    }
    
    private func exportToExcel(
        _ data: ExportableData,
        to url: URL,
        options: ExportOptions
    ) async throws {
        // Convert data to DataFrame
        let dataFrame = try await createDataFrame(from: data)
        
        // Configure Excel options
        let excelOptions = options.excelOptions ?? ExcelOptions()
        
        // Create workbook
        let workbook = try createExcelWorkbook(
            from: dataFrame,
            options: excelOptions
        )
        
        // Write Excel file
        try workbook.write(to: url)
    }
    
    private func exportToJSON(
        _ data: ExportableData,
        to url: URL,
        options: ExportOptions
    ) async throws {
        // Convert to JSON
        let jsonData = try await createJSONData(
            from: data,
            options: options.jsonOptions ?? JSONOptions()
        )
        
        // Write JSON
        try jsonData.write(to: url)
    }
    
    private func exportToXML(
        _ data: ExportableData,
        to url: URL,
        options: ExportOptions
    ) async throws {
        // Convert to XML
        let xmlData = try await createXMLData(
            from: data,
            options: options.xmlOptions ?? XMLOptions()
        )
        
        // Write XML
        try xmlData.write(to: url)
    }
    
    // MARK: - Data Conversion
    
    private func createDataFrame(
        from data: ExportableData
    ) async throws -> DataFrame {
        switch data {
        case .metrics(let metrics):
            return try await createMetricsDataFrame(metrics)
        case .report(let report):
            return try await createReportDataFrame(report)
        case .insights(let insights):
            return try await createInsightsDataFrame(insights)
        case .custom(let customData):
            return try await createCustomDataFrame(customData)
        }
    }
    
    private func createMetricsDataFrame(
        _ metrics: AnalyticsMetrics
    ) async throws -> DataFrame {
        var columns: [Column] = []
        
        // Add timestamp column
        columns.append(Column(name: "Timestamp", contents: metrics.timestamps))
        
        // Add storage metrics
        columns.append(Column(name: "Total Storage", contents: metrics.storage.total))
        columns.append(Column(name: "Used Storage", contents: metrics.storage.used))
        columns.append(Column(name: "Free Storage", contents: metrics.storage.free))
        
        // Add performance metrics
        columns.append(Column(name: "CPU Usage", contents: metrics.performance.cpuUsage))
        columns.append(Column(name: "Memory Usage", contents: metrics.performance.memoryUsage))
        columns.append(Column(name: "IO Operations", contents: metrics.performance.ioOperations))
        
        // Add cost metrics
        columns.append(Column(name: "Storage Cost", contents: metrics.costs.storageCost))
        columns.append(Column(name: "Transfer Cost", contents: metrics.costs.transferCost))
        columns.append(Column(name: "Total Cost", contents: metrics.costs.totalCost))
        
        return DataFrame(columns: columns)
    }
    
    private func createReportDataFrame(
        _ report: AnalyticsReport
    ) async throws -> DataFrame {
        var columns: [Column] = []
        
        // Add basic report info
        columns.append(Column(name: "Section", contents: report.sections.map { $0.title }))
        columns.append(Column(name: "Content", contents: report.sections.map { $0.content }))
        
        // Add insights
        columns.append(Column(name: "Insights", contents: report.insights.map { $0.description }))
        
        // Add recommendations
        columns.append(Column(
            name: "Recommendations",
            contents: report.recommendations.map { $0.description }
        ))
        
        return DataFrame(columns: columns)
    }
    
    private func createInsightsDataFrame(
        _ insights: [AnalyticsInsight]
    ) async throws -> DataFrame {
        return DataFrame(columns: [
            Column(name: "Title", contents: insights.map { $0.title }),
            Column(name: "Category", contents: insights.map { $0.category.rawValue }),
            Column(name: "Severity", contents: insights.map { $0.severity.rawValue }),
            Column(name: "Description", contents: insights.map { $0.description })
        ])
    }
    
    private func createCustomDataFrame(
        _ data: CustomExportData
    ) async throws -> DataFrame {
        // Implementation would handle custom data structures
        return DataFrame()
    }
    
    // MARK: - Helper Methods
    
    private func createExportDirectory() throws -> URL {
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResticMacExports")
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(
            at: exportURL,
            withIntermediateDirectories: true
        )
        
        return exportURL
    }
    
    private func generateFilename(
        for data: ExportableData,
        format: ExportFormat
    ) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let dataType = String(describing: data).components(separatedBy: ".").last ?? "data"
        return "resticmac_\(dataType)_\(timestamp).\(format.extension)"
    }
    
    private func createArchive(
        containing files: [URL],
        at directory: URL,
        options: BatchExportOptions
    ) async throws -> URL {
        let archiveURL = directory
            .appendingPathComponent("export_\(UUID().uuidString)")
            .appendingPathExtension("zip")
        
        // Create archive
        try await withCheckedThrowingContinuation { continuation in
            do {
                try FileManager.default.zipItem(
                    at: directory,
                    to: archiveURL
                )
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        
        return archiveURL
    }
    
    private func cleanupExportedFiles(_ files: [URL]) throws {
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// MARK: - Supporting Types

enum ExportableData {
    case metrics(AnalyticsMetrics)
    case report(AnalyticsReport)
    case insights([AnalyticsInsight])
    case custom(CustomExportData)
}

enum ExportFormat {
    case csv
    case excel
    case json
    case xml
    
    var `extension`: String {
        switch self {
        case .csv: return "csv"
        case .excel: return "xlsx"
        case .json: return "json"
        case .xml: return "xml"
        }
    }
}

struct ExportOptions {
    var csvOptions: CSVOptions?
    var excelOptions: ExcelOptions?
    var jsonOptions: JSONOptions?
    var xmlOptions: XMLOptions?
    
    struct CSVOptions {
        var delimiter: String = ","
        var includeHeader: Bool = true
        var dateFormat: DateFormat = .iso8601
        var encoding: String.Encoding = .utf8
        
        enum DateFormat {
            case iso8601
            case custom(String)
        }
    }
    
    struct ExcelOptions {
        var sheetName: String = "Data"
        var includeHeader: Bool = true
        var dateFormat: String?
        var autoFilter: Bool = true
        var freezeHeader: Bool = true
    }
    
    struct JSONOptions {
        var pretty: Bool = true
        var dateFormat: String?
        var encoding: String.Encoding = .utf8
    }
    
    struct XMLOptions {
        var rootElement: String = "data"
        var pretty: Bool = true
        var encoding: String.Encoding = .utf8
    }
}

struct BatchExportOptions {
    var itemOptions: ExportOptions = ExportOptions()
    var createArchive: Bool = true
    var archiveFormat: ArchiveFormat = .zip
    var includeMetadata: Bool = true
    
    enum ArchiveFormat {
        case zip
        case tar
        case tarGz
    }
}

protocol CustomExportData {
    func toDataFrame() throws -> DataFrame
    func toJSON() throws -> Data
    func toXML() throws -> Data
}

enum ExportError: Error {
    case exportFailed(error: Error)
    case batchExportFailed(error: Error)
    case invalidData
    case unsupportedFormat
    case archivingFailed
}
