import XCTest
@testable import ResticMac

final class CloudAnalyticsMigrationTests: XCTestCase {
    var migration: CloudAnalyticsMigration!
    var persistence: MockCloudAnalyticsPersistence!
    var monitor: CloudAnalyticsMonitor!
    var recovery: CloudAnalyticsRecovery!
    var testDataDirectory: URL!
    
    override func setUp() async throws {
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacMigrationTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        persistence = MockCloudAnalyticsPersistence(storageURL: testDataDirectory)
        monitor = CloudAnalyticsMonitor.shared
        recovery = CloudAnalyticsRecovery(persistence: persistence, monitor: monitor)
        migration = CloudAnalyticsMigration(persistence: persistence, monitor: monitor, recovery: recovery)
    }
    
    override func tearDown() async throws {
        migration = nil
        persistence = nil
        monitor = nil
        recovery = nil
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Migration Tests
    
    func testMigrationCheck() async throws {
        // Set initial version
        try await persistence.updateSchemaVersion(to: .v1_0)
        
        // Perform migration check
        try await migration.checkAndPerformMigrations()
        
        // Verify final version
        let finalVersion = try await persistence.getCurrentSchemaVersion()
        XCTAssertEqual(finalVersion, .v2_0)
    }
    
    func testSequentialMigrations() async throws {
        // Start from v1.0
        try await persistence.updateSchemaVersion(to: .v1_0)
        
        // Track migration steps
        var migrationSteps: [SchemaVersion] = []
        persistence.migrationCallback = { version in
            migrationSteps.append(version)
        }
        
        // Perform migrations
        try await migration.checkAndPerformMigrations()
        
        // Verify migration sequence
        XCTAssertEqual(migrationSteps, [.v1_1, .v1_2, .v2_0])
    }
    
    func testMigrationBackup() async throws {
        // Setup test data
        let repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
        
        let metrics = StorageMetrics(
            totalBytes: 1000,
            compressedBytes: 800,
            deduplicatedBytes: 600
        )
        
        try await persistence.saveStorageMetrics(metrics, for: repository)
        
        // Perform migration
        try await migration.checkAndPerformMigrations()
        
        // Verify backup exists
        let backups = try FileManager.default.contentsOfDirectory(at: testDataDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.starts(with: "migration_backup_") }
        
        XCTAssertFalse(backups.isEmpty)
    }
    
    // MARK: - Version-Specific Migration Tests
    
    func testMigrationToV1_1() async throws {
        // Set initial version
        try await persistence.updateSchemaVersion(to: .v1_0)
        
        // Setup test data
        let repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
        
        let storageMetrics = StorageMetrics(
            totalBytes: 1000,
            compressedBytes: 800,
            deduplicatedBytes: 600
        )
        
        let transferMetrics = TransferMetrics(
            uploadedBytes: 100,
            downloadedBytes: 50,
            averageTransferSpeed: 1000,
            successRate: 1.0
        )
        
        try await persistence.saveStorageMetrics(storageMetrics, for: repository)
        try await persistence.saveTransferMetrics(transferMetrics, for: repository)
        
        // Perform migration
        try await migration.checkAndPerformMigrations()
        
        // Verify cost metrics were created
        let costMetrics = try await persistence.getCostMetrics(for: repository)
        XCTAssertNotNil(costMetrics)
        XCTAssertGreaterThan(costMetrics.totalCost, 0)
    }
    
    func testMigrationToV2_0() async throws {
        // Set initial version
        try await persistence.updateSchemaVersion(to: .v1_2)
        
        // Setup test data
        let repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
        
        let metrics = StorageMetrics(
            totalBytes: 1000,
            compressedBytes: 800,
            deduplicatedBytes: 600
        )
        
        try await persistence.saveStorageMetrics(metrics, for: repository)
        
        // Perform migration
        try await migration.checkAndPerformMigrations()
        
        // Verify data was transformed
        let transformedMetrics = try await persistence.getStorageMetrics(for: repository)
        XCTAssertNotNil(transformedMetrics)
    }
    
    // MARK: - Rollback Tests
    
    func testMigrationRollback() async throws {
        // Setup initial state
        let repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
        
        let originalMetrics = StorageMetrics(
            totalBytes: 1000,
            compressedBytes: 800,
            deduplicatedBytes: 600
        )
        
        try await persistence.saveStorageMetrics(originalMetrics, for: repository)
        try await persistence.updateSchemaVersion(to: .v1_0)
        
        // Perform migration
        try await migration.checkAndPerformMigrations()
        
        // Verify migration occurred
        XCTAssertEqual(try await persistence.getCurrentSchemaVersion(), .v2_0)
        
        // Perform rollback
        try await migration.rollbackMigration(to: .v1_0)
        
        // Verify rollback
        XCTAssertEqual(try await persistence.getCurrentSchemaVersion(), .v1_0)
        
        let rolledBackMetrics = try await persistence.getStorageMetrics(for: repository)
        XCTAssertEqual(rolledBackMetrics.totalBytes, originalMetrics.totalBytes)
    }
    
    func testRollbackToNonexistentBackup() async throws {
        do {
            try await migration.rollbackMigration(to: .v1_0)
            XCTFail("Expected rollback to fail")
        } catch let error as MigrationError {
            if case .noBackupFound = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testMigrationFailure() async throws {
        // Setup failing persistence
        persistence.shouldFail = true
        
        do {
            try await migration.checkAndPerformMigrations()
            XCTFail("Expected migration to fail")
        } catch let error as MigrationError {
            if case .migrationFailed = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testBackupFailure() async throws {
        // Make backup directory read-only
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: testDataDirectory.path
        )
        
        do {
            try await migration.checkAndPerformMigrations()
            XCTFail("Expected backup to fail")
        } catch let error as MigrationError {
            if case .backupFailed = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

// MARK: - Test Helpers

class MockCloudAnalyticsPersistence: CloudAnalyticsPersistence {
    var shouldFail = false
    var migrationCallback: ((SchemaVersion) -> Void)?
    
    override func getCurrentSchemaVersion() async throws -> SchemaVersion {
        if shouldFail {
            throw NSError(domain: "TestError", code: -1)
        }
        return try await super.getCurrentSchemaVersion()
    }
    
    override func updateSchemaVersion(to version: SchemaVersion) async throws {
        if shouldFail {
            throw NSError(domain: "TestError", code: -1)
        }
        migrationCallback?(version)
        try await super.updateSchemaVersion(to: version)
    }
}
