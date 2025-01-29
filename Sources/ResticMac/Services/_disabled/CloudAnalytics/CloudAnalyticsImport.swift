import Foundation
import UniformTypeIdentifiers

actor CloudAnalyticsImport {
    private let persistence: CloudAnalyticsPersistence
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsImport")
    
    init(persistence: CloudAnalyticsPersistence) {
        self.persistence = persistence
    }
    
    // MARK: - Import Functions
    
    func importAnalytics(from url: URL, for repository: Repository) async throws {
        let fileType = try identifyFileType(url)
        let data = try Data(contentsOf: url)
        
        switch fileType {
        case .csv:
            try await importCSV(data: data, repository: repository)
        case .json:
            try await importJSON(data: data, repository: repository)
        case .resticStats:
            try await importResticStats(data: data, repository: repository)
        }
    }
    
    // MARK: - Import Implementations
    
    private func importCSV(data: Data, repository: Repository) async throws {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidEncoding
        }
        
        var records: [ImportRecord] = []
        let rows = content.components(separatedBy: .newlines)
        
        // Validate header
        guard let header = rows.first else {
            throw ImportError.invalidFormat("Missing header row")
        }
        
        let columns = header.components(separatedBy: ",")
        try validateCSVHeader(columns)
        
        // Parse records
        for row in rows.dropFirst() where !row.isEmpty {
            let values = row.components(separatedBy: ",")
            guard values.count == columns.count else {
                throw ImportError.invalidFormat("Inconsistent column count")
            }
            
            try records.append(parseCSVRecord(values: values))
        }
        
        // Import records
        try await importRecords(records, for: repository)
    }
    
    private func importJSON(data: Data, repository: Repository) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let importData = try decoder.decode(AnalyticsImportData.self, from: data)
        try await importRecords(importData.records, for: repository)
    }
    
    private func importResticStats(data: Data, repository: Repository) async throws {
        let decoder = JSONDecoder()
        let stats = try decoder.decode(ResticStats.self, from: data)
        
        // Convert Restic stats to our format
        let records = try convertResticStats(stats)
        try await importRecords(records, for: repository)
    }
    
    // MARK: - Helper Functions
    
    private func identifyFileType(_ url: URL) throws -> ImportFileType {
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "csv":
            return .csv
        case "json":
            // Check if it's Restic stats or our format
            let data = try Data(contentsOf: url)
            if let _ = try? JSONDecoder().decode(ResticStats.self, from: data) {
                return .resticStats
            }
            return .json
        default:
            throw ImportError.unsupportedFileType
        }
    }
    
    private func validateCSVHeader(_ columns: [String]) throws {
        let requiredColumns = Set([
            "timestamp",
            "total_bytes",
            "compressed_bytes",
            "deduplicated_bytes",
            "uploaded_bytes",
            "downloaded_bytes",
            "transfer_speed",
            "storage_cost",
            "transfer_cost",
            "snapshot_count",
            "average_snapshot_size"
        ])
        
        let headerSet = Set(columns.map { $0.lowercased() })
        guard requiredColumns.isSubset(of: headerSet) else {
            throw ImportError.invalidFormat("Missing required columns")
        }
    }
    
    private func parseCSVRecord(values: [String]) throws -> ImportRecord {
        guard let timestamp = ISO8601DateFormatter().date(from: values[0]) else {
            throw ImportError.invalidFormat("Invalid timestamp format")
        }
        
        return ImportRecord(
            timestamp: timestamp,
            storageMetrics: StorageMetrics(
                totalBytes: Int64(values[1]) ?? 0,
                compressedBytes: Int64(values[2]) ?? 0,
                deduplicatedBytes: Int64(values[3]) ?? 0
            ),
            transferMetrics: TransferMetrics(
                uploadedBytes: Int64(values[4]) ?? 0,
                downloadedBytes: Int64(values[5]) ?? 0,
                averageTransferSpeed: Double(values[6]) ?? 0,
                successRate: 1.0
            ),
            costMetrics: CostMetrics(
                storageUnitCost: Double(values[7]) ?? 0,
                transferUnitCost: Double(values[8]) ?? 0,
                totalCost: 0 // Will be calculated
            ),
            snapshotMetrics: SnapshotMetrics(
                totalSnapshots: Int(values[9]) ?? 0,
                averageSnapshotSize: Int64(values[10]) ?? 0,
                retentionDays: 30 // Default value
            )
        )
    }
    
    private func convertResticStats(_ stats: ResticStats) throws -> [ImportRecord] {
        // Convert Restic's JSON stats format to our records
        var records: [ImportRecord] = []
        
        for snapshot in stats.snapshots {
            let record = ImportRecord(
                timestamp: snapshot.time,
                storageMetrics: StorageMetrics(
                    totalBytes: snapshot.stats.totalSize,
                    compressedBytes: snapshot.stats.totalSize - snapshot.stats.dataSize,
                    deduplicatedBytes: snapshot.stats.dataSize
                ),
                transferMetrics: TransferMetrics(
                    uploadedBytes: snapshot.stats.totalSize,
                    downloadedBytes: 0,
                    averageTransferSpeed: 0,
                    successRate: 1.0
                ),
                costMetrics: CostMetrics(
                    storageUnitCost: 0,
                    transferUnitCost: 0,
                    totalCost: 0
                ),
                snapshotMetrics: SnapshotMetrics(
                    totalSnapshots: stats.snapshots.count,
                    averageSnapshotSize: calculateAverageSize(stats.snapshots),
                    retentionDays: 30
                )
            )
            records.append(record)
        }
        
        return records
    }
    
    private func calculateAverageSize(_ snapshots: [ResticSnapshot]) -> Int64 {
        guard !snapshots.isEmpty else { return 0 }
        let totalSize = snapshots.reduce(0) { $0 + $1.stats.totalSize }
        return totalSize / Int64(snapshots.count)
    }
    
    private func importRecords(_ records: [ImportRecord], for repository: Repository) async throws {
        // Group records by type and save
        for record in records {
            try await persistence.saveStorageMetrics(record.storageMetrics, for: repository)
            try await persistence.saveTransferMetrics(record.transferMetrics, for: repository)
            try await persistence.saveCostMetrics(record.costMetrics, for: repository)
            try await persistence.saveSnapshotMetrics(record.snapshotMetrics, for: repository)
        }
        
        logger.info("Imported \(records.count) records for repository: \(repository.path.absoluteString)")
    }
}

// MARK: - Supporting Types

enum ImportFileType {
    case csv
    case json
    case resticStats
}

enum ImportError: LocalizedError {
    case unsupportedFileType
    case invalidEncoding
    case invalidFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Unsupported file type. Please use CSV or JSON format."
        case .invalidEncoding:
            return "Invalid file encoding. Please ensure the file is UTF-8 encoded."
        case .invalidFormat(let details):
            return "Invalid file format: \(details)"
        }
    }
}

struct ImportRecord {
    let timestamp: Date
    let storageMetrics: StorageMetrics
    let transferMetrics: TransferMetrics
    let costMetrics: CostMetrics
    let snapshotMetrics: SnapshotMetrics
}

struct AnalyticsImportData: Codable {
    let records: [ImportRecord]
}

struct ResticStats: Codable {
    let snapshots: [ResticSnapshot]
    let totalSize: Int64
    let totalFileCount: Int
}

struct ResticSnapshot: Codable {
    let id: String
    let time: Date
    let stats: ResticSnapshotStats
}

struct ResticSnapshotStats: Codable {
    let totalSize: Int64
    let dataSize: Int64
    let fileCount: Int
}
