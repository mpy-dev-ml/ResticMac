import Foundation
import OSLog

actor CloudAnalyticsMigration {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsMigration")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    private let recovery: CloudAnalyticsRecovery
    
    init(persistence: CloudAnalyticsPersistence, monitor: CloudAnalyticsMonitor, recovery: CloudAnalyticsRecovery) {
        self.persistence = persistence
        self.monitor = monitor
        self.recovery = recovery
    }
    
    // MARK: - Migration Management
    
    func checkAndPerformMigrations() async throws {
        let currentVersion = try await persistence.getCurrentSchemaVersion()
        let latestVersion = SchemaVersion.latest
        
        if currentVersion < latestVersion {
            logger.info("Starting migration from v\(currentVersion.rawValue) to v\(latestVersion.rawValue)")
            
            // Create backup before migration
            try await createMigrationBackup()
            
            // Perform migrations sequentially
            for version in currentVersion.nextVersion...latestVersion {
                try await performMigration(to: version)
            }
            
            // Update schema version
            try await persistence.updateSchemaVersion(to: latestVersion)
            
            logger.info("Migration completed successfully")
        }
    }
    
    private func performMigration(to version: SchemaVersion) async throws {
        logger.info("Performing migration to v\(version.rawValue)")
        
        let migrationTracker = await monitor.trackOperation("migration_to_v\(version.rawValue)")
        defer { migrationTracker.stop() }
        
        do {
            switch version {
            case .v1_0:
                try await migrateToV1_0()
            case .v1_1:
                try await migrateToV1_1()
            case .v1_2:
                try await migrateToV1_2()
            case .v2_0:
                try await migrateToV2_0()
            }
            
            await monitor.recordMetric(.migrationSuccess, value: 1.0)
        } catch {
            await monitor.recordMetric(.migrationFailure, value: 1.0)
            throw MigrationError.migrationFailed(version: version, error: error)
        }
    }
    
    // MARK: - Backup Management
    
    private func createMigrationBackup() async throws {
        logger.info("Creating pre-migration backup")
        
        let backupTracker = await monitor.trackOperation("migration_backup")
        defer { backupTracker.stop() }
        
        do {
            let repositories = try await persistence.getAllRepositories()
            for repository in repositories {
                try await recovery.createCheckpoint(for: repository)
            }
            
            // Export current schema and data
            let backup = try await createDataBackup()
            try await saveBackup(backup)
            
            logger.info("Migration backup created successfully")
        } catch {
            logger.error("Failed to create migration backup: \(error.localizedDescription)")
            throw MigrationError.backupFailed(error: error)
        }
    }
    
    private func createDataBackup() async throws -> MigrationBackup {
        let repositories = try await persistence.getAllRepositories()
        var repositoryData: [String: RepositoryBackup] = [:]
        
        for repository in repositories {
            let metrics = try await persistence.exportMetrics(for: repository)
            repositoryData[repository.id] = RepositoryBackup(
                repository: repository,
                metricsData: metrics
            )
        }
        
        return MigrationBackup(
            timestamp: Date(),
            schemaVersion: try await persistence.getCurrentSchemaVersion(),
            repositories: repositoryData
        )
    }
    
    private func saveBackup(_ backup: MigrationBackup) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        
        let backupURL = try backupDirectory()
            .appendingPathComponent("migration_backup_v\(backup.schemaVersion.rawValue)_\(backup.timestamp.ISO8601Format()).json")
        
        try data.write(to: backupURL)
    }
    
    // MARK: - Version-Specific Migrations
    
    private func migrateToV1_0() async throws {
        // Initial schema setup
        try await persistence.executeQuery("""
        CREATE TABLE IF NOT EXISTS analytics_metadata (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        """)
    }
    
    private func migrateToV1_1() async throws {
        // Add support for cost metrics
        let repositories = try await persistence.getAllRepositories()
        
        for repository in repositories {
            let storageMetrics = try await persistence.getStorageMetrics(for: repository)
            let transferMetrics = try await persistence.getTransferMetrics(for: repository)
            
            // Calculate and store initial cost metrics
            let costMetrics = CostMetrics(
                storageUnitCost: 0.02, // Default cost
                transferUnitCost: 0.01, // Default cost
                totalCost: calculateInitialCost(
                    storageBytes: storageMetrics.totalBytes,
                    transferredBytes: transferMetrics.totalTransferredBytes
                )
            )
            
            try await persistence.saveCostMetrics(costMetrics, for: repository)
        }
    }
    
    private func migrateToV1_2() async throws {
        // Add performance tracking
        try await persistence.executeQuery("""
        CREATE TABLE IF NOT EXISTS performance_metrics (
            id TEXT PRIMARY KEY,
            repository_id TEXT,
            metric_type TEXT,
            value REAL,
            timestamp DATETIME,
            FOREIGN KEY(repository_id) REFERENCES repositories(id)
        );
        """)
    }
    
    private func migrateToV2_0() async throws {
        // Major schema update with breaking changes
        let repositories = try await persistence.getAllRepositories()
        
        for repository in repositories {
            // 1. Export existing data
            let oldMetrics = try await persistence.exportMetrics(for: repository)
            
            // 2. Transform data to new schema
            let newMetrics = try await transformMetricsToV2(oldMetrics)
            
            // 3. Save transformed data
            try await persistence.importMetrics(newMetrics, for: repository)
        }
    }
    
    // MARK: - Recovery
    
    func rollbackMigration(to version: SchemaVersion) async throws {
        logger.warning("Rolling back migration to v\(version.rawValue)")
        
        let rollbackTracker = await monitor.trackOperation("migration_rollback")
        defer { rollbackTracker.stop() }
        
        do {
            // Find latest backup for target version
            let backup = try await findLatestBackup(for: version)
            
            // Restore from backup
            try await restoreFromBackup(backup)
            
            // Update schema version
            try await persistence.updateSchemaVersion(to: version)
            
            logger.info("Rollback completed successfully")
        } catch {
            logger.error("Rollback failed: \(error.localizedDescription)")
            throw MigrationError.rollbackFailed(error: error)
        }
    }
    
    private func findLatestBackup(for version: SchemaVersion) async throws -> MigrationBackup {
        let backups = try FileManager.default.contentsOfDirectory(
            at: try backupDirectory(),
            includingPropertiesForKeys: [.creationDateKey]
        )
        .filter { $0.lastPathComponent.contains("migration_backup_v\(version.rawValue)") }
        .sorted { file1, file2 in
            let date1 = try file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
            let date2 = try file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
            return date1 > date2
        }
        
        guard let latestBackup = backups.first else {
            throw MigrationError.noBackupFound(version: version)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: latestBackup)
        return try decoder.decode(MigrationBackup.self, from: data)
    }
    
    private func restoreFromBackup(_ backup: MigrationBackup) async throws {
        for (_, repositoryBackup) in backup.repositories {
            try await persistence.importMetrics(
                repositoryBackup.metricsData,
                for: repositoryBackup.repository
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func backupDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let backupDir = appSupport.appendingPathComponent("ResticMac/Backups/Analytics", isDirectory: true)
        
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        return backupDir
    }
    
    private func calculateInitialCost(storageBytes: Int64, transferredBytes: Int64) -> Double {
        let storageGB = Double(storageBytes) / 1_000_000_000.0
        let transferredGB = Double(transferredBytes) / 1_000_000_000.0
        
        return (storageGB * 0.02) + (transferredGB * 0.01)
    }
    
    private func transformMetricsToV2(_ oldMetrics: Data) async throws -> Data {
        // Implement v2 transformation logic
        return oldMetrics // Placeholder
    }
}

// MARK: - Supporting Types

enum SchemaVersion: Int, Comparable {
    case v1_0 = 100
    case v1_1 = 110
    case v1_2 = 120
    case v2_0 = 200
    
    static var latest: SchemaVersion { .v2_0 }
    
    var nextVersion: SchemaVersion {
        switch self {
        case .v1_0: return .v1_1
        case .v1_1: return .v1_2
        case .v1_2: return .v2_0
        case .v2_0: return .v2_0
        }
    }
    
    static func < (lhs: SchemaVersion, rhs: SchemaVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MigrationError: Error {
    case migrationFailed(version: SchemaVersion, error: Error)
    case backupFailed(error: Error)
    case rollbackFailed(error: Error)
    case noBackupFound(version: SchemaVersion)
}

struct MigrationBackup: Codable {
    let timestamp: Date
    let schemaVersion: SchemaVersion
    let repositories: [String: RepositoryBackup]
}

struct RepositoryBackup: Codable {
    let repository: Repository
    let metricsData: Data
}

// MARK: - Extensions

extension MetricType {
    static let migrationSuccess = MetricType.init(rawValue: "migration_success")
    static let migrationFailure = MetricType.init(rawValue: "migration_failure")
}
