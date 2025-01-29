import XCTest
@testable import ResticMac

final class CloudAnalyticsIntegrationTests: XCTestCase {
    var analytics: CloudAnalytics!
    var persistence: CloudAnalyticsPersistence!
    var repository: Repository!
    var testDataDirectory: URL!
    
    override func setUp() async throws {
        // Set up test environment
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
        
        persistence = CloudAnalyticsPersistence(storageURL: testDataDirectory)
        analytics = CloudAnalytics(persistence: persistence)
        
        // Generate test data
        try await generateTestData()
    }
    
    override func tearDown() async throws {
        analytics = nil
        persistence = nil
        repository = nil
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Full Workflow Tests
    
    func testCompleteAnalyticsWorkflow() async throws {
        // 1. Import initial data
        try await importTestData()
        
        // 2. Collect metrics
        let storageMetrics = try await analytics.getStorageMetrics(for: repository)
        let transferMetrics = try await analytics.getTransferMetrics(for: repository)
        let costMetrics = try await analytics.getCostMetrics(for: repository)
        
        // 3. Validate metrics
        XCTAssertGreaterThan(storageMetrics.totalBytes, 0)
        XCTAssertGreaterThan(transferMetrics.totalTransferredBytes, 0)
        XCTAssertGreaterThan(costMetrics.totalCost, 0)
        
        // 4. Analyse trends
        let trend = try await analytics.analyzeStorageTrend(for: repository)
        XCTAssertNotNil(trend)
        
        // 5. Generate reports
        let report = try await analytics.generateAnalyticsReport(for: repository)
        XCTAssertNotNil(report)
        
        // 6. Export data
        let exportedData = try await analytics.exportData(for: repository, format: .json)
        XCTAssertNotNil(exportedData)
    }
    
    func testDataPersistenceAndRecovery() async throws {
        // 1. Save metrics
        let originalMetrics = StorageMetrics(
            totalBytes: 1000,
            compressedBytes: 800,
            deduplicatedBytes: 600
        )
        try await persistence.saveStorageMetrics(originalMetrics, for: repository)
        
        // 2. Simulate app restart
        analytics = nil
        persistence = nil
        analytics = CloudAnalytics(
            persistence: CloudAnalyticsPersistence(storageURL: testDataDirectory)
        )
        
        // 3. Verify data persistence
        let recoveredMetrics = try await analytics.getStorageMetrics(for: repository)
        XCTAssertEqual(recoveredMetrics.totalBytes, originalMetrics.totalBytes)
        XCTAssertEqual(recoveredMetrics.compressedBytes, originalMetrics.compressedBytes)
        XCTAssertEqual(recoveredMetrics.deduplicatedBytes, originalMetrics.deduplicatedBytes)
    }
    
    func testConcurrentOperations() async throws {
        // 1. Set up concurrent tasks
        async let storageTask = analytics.getStorageMetrics(for: repository)
        async let transferTask = analytics.getTransferMetrics(for: repository)
        async let costTask = analytics.getCostMetrics(for: repository)
        async let trendTask = analytics.analyzeStorageTrend(for: repository)
        
        // 2. Wait for all tasks
        let (storage, transfer, cost, trend) = try await (
            storageTask,
            transferTask,
            costTask,
            trendTask
        )
        
        // 3. Verify results
        XCTAssertNotNil(storage)
        XCTAssertNotNil(transfer)
        XCTAssertNotNil(cost)
        XCTAssertNotNil(trend)
    }
    
    func testErrorRecoveryAndDataIntegrity() async throws {
        // 1. Introduce corrupted data
        try await persistence.saveStorageMetrics(
            StorageMetrics(totalBytes: -1000, compressedBytes: 800, deduplicatedBytes: 600),
            for: repository
        )
        
        // 2. Attempt to read and recover
        do {
            _ = try await analytics.getStorageMetrics(for: repository)
            XCTFail("Should throw error for invalid data")
        } catch {
            // 3. Verify error handling
            XCTAssertTrue(error is CloudAnalyticsError)
            
            // 4. Attempt recovery
            try await analytics.repairStorageMetrics(for: repository)
            
            // 5. Verify recovered data
            let repairedMetrics = try await analytics.getStorageMetrics(for: repository)
            XCTAssertGreaterThanOrEqual(repairedMetrics.totalBytes, 0)
        }
    }
    
    func testAnalyticsChain() async throws {
        // 1. Initial collection
        let metrics = try await analytics.getStorageMetrics(for: repository)
        
        // 2. Trend analysis
        let trend = try await analytics.analyzeStorageTrend(for: repository)
        
        // 3. Cost projection
        let projection = try await analytics.projectCosts(
            basedOn: metrics,
            trend: trend,
            months: 12
        )
        
        // 4. Optimisation recommendations
        let recommendations = try await analytics.generateOptimisationRecommendations(
            basedOn: metrics,
            trend: trend,
            projection: projection
        )
        
        // 5. Verify chain results
        XCTAssertNotNil(metrics)
        XCTAssertNotNil(trend)
        XCTAssertNotNil(projection)
        XCTAssertFalse(recommendations.isEmpty)
    }
    
    // MARK: - Helper Methods
    
    private func generateTestData() async throws {
        let startDate = Date()
        var storageHistory: [StorageMetrics] = []
        var transferHistory: [TransferMetrics] = []
        var costHistory: [CostMetrics] = []
        
        for i in 0..<100 {
            let timestamp = startDate.addingTimeInterval(Double(i * 86400))
            
            // Storage metrics with realistic growth pattern
            let baseStorage = Double(i * 1000)
            let randomFactor = Double.random(in: 0.9...1.1)
            let storageMetrics = StorageMetrics(
                totalBytes: Int64(baseStorage * randomFactor),
                compressedBytes: Int64(baseStorage * 0.8 * randomFactor),
                deduplicatedBytes: Int64(baseStorage * 0.6 * randomFactor)
            )
            storageHistory.append(storageMetrics)
            
            // Transfer metrics with daily fluctuations
            let transferMetrics = TransferMetrics(
                uploadedBytes: Int64(Double(i * 100) * randomFactor),
                downloadedBytes: Int64(Double(i * 50) * randomFactor),
                averageTransferSpeed: Double(i * 10) * randomFactor,
                successRate: Double.random(in: 0.95...1.0)
            )
            transferHistory.append(transferMetrics)
            
            // Cost metrics with realistic pricing
            let costMetrics = CostMetrics(
                storageUnitCost: 0.02,
                transferUnitCost: 0.01,
                totalCost: Double(i) * 0.05 * randomFactor
            )
            costHistory.append(costMetrics)
            
            // Save metrics with timestamps
            try await persistence.saveStorageMetricsHistory(
                storageHistory,
                for: repository,
                timestamp: timestamp
            )
            try await persistence.saveTransferMetricsHistory(
                transferHistory,
                for: repository,
                timestamp: timestamp
            )
            try await persistence.saveCostMetricsHistory(
                costHistory,
                for: repository,
                timestamp: timestamp
            )
        }
    }
    
    private func importTestData() async throws {
        let csvURL = testDataDirectory.appendingPathComponent("test_import.csv")
        let csvContent = """
        timestamp,total_bytes,compressed_bytes,deduplicated_bytes,uploaded_bytes,downloaded_bytes,transfer_speed,storage_cost,transfer_cost,snapshot_count,average_snapshot_size
        2025-01-01T00:00:00Z,1000,800,600,100,50,1000,0.02,0.01,5,200
        2025-01-02T00:00:00Z,1200,900,700,150,75,1200,0.02,0.01,6,200
        """
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
        
        let importer = CloudAnalyticsImport(persistence: persistence)
        try await importer.importAnalytics(from: csvURL, for: repository)
    }
}

// MARK: - Test Extensions

extension CloudAnalytics {
    func repairStorageMetrics(for repository: Repository) async throws {
        // Implement repair logic
        let validator = CloudAnalyticsValidation()
        let metrics = StorageMetrics(totalBytes: 0, compressedBytes: 0, deduplicatedBytes: 0)
        try await persistence.saveStorageMetrics(metrics, for: repository)
    }
    
    func projectCosts(
        basedOn metrics: StorageMetrics,
        trend: TrendAnalysis,
        months: Int
    ) async throws -> CostProjection {
        // Implement cost projection
        return CostProjection(
            projectedStorageCost: 0,
            projectedTransferCost: 0,
            confidence: 1.0
        )
    }
    
    func generateOptimisationRecommendations(
        basedOn metrics: StorageMetrics,
        trend: TrendAnalysis,
        projection: CostProjection
    ) async throws -> [Recommendation] {
        // Implement recommendation generation
        return []
    }
}

struct CostProjection {
    let projectedStorageCost: Double
    let projectedTransferCost: Double
    let confidence: Double
}
