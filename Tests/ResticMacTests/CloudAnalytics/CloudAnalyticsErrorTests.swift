import XCTest
@testable import ResticMac

final class CloudAnalyticsErrorTests: XCTestCase {
    var scheduler: CloudAnalyticsScheduler!
    var visualization: CloudAnalyticsVisualization!
    var synchronization: CloudAnalyticsSynchronization!
    var intelligence: CloudAnalyticsIntelligence!
    var filter: CloudAnalyticsFilter!
    var verification: CloudAnalyticsVerification!
    var mockPersistence: MockErrorPersistence!
    var mockRepository: Repository!
    var mockMonitor: MockCloudAnalyticsMonitor!
    var mockSecurity: MockErrorSecurityManager!
    
    override func setUp() async throws {
        mockPersistence = MockErrorPersistence()
        mockMonitor = MockCloudAnalyticsMonitor()
        mockSecurity = MockErrorSecurityManager()
        mockRepository = Repository(
            path: URL(fileURLWithPath: "/test/repo"),
            password: "test",
            provider: .local
        )
        
        scheduler = CloudAnalyticsScheduler(
            persistence: mockPersistence,
            monitor: mockMonitor,
            notifications: MockErrorNotifications()
        )
        
        visualization = CloudAnalyticsVisualization(
            persistence: mockPersistence,
            monitor: mockMonitor,
            chartCustomization: MockErrorChartCustomization()
        )
        
        synchronization = CloudAnalyticsSynchronization(
            persistence: mockPersistence,
            monitor: mockMonitor,
            securityManager: mockSecurity
        )
        
        intelligence = CloudAnalyticsIntelligence(
            persistence: mockPersistence,
            monitor: mockMonitor
        )
        
        filter = CloudAnalyticsFilter(
            persistence: mockPersistence,
            monitor: mockMonitor
        )
        
        verification = CloudAnalyticsVerification(
            persistence: mockPersistence,
            monitor: mockMonitor,
            securityManager: mockSecurity
        )
    }
    
    override func tearDown() async throws {
        scheduler = nil
        visualization = nil
        synchronization = nil
        intelligence = nil
        filter = nil
        verification = nil
        mockPersistence = nil
        mockMonitor = nil
        mockSecurity = nil
        mockRepository = nil
    }
    
    // MARK: - Scheduler Error Tests
    
    func testScheduleCreationWithInvalidFrequency() async throws {
        // Given
        let schedule = AnalyticsSchedule(
            name: "Invalid Schedule",
            description: "Test Description",
            frequency: .interval(-1), // Invalid interval
            tasks: [.generateReport(.executive)]
        )
        
        // When/Then
        await XCTAssertThrowsError(
            try await scheduler.createSchedule(schedule, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? SchedulerError,
                .validation("Interval must be at least 300 seconds")
            )
        }
    }
    
    func testScheduleExecutionWithMissingData() async throws {
        // Given
        let schedule = AnalyticsSchedule(
            name: "Test Schedule",
            description: "Test Description",
            frequency: .interval(300),
            tasks: [.exportData(.csv)]
        )
        mockPersistence.shouldSimulateDataMissing = true
        
        // When/Then
        await XCTAssertThrowsError(
            try await scheduler.executeSchedule(schedule, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? SchedulerError,
                .executionFailed(error: MockError.dataMissing)
            )
        }
    }
    
    // MARK: - Visualization Error Tests
    
    func testChartGenerationWithInvalidData() async throws {
        // Given
        let type = VisualizationType.storage
        mockPersistence.shouldSimulateInvalidData = true
        
        // When/Then
        await XCTAssertThrowsError(
            try await visualization.generateVisualization(type, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? VisualizationError,
                .generationFailed(error: MockError.invalidData)
            )
        }
    }
    
    func testInteractiveChartWithInvalidOptions() async throws {
        // Given
        let type = InteractiveChartType.timeSeriesComparison
        let data = ChartData(series: [])
        let options = InteractiveChartOptions(
            timeInterval: -1,
            xDomain: 0...0,
            yDomain: 0...0
        )
        
        // When/Then
        await XCTAssertThrowsError(
            try await visualization.createInteractiveChart(type, data: data, options: options)
        ) { error in
            XCTAssertEqual(
                error as? VisualizationError,
                .invalidData
            )
        }
    }
    
    // MARK: - Synchronization Error Tests
    
    func testSyncConfigurationWithInvalidCredentials() async throws {
        // Given
        let config = SyncConfiguration(
            provider: .iCloud,
            credentials: SyncCredentials(
                accessToken: "",
                refreshToken: nil,
                expiresAt: nil
            ),
            settings: SyncConfiguration.SyncSettings(
                interval: 300,
                dataTypes: [],
                compression: .balanced,
                encryption: .standard,
                retryPolicy: .init(
                    maxAttempts: 3,
                    initialDelay: 1,
                    maxDelay: 10
                )
            )
        )
        
        // When/Then
        await XCTAssertThrowsError(
            try await synchronization.configureSynchronisation(config, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? SyncError,
                .validation("Invalid credentials")
            )
        }
    }
    
