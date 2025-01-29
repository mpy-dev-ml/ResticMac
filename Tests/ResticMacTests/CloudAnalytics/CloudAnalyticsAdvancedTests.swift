import XCTest
@testable import ResticMac

final class CloudAnalyticsAdvancedTests: XCTestCase {
    var analytics: CloudAnalytics!
    var scheduler: CloudAnalyticsScheduler!
    var visualization: CloudAnalyticsVisualization!
    var synchronization: CloudAnalyticsSynchronization!
    var intelligence: CloudAnalyticsIntelligence!
    var filter: CloudAnalyticsFilter!
    var verification: CloudAnalyticsVerification!
    var mockPersistence: MockCloudAnalyticsPersistence!
    var mockRepository: Repository!
    var mockMonitor: MockCloudAnalyticsMonitor!
    var mockSecurity: MockSecurityManager!
    
    override func setUp() async throws {
        mockPersistence = MockCloudAnalyticsPersistence()
        mockMonitor = MockCloudAnalyticsMonitor()
        mockSecurity = MockSecurityManager()
        mockRepository = Repository(
            path: URL(fileURLWithPath: "/test/repo"),
            password: "test",
            provider: .local
        )
        
        scheduler = CloudAnalyticsScheduler(
            persistence: mockPersistence,
            monitor: mockMonitor,
            notifications: MockCloudAnalyticsNotifications()
        )
        
        visualization = CloudAnalyticsVisualization(
            persistence: mockPersistence,
            monitor: mockMonitor,
            chartCustomization: MockCloudAnalyticsChartCustomization()
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
    
    // MARK: - Scheduler Tests
    
    func testScheduleCreation() async throws {
        // Given
        let schedule = AnalyticsSchedule(
            name: "Test Schedule",
            description: "Test Description",
            frequency: .daily(3600), // 1 hour after midnight
            tasks: [.generateReport(.executive)],
            requiresPower: true
        )
        
        // When
        try await scheduler.createSchedule(schedule, for: mockRepository)
        
        // Then
        let savedSchedule = try await mockPersistence.getSchedule(id: schedule.id)
        XCTAssertEqual(savedSchedule?.name, "Test Schedule")
        XCTAssertEqual(savedSchedule?.frequency, .daily(3600))
    }
    
    func testScheduleExecution() async throws {
        // Given
        let schedule = AnalyticsSchedule(
            name: "Test Schedule",
            description: "Test Description",
            frequency: .interval(300),
            tasks: [.exportData(.csv)]
        )
        
        // When
        try await scheduler.createSchedule(schedule, for: mockRepository)
        try await scheduler.executeSchedule(schedule, for: mockRepository)
        
        // Then
        XCTAssertTrue(mockMonitor.operationExecuted("execute_schedule"))
    }
    
    // MARK: - Visualization Tests
    
    func testChartGeneration() async throws {
        // Given
        let type = VisualizationType.storage
        let options = VisualizationOptions()
        
        // When
        let chart = try await visualization.generateVisualization(
            type,
            for: mockRepository,
            options: options
        )
        
        // Then
        XCTAssertNotNil(chart)
        XCTAssertTrue(mockMonitor.operationExecuted("generate_visualization"))
    }
    
    func testInteractiveChart() async throws {
        // Given
        let type = InteractiveChartType.timeSeriesComparison
        let data = ChartData(series: [
            ChartSeries(name: "Usage", data: [1.0, 2.0, 3.0])
        ])
        let options = InteractiveChartOptions(
            timeInterval: 3600,
            xDomain: 0...10,
            yDomain: 0...5
        )
        
        // When
        let chart = try await visualization.createInteractiveChart(
            type,
            data: data,
            options: options
        )
        
        // Then
        XCTAssertNotNil(chart)
    }
    
    // MARK: - Synchronization Tests
    
    func testSyncConfiguration() async throws {
        // Given
        let config = SyncConfiguration(
            provider: .iCloud,
            credentials: SyncCredentials(
                accessToken: "test-token",
                refreshToken: nil,
                expiresAt: nil
            ),
            settings: SyncConfiguration.SyncSettings(
                interval: 300,
                dataTypes: [.metrics, .reports],
                compression: .balanced,
                encryption: .standard,
                retryPolicy: .init(
                    maxAttempts: 3,
                    initialDelay: 1,
                    maxDelay: 10
                )
            )
        )
        
        // When
        try await synchronization.configureSynchronisation(
            config,
            for: mockRepository
        )
        
        // Then
        XCTAssertTrue(mockMonitor.operationExecuted("configure_sync"))
    }
    
    // MARK: - Intelligence Tests
    
    func testModelTraining() async throws {
        // Given
        let type = ModelType.costPrediction
        let options = TrainingOptions(
            epochs: 10,
            batchSize: 32,
            learningRate: 0.001
        )
        
        // When
        try await intelligence.trainModel(
            type,
            for: mockRepository,
            options: options
        )
        
        // Then
        XCTAssertTrue(mockMonitor.operationExecuted("train_model"))
    }
    
    func testPrediction() async throws {
        // Given
        let type = ModelType.costPrediction
        let input = MockPredictionInput()
        let options = PredictionOptions(
            confidenceThreshold: 0.8,
            maxPredictions: 5
        )
        
        // When
        let prediction = try await intelligence.predict(
            type,
            input: input,
            options: options
        )
        
        // Then
        XCTAssertNotNil(prediction)
        XCTAssertTrue(mockMonitor.operationExecuted("predict"))
    }
    
    // MARK: - Filter Tests
    
    func testFilterCreation() async throws {
        // Given
        let filter = AnalyticsFilter(
            operations: [
                .timeRange(TimeRange(
                    start: Date(),
                    end: Date().addingTimeInterval(86400)
                )),
                .dataType([.metrics, .reports])
            ],
            metadata: ["source": "test"]
        )
        
        // When
        let chain = try await self.filter.createFilter(
            filter,
            for: mockRepository
        )
        
        // Then
        XCTAssertNotNil(chain)
        XCTAssertTrue(mockMonitor.operationExecuted("create_filter"))
    }
    
    func testFilterApplication() async throws {
        // Given
        let filter = AnalyticsFilter(
            operations: [
                .threshold(ThresholdCondition(
                    value: 100,
                    comparison: .greaterThan
                ))
            ],
            metadata: [:]
        )
        let data = MockAnalyticsData()
        let options = FilterOptions(
            cacheResults: true,
            parallelProcessing: false
        )
        
        // When
        let chain = try await self.filter.createFilter(
            filter,
            for: mockRepository
        )
        let result = try await self.filter.applyFilter(
            chain,
            to: data,
            options: options
        )
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(mockMonitor.operationExecuted("apply_filter"))
    }
    
    // MARK: - Verification Tests
    
    func testVerificationProcess() async throws {
        // Given
        let options = VerificationOptions(
            depth: .standard,
            parallelization: 4,
            timeoutInterval: 3600,
            retryAttempts: 3
        )
        
        // When
        let result = try await verification.startVerification(
            for: mockRepository,
            options: options
        )
        
        // Then
        XCTAssertTrue(result.isSuccessful)
        XCTAssertTrue(mockMonitor.operationExecuted("start_verification"))
    }
}

// MARK: - Mock Implementations

class MockCloudAnalyticsMonitor: CloudAnalyticsMonitor {
    private var executedOperations: Set<String> = []
    
    func trackOperation(_ name: String) async -> OperationTracker {
        executedOperations.insert(name)
        return MockOperationTracker()
    }
    
    func operationExecuted(_ name: String) -> Bool {
        return executedOperations.contains(name)
    }
}

class MockOperationTracker: OperationTracker {
    func stop() {}
}

class MockSecurityManager: SecurityManager {
    func getSyncEncryptionKey() async throws -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
}

class MockCloudAnalyticsNotifications: CloudAnalyticsNotifications {
    func scheduleNotification(withId id: UUID) async throws {}
    func cancelNotification(withId id: UUID) async throws {}
}

class MockCloudAnalyticsChartCustomization: CloudAnalyticsChartCustomization {}

struct MockPredictionInput: PredictionInput {}
struct MockAnalyticsData: AnalyticsData {
    var metrics: [AnalyticsMetric] = []
}

struct ChartSeries {
    let name: String
    let data: [Double]
}
