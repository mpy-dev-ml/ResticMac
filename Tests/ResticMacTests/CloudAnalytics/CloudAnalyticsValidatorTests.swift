import XCTest
@testable import ResticMac

final class CloudAnalyticsValidatorTests: XCTestCase {
    var validator: CloudAnalyticsValidator!
    var persistence: MockCloudAnalyticsPersistence!
    var monitor: CloudAnalyticsMonitor!
    var testDataDirectory: URL!
    var repository: Repository!
    
    override func setUp() async throws {
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacValidatorTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        persistence = MockCloudAnalyticsPersistence(storageURL: testDataDirectory)
        monitor = CloudAnalyticsMonitor.shared
        validator = CloudAnalyticsValidator(persistence: persistence, monitor: monitor)
        
        repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
    }
    
    override func tearDown() async throws {
        validator = nil
        persistence = nil
        monitor = nil
        repository = nil
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Storage Validation Tests
    
    func testStorageValidation() async throws {
        // Generate valid storage metrics
        let storageMetrics = generateStorageMetrics(valid: true)
        try await persistence.saveStorageMetricsHistory(storageMetrics, for: repository)
        
        // Perform validation
        let report = try await validator.validateAnalytics(for: repository)
        
        // Verify results
        XCTAssertFalse(report.hasErrors)
        XCTAssertFalse(report.hasWarnings)
        XCTAssertEqual(report.storageValidation.totalPoints, storageMetrics.count)
    }
    
    func testInvalidStorageMetrics() async throws {
        // Generate invalid storage metrics
        let storageMetrics = generateStorageMetrics(valid: false)
        try await persistence.saveStorageMetricsHistory(storageMetrics, for: repository)
        
        // Perform validation
        let report = try await validator.validateAnalytics(for: repository)
        
        // Verify results
        XCTAssertTrue(report.hasErrors)
        XCTAssertTrue(report.storageValidation.issues.contains { $0.type == .invalidValue })
    }
    
    func testStorageGapDetection() async throws {
        // Generate storage metrics with gaps
        let storageMetrics = generateStorageMetricsWithGaps()
        try await persistence.saveStorageMetricsHistory(storageMetrics, for: repository)
        
        // Perform validation
        let report = try await validator.validateAnalytics(for: repository)
        
        // Verify results
        XCTAssertTrue(report.hasWarnings)
        XCTAssertTrue(report.storageValidation.issues.contains { $0.type == .dataGap })
    }
    
    // MARK: - Transfer Validation Tests
    
    func testTransferValidation() async throws {
        // Generate valid transfer metrics
        let transferMetrics = generateTransferMetrics(valid: true)
        try await persistence.saveTransferMetricsHistory(transferMetrics, for: repository)
        
        // Perform validation
        let report = try await validator.validateAnalytics(for: repository)
        
        // Verify results
        XCTAssertFalse(report.hasErrors)
        XCTAssertFalse(report.hasWarnings)
        XCTAssertEqual(report.transferValidation.totalPoints, transferMetrics.count)
    }
    
    func testInvalidTransferMetrics() async throws {
        // Generate invalid transfer metrics
        let transferMetrics = generateTransferMetrics(valid: false)
        try await persistence.saveTransferMetricsHistory(transferMetrics, for: repository)
        
        // Perform validation
        let report = try await validator.validateAnalytics(for: repository)
        
        // Verify results
        XCTAssertTrue(report.hasErrors)
        XCTAssertTrue(report.transferValidation.issues.contains { $0.type == .invalidValue })
    }
    
    func testTransferAnomalyDetection() async throws {
        // Generate transfer metrics with anomalies
        let transferMetrics = generateTransferMetricsWithAnomalies()
        try await persistence.saveTransferMetricsHistory(transferMetrics, for: repository)
        
        // Perform validation
        let report = try await validator.validateAnalytics(for: repository)
        
        // Verify results
        XCTAssertTrue(report.hasWarnings)
        XCTAssertTrue(report.transferValidation.issues.contains { $0.type == .anomaly })
    }
    
    // MARK: - Cost Validation Tests
    
    func testCostValidation() async throws {
        // Generate valid cost metrics
        let costMetrics = generateCostMetrics(valid: true)
        try await persistence.saveCostMetricsHistory(costMetrics, for: repository)
        
        // Perform validation
        let report = try await validator.validateAnalytics(for: repository)
        
        // Verify results
        XCTAssertFalse(report.hasErrors)
        XCTAssertFalse(report.hasWarnings)
        XCTAssertEqual(report.costValidation.totalPoints, costMetrics.count)
    }
    
    func testInvalidCostMetrics() async throws {
        // Generate invalid cost metrics
        let costMetrics = generateCostMetrics(valid: false)
        try await persistence.saveCostMetricsHistory(costMetrics, for: repository)
        
        // Perform validation
        let report = try await validator.validateAnalytics(for: repository)
        
        // Verify results
        XCTAssertTrue(report.hasErrors)
        XCTAssertTrue(report.costValidation.issues.contains { $0.type == .invalidValue })
    }
    
    func testCostConsistencyValidation() async throws {
        // Generate cost metrics with inconsistencies
        let costMetrics = generateCostMetricsWithInconsistencies()
        try await persistence.saveCostMetricsHistory(costMetrics, for: repository)
        
        // Perform validation
        let report = try await validator.validateAnalytics(for: repository)
        
        // Verify results
        XCTAssertTrue(report.hasWarnings)
        XCTAssertTrue(report.costValidation.issues.contains { $0.type == .inconsistency })
    }
    
    // MARK: - Time Range Tests
    
    func testTimeRangeValidation() async throws {
        // Generate metrics
        let storageMetrics = generateStorageMetrics(valid: true)
        try await persistence.saveStorageMetricsHistory(storageMetrics, for: repository)
        
        // Set time range
        let now = Date()
        let timeRange = DateInterval(
            start: now.addingTimeInterval(-3600), // 1 hour ago
            end: now
        )
        
        // Perform validation
        let report = try await validator.validateAnalytics(
            for: repository,
            timeRange: timeRange
        )
        
        // Verify results
        XCTAssertLessThanOrEqual(report.storageValidation.totalPoints, storageMetrics.count)
    }
    
    // MARK: - Helper Methods
    
    private func generateStorageMetrics(valid: Bool) -> [TimeSeriesPoint<StorageMetrics>] {
        let now = Date()
        var metrics: [TimeSeriesPoint<StorageMetrics>] = []
        
        for i in 0..<24 {
            let timestamp = now.addingTimeInterval(Double(-i * 3600))
            let totalBytes = valid ? Int64(i * 1000) : Int64(-1000)
            let compressedBytes = valid ? Int64(i * 800) : Int64(-800)
            let deduplicatedBytes = valid ? Int64(i * 600) : Int64(-600)
            
            metrics.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: StorageMetrics(
                    totalBytes: totalBytes,
                    compressedBytes: compressedBytes,
                    deduplicatedBytes: deduplicatedBytes
                )
            ))
        }
        
