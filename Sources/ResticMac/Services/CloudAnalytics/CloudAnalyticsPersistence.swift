import Foundation
import os.log

actor CloudAnalyticsPersistence {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsPersistence")
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private var baseURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ResticMac/Analytics", isDirectory: true)
    }
    
    init() {
        createDirectoryIfNeeded()
        setupEncoder()
    }
    
    private func createDirectoryIfNeeded() {
        do {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create analytics directory: \(error.localizedDescription)")
        }
    }
    
    private func setupEncoder() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Storage Metrics
    
    func saveStorageMetrics(_ metrics: CloudAnalytics.StorageMetrics, for repository: Repository) async throws {
        let record = StorageRecord(
            timestamp: Date(),
            metrics: metrics,
            repositoryId: repository.path.absoluteString
        )
        
        try await saveRecord(record, type: .storage, repository: repository)
        try await pruneOldRecords(type: .storage, repository: repository)
    }
    
    func loadStorageMetrics(for repository: Repository, timeRange: TimeRange) async throws -> [StorageRecord] {
        return try await loadRecords(type: .storage, repository: repository, timeRange: timeRange)
    }
    
    // MARK: - Transfer Metrics
    
    func saveTransferMetrics(_ metrics: CloudAnalytics.TransferMetrics, for repository: Repository) async throws {
        let record = TransferRecord(
            timestamp: Date(),
            metrics: metrics,
            repositoryId: repository.path.absoluteString
        )
        
        try await saveRecord(record, type: .transfer, repository: repository)
        try await pruneOldRecords(type: .transfer, repository: repository)
    }
    
    func loadTransferMetrics(for repository: Repository, timeRange: TimeRange) async throws -> [TransferRecord] {
        return try await loadRecords(type: .transfer, repository: repository, timeRange: timeRange)
    }
    
    // MARK: - Cost Metrics
    
    func saveCostMetrics(_ metrics: CloudAnalytics.CostMetrics, for repository: Repository) async throws {
        let record = CostRecord(
            timestamp: Date(),
            metrics: metrics,
            repositoryId: repository.path.absoluteString
        )
        
        try await saveRecord(record, type: .cost, repository: repository)
        try await pruneOldRecords(type: .cost, repository: repository)
    }
    
    func loadCostMetrics(for repository: Repository, timeRange: TimeRange) async throws -> [CostRecord] {
        return try await loadRecords(type: .cost, repository: repository, timeRange: timeRange)
    }
    
    // MARK: - Snapshot Metrics
    
    func saveSnapshotMetrics(_ metrics: CloudAnalytics.SnapshotMetrics, for repository: Repository) async throws {
        let record = SnapshotRecord(
            timestamp: Date(),
            metrics: metrics,
            repositoryId: repository.path.absoluteString
        )
        
        try await saveRecord(record, type: .snapshot, repository: repository)
        try await pruneOldRecords(type: .snapshot, repository: repository)
    }
    
    func loadSnapshotMetrics(for repository: Repository, timeRange: TimeRange) async throws -> [SnapshotRecord] {
        return try await loadRecords(type: .snapshot, repository: repository, timeRange: timeRange)
    }
    
    // MARK: - Generic Record Handling
    
    private func saveRecord<T: Codable>(_ record: T, type: MetricType, repository: Repository) async throws {
        let filename = recordFilename(for: record, type: type, repository: repository)
        let url = baseURL.appendingPathComponent(filename)
        let data = try encoder.encode(record)
        try data.write(to: url)
        
        logger.debug("Saved \(type.rawValue) record for repository: \(repository.path.absoluteString)")
    }
    
    private func loadRecords<T: Codable>(
        type: MetricType,
        repository: Repository,
        timeRange: TimeRange
    ) async throws -> [T] {
        let pattern = recordPattern(type: type, repository: repository)
        let urls = try fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: Date()) ?? Date()
        
        return try urls
            .filter { $0.lastPathComponent.hasPrefix(pattern) }
            .filter { url in
                if let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    return date >= cutoffDate
                }
                return false
            }
            .compactMap { url -> T? in
                let data = try Data(contentsOf: url)
                return try decoder.decode(T.self, from: data)
            }
            .sorted { ($0 as? TimestampedRecord)?.timestamp ?? Date() < ($1 as? TimestampedRecord)?.timestamp ?? Date() }
    }
    
    private func pruneOldRecords(type: MetricType, repository: Repository) async throws {
        let pattern = recordPattern(type: type, repository: repository)
        let urls = try fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        let retentionPeriod = TimeInterval(type.retentionDays * 24 * 60 * 60)
        let cutoffDate = Date().addingTimeInterval(-retentionPeriod)
        
        for url in urls where url.lastPathComponent.hasPrefix(pattern) {
            let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modificationDate = attributes.contentModificationDate,
               modificationDate < cutoffDate {
                try fileManager.removeItem(at: url)
                logger.debug("Pruned old \(type.rawValue) record: \(url.lastPathComponent)")
            }
        }
    }
    
    private func recordFilename<T>(for record: T, type: MetricType, repository: Repository) -> String {
        let timestamp = (record as? TimestampedRecord)?.timestamp ?? Date()
        let dateFormatter = ISO8601DateFormatter()
        let timestampString = dateFormatter.string(from: timestamp)
        return "\(type.rawValue)_\(repository.path.absoluteString.hash)_\(timestampString).json"
    }
    
    private func recordPattern(type: MetricType, repository: Repository) -> String {
        return "\(type.rawValue)_\(repository.path.absoluteString.hash)"
    }
}

// MARK: - Record Types

protocol TimestampedRecord {
    var timestamp: Date { get }
}

struct StorageRecord: Codable, TimestampedRecord {
    let timestamp: Date
    let metrics: CloudAnalytics.StorageMetrics
    let repositoryId: String
}

struct TransferRecord: Codable, TimestampedRecord {
    let timestamp: Date
    let metrics: CloudAnalytics.TransferMetrics
    let repositoryId: String
}

struct CostRecord: Codable, TimestampedRecord {
    let timestamp: Date
    let metrics: CloudAnalytics.CostMetrics
    let repositoryId: String
}

struct SnapshotRecord: Codable, TimestampedRecord {
    let timestamp: Date
    let metrics: CloudAnalytics.SnapshotMetrics
    let repositoryId: String
}

// MARK: - Supporting Types

enum MetricType: String {
    case storage = "storage"
    case transfer = "transfer"
    case cost = "cost"
    case snapshot = "snapshot"
    
    var retentionDays: Int {
        switch self {
        case .storage: return 365  // 1 year
        case .transfer: return 90  // 3 months
        case .cost: return 730     // 2 years
        case .snapshot: return 180 // 6 months
        }
    }
}

extension TimeRange {
    var startDate: Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }
    
    static func dates(for range: TimeRange) -> [Date] {
        let calendar = Calendar.current
        let startDate = range.startDate
        let endDate = Date()
        
        var dates: [Date] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            dates.append(currentDate)
            if let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) {
                currentDate = nextDate
            } else {
                break
            }
        }
        
        return dates
    }
}