    func testSyncWithNetworkFailure() async throws {
        mockPersistence.shouldSimulateNetworkError = true
        
        // When/Then
        await XCTAssertThrowsError(
            try await synchronization.startSynchronisation(for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? SyncError,
                .syncFailed(error: MockError.networkError)
            )
        }
    }
    
    // MARK: - Intelligence Error Tests
    
    func testModelTrainingWithInsufficientData() async throws {
        // Given
        let type = ModelType.costPrediction
        mockPersistence.shouldSimulateInsufficientData = true
        
        // When/Then
        await XCTAssertThrowsError(
            try await intelligence.trainModel(type, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? IntelligenceError,
                .insufficientData
            )
        }
    }
    
    func testPredictionWithoutModel() async throws {
        // Given
        let type = ModelType.costPrediction
        let input = MockPredictionInput()
        
        // When/Then
        await XCTAssertThrowsError(
            try await intelligence.predict(type, input: input)
        ) { error in
            XCTAssertEqual(
                error as? IntelligenceError,
                .modelNotFound
            )
        }
    }
    
    // MARK: - Filter Error Tests
    
    func testFilterCreationWithInvalidOperations() async throws {
        // Given
        let filter = AnalyticsFilter(
            operations: [], // Empty operations
            metadata: [:]
        )
        
        // When/Then
        await XCTAssertThrowsError(
            try await self.filter.createFilter(filter, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? FilterError,
                .validation("Filter must have at least one operation")
            )
        }
    }
    
    func testFilterApplicationWithInvalidData() async throws {
        // Given
        let filter = AnalyticsFilter(
            operations: [
                .threshold(ThresholdCondition(
                    value: Double.infinity,
                    comparison: .greaterThan
                ))
            ],
            metadata: [:]
        )
        let data = MockAnalyticsData()
        
        // When/Then
        let chain = try await self.filter.createFilter(filter, for: mockRepository)
        await XCTAssertThrowsError(
            try await self.filter.applyFilter(chain, to: data)
        ) { error in
            XCTAssertEqual(
                error as? FilterError,
                .validation("Invalid threshold condition")
            )
        }
    }
    
    // MARK: - Verification Error Tests
    
    func testVerificationWithCorruptedData() async throws {
        // Given
        mockPersistence.shouldSimulateCorruptedData = true
        
        // When/Then
        await XCTAssertThrowsError(
            try await verification.startVerification(for: mockRepository)
        ) { error in
            if case let VerificationError.verificationFailed(innerError) = error {
                XCTAssertEqual(innerError as? MockError, .corruptedData)
            } else {
                XCTFail("Expected VerificationError.verificationFailed")
            }
        }
    }
    
    func testVerificationWithTimeoutError() async throws {
        // Given
        let options = VerificationOptions(
            depth: .full,
            parallelization: 4,
            timeoutInterval: 0.1, // Very short timeout
            retryAttempts: 1
        )
        mockPersistence.shouldSimulateTimeout = true
        
        // When/Then
        await XCTAssertThrowsError(
            try await verification.startVerification(
                for: mockRepository,
                options: options
            )
        ) { error in
            XCTAssertEqual(
                error as? VerificationError,
                .timeout
            )
        }
    }
}

// MARK: - Mock Error Types

enum MockError: Error, Equatable {
    case dataMissing
    case invalidData
    case networkError
    case corruptedData
    case timeout
}

// MARK: - Mock Error Implementations

class MockErrorPersistence: CloudAnalyticsPersistence {
    var shouldSimulateDataMissing = false
    var shouldSimulateInvalidData = false
    var shouldSimulateNetworkError = false
    var shouldSimulateInsufficientData = false
    var shouldSimulateCorruptedData = false
    var shouldSimulateTimeout = false
    
    func getStorageMetrics(for repository: Repository) async throws -> StorageMetrics {
        if shouldSimulateDataMissing {
            throw MockError.dataMissing
        }
        if shouldSimulateInvalidData {
            throw MockError.invalidData
        }
        return StorageMetrics(totalBytes: 0, compressedBytes: 0, deduplicatedBytes: 0)
    }
    
    // Additional persistence methods would be implemented here
}

class MockErrorSecurityManager: SecurityManager {
    func getSyncEncryptionKey() async throws -> SymmetricKey {
        throw MockError.invalidData
    }
}

class MockErrorNotifications: CloudAnalyticsNotifications {
    func scheduleNotification(withId id: UUID) async throws {
        throw MockError.networkError
    }
    
    func cancelNotification(withId id: UUID) async throws {
        throw MockError.networkError
    }
}

class MockErrorChartCustomization: CloudAnalyticsChartCustomization {
    // Implementation would simulate chart customization errors
}
