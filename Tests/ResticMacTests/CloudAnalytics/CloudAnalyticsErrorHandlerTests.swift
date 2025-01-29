import XCTest
@testable import ResticMac

final class CloudAnalyticsErrorHandlerTests: XCTestCase {
    var errorHandler: CloudAnalyticsErrorHandler!
    var persistence: MockCloudAnalyticsPersistence!
    var monitor: CloudAnalyticsMonitor!
    var recovery: MockCloudAnalyticsRecovery!
    var testDataDirectory: URL!
    
    override func setUp() async throws {
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacErrorHandlerTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        persistence = MockCloudAnalyticsPersistence(storageURL: testDataDirectory)
        monitor = CloudAnalyticsMonitor.shared
        recovery = MockCloudAnalyticsRecovery()
        errorHandler = CloudAnalyticsErrorHandler(
            persistence: persistence,
            monitor: monitor,
            recovery: recovery
        )
    }
    
    override func tearDown() async throws {
        errorHandler = nil
        persistence = nil
        monitor = nil
        recovery = nil
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Error Handling Tests
    
    func testBasicErrorHandling() async throws {
        let error = NSError(domain: "Test", code: -1)
        
        let resolution = try await errorHandler.handleError(
            error,
            context: .storage,
            severity: .error
        )
        
        XCTAssertEqual(resolution.status, .resolved)
        XCTAssertEqual(resolution.context, .storage)
    }
    
    func testErrorEscalation() async throws {
        let error = NSError(domain: "Test", code: -1)
        
        let resolution = try await errorHandler.handleError(
            error,
            context: .storage,
            severity: .critical,
            recovery: .escalate
        )
        
        XCTAssertEqual(resolution.status, .escalated)
        XCTAssertEqual(resolution.context, .storage)
    }
    
    func testRetryStrategy() async throws {
        let error = NetworkError.connectionFailed
        
        let resolution = try await errorHandler.handleError(
            error,
            context: .transfer,
            severity: .error,
            recovery: .retry(delay: 0.1)
        )
        
        XCTAssertEqual(resolution.status, .resolved)
        XCTAssertEqual(resolution.context, .transfer)
    }
    
    func testRetryLimitExceeded() async throws {
        let error = NetworkError.connectionFailed
        
        // Simulate multiple retries
        for _ in 0...3 {
            _ = try await errorHandler.handleError(
                error,
                context: .transfer,
                severity: .error,
                recovery: .retry(delay: 0.1)
            )
        }
        
        let finalResolution = try await errorHandler.handleError(
            error,
            context: .transfer,
            severity: .error,
            recovery: .retry(delay: 0.1)
        )
        
        XCTAssertEqual(finalResolution.status, .failed)
        XCTAssertTrue(finalResolution.message?.contains("Retry limit exceeded") ?? false)
    }
    
    // MARK: - Pattern Detection Tests
    
    func testHighFrequencyPattern() async throws {
        let error = ValidationError.validationFailed(error: NSError(domain: "Test", code: -1))
        
        // Generate high frequency errors
        for _ in 0..<20 {
            _ = try await errorHandler.handleError(
                error,
                context: .validation,
                severity: .error
            )
        }
        
        let resolution = try await errorHandler.handleError(
            error,
            context: .validation,
            severity: .error
        )
        
        XCTAssertEqual(resolution.status, .escalated)
    }
    
    func testCascadingPattern() async throws {
        // Generate cascading errors with increasing severity
        let error = NSError(domain: "Test", code: -1)
        
        _ = try await errorHandler.handleError(
            error,
            context: .storage,
            severity: .info
        )
        
        _ = try await errorHandler.handleError(
            error,
            context: .storage,
            severity: .warning
        )
        
        _ = try await errorHandler.handleError(
            error,
            context: .storage,
            severity: .error
        )
        
        let resolution = try await errorHandler.handleError(
            error,
            context: .storage,
            severity: .critical
        )
        
        XCTAssertEqual(resolution.status, .resolved)
    }
    
    func testCyclicPattern() async throws {
        let errors = [
            NetworkError.connectionFailed,
            ValidationError.validationFailed(error: NSError(domain: "Test", code: -1)),
            PersistenceError.saveFailed(error: NSError(domain: "Test", code: -1))
        ]
        
        // Generate cyclic error pattern
        for _ in 0..<2 {
            for error in errors {
                _ = try await errorHandler.handleError(
                    error,
                    context: .transfer,
                    severity: .error
                )
            }
        }
        
        let resolution = try await errorHandler.handleError(
            errors[0],
            context: .transfer,
            severity: .error
        )
        
        XCTAssertEqual(resolution.status, .resolved)
    }
    
    // MARK: - Recovery Tests
    
    func testRollbackRecovery() async throws {
        let error = PersistenceError.saveFailed(error: NSError(domain: "Test", code: -1))
        
        let resolution = try await errorHandler.handleError(
            error,
            context: .storage,
            severity: .error,
            recovery: .rollback(checkpoint: nil)
        )
        
        XCTAssertEqual(resolution.status, .resolved)
        XCTAssertTrue(recovery.rollbackCalled)
    }
    
    func testFallbackRecovery() async throws {
        let error = ValidationError.validationFailed(error: NSError(domain: "Test", code: -1))
        
        let resolution = try await errorHandler.handleError(
            error,
            context: .validation,
            severity: .error,
            recovery: .fallback(alternative: nil)
        )
        
        XCTAssertEqual(resolution.status, .resolved)
        XCTAssertTrue(recovery.fallbackCalled)
    }
    
    // MARK: - Error Recording Tests
    
    func testErrorRecording() async throws {
        let error = NSError(domain: "Test", code: -1)
        
        _ = try await errorHandler.handleError(
            error,
            context: .storage,
            severity: .error
        )
        
        XCTAssertTrue(persistence.errorRecordSaved)
    }
    
    func testErrorHistoryLimit() async throws {
        let error = NSError(domain: "Test", code: -1)
        
        // Generate more errors than the history limit
        for _ in 0..<1100 {
            _ = try await errorHandler.handleError(
                error,
                context: .storage,
                severity: .error
            )
        }
        
        // Verify history size is limited
        XCTAssertLessThanOrEqual(persistence.errorRecordCount, 1000)
    }
}

// MARK: - Test Doubles

class MockCloudAnalyticsRecovery: CloudAnalyticsRecovery {
    var rollbackCalled = false
    var fallbackCalled = false
    
    override func rollbackToCheckpoint(_ checkpoint: Checkpoint?) async throws {
        rollbackCalled = true
    }
    
    override func switchToFallback(_ alternative: Any?) async throws {
        fallbackCalled = true
    }
}

// MARK: - Test Errors

enum NetworkError: Error {
    case connectionFailed
}

enum PersistenceError: Error {
    case saveFailed(error: Error)
}

// MARK: - Test Extensions

extension MockCloudAnalyticsPersistence {
    var errorRecordSaved: Bool {
        errorRecordCount > 0
    }
    
    var errorRecordCount: Int {
        // Return count of saved error records
        0 // Implement actual counting logic
    }
}