        return metrics
    }
    
    private func generateStorageMetricsWithGaps() -> [TimeSeriesPoint<StorageMetrics>] {
        let now = Date()
        var metrics: [TimeSeriesPoint<StorageMetrics>] = []
        
        for i in 0..<24 {
            // Create a gap every 6 hours
            if i % 6 != 0 {
                let timestamp = now.addingTimeInterval(Double(-i * 3600))
                metrics.append(TimeSeriesPoint(
                    timestamp: timestamp,
                    value: StorageMetrics(
                        totalBytes: Int64(i * 1000),
                        compressedBytes: Int64(i * 800),
                        deduplicatedBytes: Int64(i * 600)
                    )
                ))
            }
        }
        
        return metrics
    }
    
    private func generateTransferMetrics(valid: Bool) -> [TimeSeriesPoint<TransferMetrics>] {
        let now = Date()
        var metrics: [TimeSeriesPoint<TransferMetrics>] = []
        
        for i in 0..<24 {
            let timestamp = now.addingTimeInterval(Double(-i * 3600))
            let uploadedBytes = valid ? Int64(i * 100) : Int64(-100)
            let downloadedBytes = valid ? Int64(i * 50) : Int64(-50)
            let speed = valid ? Double(i * 10) : -10.0
            let successRate = valid ? 0.95 : 1.5
            
            metrics.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: TransferMetrics(
                    uploadedBytes: uploadedBytes,
                    downloadedBytes: downloadedBytes,
                    averageTransferSpeed: speed,
                    successRate: successRate
                )
            ))
        }
        
        return metrics
    }
    
    private func generateTransferMetricsWithAnomalies() -> [TimeSeriesPoint<TransferMetrics>] {
        let now = Date()
        var metrics: [TimeSeriesPoint<TransferMetrics>] = []
        
        for i in 0..<24 {
            let timestamp = now.addingTimeInterval(Double(-i * 3600))
            let speed = i == 12 ? 2_000_000_000.0 : Double(i * 10) // Anomaly at hour 12
            
            metrics.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: TransferMetrics(
                    uploadedBytes: Int64(i * 100),
                    downloadedBytes: Int64(i * 50),
                    averageTransferSpeed: speed,
                    successRate: 0.95
                )
            ))
        }
        
        return metrics
    }
    
    private func generateCostMetrics(valid: Bool) -> [TimeSeriesPoint<CostMetrics>] {
        let now = Date()
        var metrics: [TimeSeriesPoint<CostMetrics>] = []
        
        for i in 0..<24 {
            let timestamp = now.addingTimeInterval(Double(-i * 3600))
            let storageUnitCost = valid ? 0.02 : -0.02
            let transferUnitCost = valid ? 0.01 : -0.01
            let totalCost = valid ? Double(i) * 0.05 : -0.05
            
            metrics.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: CostMetrics(
                    storageUnitCost: storageUnitCost,
                    transferUnitCost: transferUnitCost,
                    totalCost: totalCost
                )
            ))
        }
        
        return metrics
    }
    
    private func generateCostMetricsWithInconsistencies() -> [TimeSeriesPoint<CostMetrics>] {
        let now = Date()
        var metrics: [TimeSeriesPoint<CostMetrics>] = []
        
        for i in 0..<24 {
            let timestamp = now.addingTimeInterval(Double(-i * 3600))
            let storageUnitCost = 0.02
            let transferUnitCost = 0.01
            let totalCost = i == 12 ? 1.0 : Double(i) * 0.05 // Inconsistency at hour 12
            
            metrics.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: CostMetrics(
                    storageUnitCost: storageUnitCost,
                    transferUnitCost: transferUnitCost,
                    totalCost: totalCost
                )
            ))
        }
        
        return metrics
    }
}
