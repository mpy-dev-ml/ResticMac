import XCTest
@testable import ResticMac

final class CloudAnalyticsRecoveryTests: XCTestCase {
    var recovery: CloudAnalyticsRecovery!
    var persistence: CloudAnalyticsPersistence!
    var monitor: CloudAnalyticsMonitor!
    var repository: Repository!
    var testDataDirectory: URL!
    
    override func setUp() async throws {
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacRecoveryTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        persistence = CloudAnalyticsPersistence(storageURL: testDataDirectory)
        monitor = CloudAnalyticsMonitor.shared
        recovery = CloudAnalyticsRecovery(persistence: persistence, monitor: monitor)
        
        repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
    }
    
    override func tearDown() async throws {
        recovery = nil
        persistence = nil
        monitor = nil
        repository = nil
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Checkpoint Tests
    
    func testCheckpointCreation() async throws {
        // Generate test data
        try await generateTestData()
        
        // Create checkpoint
        try await recovery.createCheckpoint(for: repository)
        
        // Verify checkpoint exists
        let checkpoints = try FileManager.default.contentsOfDirectory(at: testDataDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.starts(with: "checkpoint_") }
        
        XCTAssertFalse(checkpoints.isEmpty)
    }
    
    func testCheckpointPruning() async throws {
        // Create multiple checkpoints
        for _ in 0..<10 {
            try await generateTestData()
            try await recovery.createCheckpoint(for: repository)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        // Verify checkpoint limit
        let checkpoints = try FileManager.default.contentsOfDirectory(at: testDataDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.starts(with: "checkpoint_") }
        
        XCTAssertLessThanOrEqual(checkpoints.count, 5)
    }
    
    // MARK: - Recovery Tests
    
    func testSuccessfulRecovery() async throws {
        // Generate and save original data
        let originalMetrics = try await generateTestData()
        try await recovery.createCheckpoint(for: repository)
        
        // Clear persistence
        try await persistence.clearMetrics(for: repository)
        
        // Recover from checkpoint
        let result = try await recovery.recoverFromCrash(for: repository)
        
        // Verify recovery
        if case .success = result {
            let recoveredMetrics = try await persistence.getStorageMetrics(for: repository)
            XCTAssertEqual(recoveredMetrics.totalBytes, originalMetrics.totalBytes)
            XCTAssertEqual(recoveredMetrics.compressedBytes, originalMetrics.compressedBytes)
            XCTAssertEqual(recoveredMetrics.deduplicatedBytes, originalMetrics.deduplicatedBytes)
        } else {
            XCTFail("Recovery failed")
        }
    }
    
    func testRecoveryWithNoCheckpoint() async throws {
        let result = try await recovery.recoverFromCrash(for: repository)
        
        if case .noCheckpointFound = result {
            // Expected result
        } else {
            XCTFail("Expected no checkpoint found")
        }
    }
    
    func testRecoveryWithCorruptedCheckpoint() async throws {
        // Create valid checkpoint
        try await generateTestData()
        try await recovery.createCheckpoint(for: repository)
        
        // Corrupt the checkpoint file
        let checkpoints = try FileManager.default.contentsOfDirectory(at: testDataDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.starts(with: "checkpoint_") }
        
        if let checkpoint = checkpoints.first {
            try "corrupted data".write(to: checkpoint, atomically: true, encoding: .utf8)
        }
        
        // Attempt recovery
        let result = try await recovery.recoverFromCrash(for: repository)
        
        if case .checkpointCorrupted = result {
            // Expected result
        } else {
            XCTFail("Expected checkpoint corrupted")
        }
    }
    
    // MARK: - Automatic Recovery Tests
    
    func testAutomaticRecoveryTrigger() async throws {
        let recoveryExpectation = expectation(description: "Recovery triggered")
        
        // Enable automatic recovery
        await recovery.enableAutomaticRecovery()
        
        // Simulate unhealthy system state
        await monitor.recordMetric(.errorRate, value: 1.0) // 100% error rate
        
        // Wait for recovery to trigger
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            recoveryExpectation.fulfill()
        }
        
        await fulfillment(of: [recoveryExpectation], timeout: 10)
        
        // Verify emergency checkpoint was created
        let checkpoints = try FileManager.default.contentsOfDirectory(at: testDataDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.starts(with: "checkpoint_") }
        
        XCTAssertFalse(checkpoints.isEmpty)
    }
    
    func testConcurrentRecoveryOperations() async throws {
        // Generate test data
        try await generateTestData()
        
        // Perform concurrent operations
        await withThrowingTaskGroup(of: Void.self) { group in
            // Create checkpoints
            for _ in 0..<5 {
                group.addTask {
                    try await self.recovery.createCheckpoint(for: self.repository)
                }
            }
            
            // Attempt recoveries
            for _ in 0..<5 {
                group.addTask {
                    let result = try await self.recovery.recoverFromCrash(for: self.repository)
                    if case .success = result {
                        // Expected result
                    } else {
                        XCTFail("Recovery failed")
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateTestData() async throws -> StorageMetrics {
        let metrics = StorageMetrics(
            totalBytes: Int64.random(in: 1000...1000000),
            compressedBytes: Int64.random(in: 800...800000),
            deduplicatedBytes: Int64.random(in: 600...600000)
        )
        
        try await persistence.saveStorageMetrics(metrics, for: repository)
        return metrics
    }
}

// MARK: - Test Extensions

extension CloudAnalyticsPersistence {
    func clearMetrics(for repository: Repository) async throws {
        // Implement clear metrics for testing
    }
    
    func getAllRepositories() async throws -> [Repository] {
        return [repository]
    }
}
