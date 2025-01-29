import XCTest
@testable import ResticMac

final class CloudAnalyticsExportUtilsTests: XCTestCase {
    var exportUtils: CloudAnalyticsExportUtils!
    var persistence: MockCloudAnalyticsPersistence!
    var monitor: CloudAnalyticsMonitor!
    var testDataDirectory: URL!
    var repository: Repository!
    
    override func setUp() async throws {
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacExportTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        persistence = MockCloudAnalyticsPersistence(storageURL: testDataDirectory)
        monitor = CloudAnalyticsMonitor.shared
        exportUtils = CloudAnalyticsExportUtils(persistence: persistence, monitor: monitor)
        
        repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
        
        // Generate test data
        try await generateTestData()
    }
    
    override func tearDown() async throws {
        exportUtils = nil
        persistence = nil
        monitor = nil
        repository = nil
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Export Tests
    
    func testJSONExport() async throws {
        let exportURL = try await exportUtils.exportAnalytics(
            for: repository,
            format: .json
        )
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        
        // Verify content
        let data = try Data(contentsOf: exportURL)
        let metrics = try JSONDecoder().decode(AnalyticsMetrics.self, from: data)
        
        XCTAssertFalse(metrics.storageHistory.isEmpty)
        XCTAssertFalse(metrics.transferHistory.isEmpty)
        XCTAssertFalse(metrics.costHistory.isEmpty)
    }
    
    func testCSVExport() async throws {
        let exportURL = try await exportUtils.exportAnalytics(
            for: repository,
            format: .csv
        )
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        
        // Verify content
        let content = try String(contentsOf: exportURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        XCTAssertTrue(lines[0].contains("timestamp"))
        XCTAssertTrue(lines[0].contains("metric_type"))
        XCTAssertTrue(lines[0].contains("value"))
        XCTAssertTrue(lines[0].contains("unit"))
    }
    
    func testExcelExport() async throws {
        let exportURL = try await exportUtils.exportAnalytics(
            for: repository,
            format: .excel
        )
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        
        // Verify file size
        let attributes = try FileManager.default.attributesOfItem(atPath: exportURL.path)
        XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, 0)
    }
    
    func testSQLExport() async throws {
        let exportURL = try await exportUtils.exportAnalytics(
            for: repository,
            format: .sql
        )
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
        
        // Verify content
        let content = try String(contentsOf: exportURL, encoding: .utf8)
        
        XCTAssertTrue(content.contains("CREATE TABLE"))
        XCTAssertTrue(content.contains("INSERT INTO"))
    }
    
    // MARK: - Time Range Tests
    
    func testTimeRangeFiltering() async throws {
        let now = Date()
        let timeRange = DateInterval(
            start: now.addingTimeInterval(-3600), // 1 hour ago
            end: now
        )
        
        let exportURL = try await exportUtils.exportAnalytics(
            for: repository,
            format: .json,
            timeRange: timeRange
        )
        
        // Verify content
        let data = try Data(contentsOf: exportURL)
        let metrics = try JSONDecoder().decode(AnalyticsMetrics.self, from: data)
        
        // Check all timestamps are within range
        for point in metrics.storageHistory {
            XCTAssertTrue(timeRange.contains(point.timestamp))
        }
    }
    
    // MARK: - Batch Export Tests
    
    func testBatchExport() async throws {
        let exportURLs = try await exportUtils.exportAllRepositories(format: .json)
        
        XCTAssertFalse(exportURLs.isEmpty)
        
        for url in exportURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testExportWithInvalidTimeRange() async throws {
        let invalidRange = DateInterval(
            start: Date(),
            end: Date().addingTimeInterval(-3600) // End before start
        )
        
        do {
            _ = try await exportUtils.exportAnalytics(
                for: repository,
                format: .json,
                timeRange: invalidRange
            )
            XCTFail("Expected export to fail")
        } catch let error as ExportError {
            if case .invalidTimeRange = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testExportWithPersistenceFailure() async throws {
        persistence.shouldFail = true
        
        do {
            _ = try await exportUtils.exportAnalytics(
                for: repository,
                format: .json
            )
            XCTFail("Expected export to fail")
        } catch let error as ExportError {
            if case .exportFailed = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateTestData() async throws {
        let now = Date()
        var storageHistory: [TimeSeriesPoint<StorageMetrics>] = []
        var transferHistory: [TimeSeriesPoint<TransferMetrics>] = []
        var costHistory: [TimeSeriesPoint<CostMetrics>] = []
        
        for i in 0..<24 {
            let timestamp = now.addingTimeInterval(Double(-i * 3600))
            
            // Storage metrics
            storageHistory.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: StorageMetrics(
                    totalBytes: Int64(i * 1000),
                    compressedBytes: Int64(i * 800),
                    deduplicatedBytes: Int64(i * 600)
                )
            ))
            
            // Transfer metrics
            transferHistory.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: TransferMetrics(
                    uploadedBytes: Int64(i * 100),
                    downloadedBytes: Int64(i * 50),
                    averageTransferSpeed: Double(i * 10),
                    successRate: 1.0
                )
            ))
            
            // Cost metrics
            costHistory.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: CostMetrics(
                    storageUnitCost: 0.02,
                    transferUnitCost: 0.01,
                    totalCost: Double(i) * 0.05
                )
            ))
        }
        
        try await persistence.saveStorageMetricsHistory(storageHistory, for: repository)
        try await persistence.saveTransferMetricsHistory(transferHistory, for: repository)
        try await persistence.saveCostMetricsHistory(costHistory, for: repository)
    }
}

// MARK: - Test Extensions

class MockCloudAnalyticsPersistence: CloudAnalyticsPersistence {
    var shouldFail = false
    
    override func getStorageMetricsHistory(
        for repository: Repository
    ) async throws -> [TimeSeriesPoint<StorageMetrics>] {
        if shouldFail {
            throw NSError(domain: "TestError", code: -1)
        }
        return try await super.getStorageMetricsHistory(for: repository)
    }
    
    override func getAllRepositories() async throws -> [Repository] {
        if shouldFail {
            throw NSError(domain: "TestError", code: -1)
        }
        return [repository]
    }
}
