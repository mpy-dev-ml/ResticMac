import XCTest
@testable import ResticMac

final class CloudAnalyticsCompressionTests: XCTestCase {
    var compression: CloudAnalyticsCompression!
    var persistence: MockCloudAnalyticsPersistence!
    var monitor: CloudAnalyticsMonitor!
    var testDataDirectory: URL!
    var repository: Repository!
    
    override func setUp() async throws {
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacCompressionTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        persistence = MockCloudAnalyticsPersistence(storageURL: testDataDirectory)
        monitor = CloudAnalyticsMonitor.shared
        compression = CloudAnalyticsCompression(persistence: persistence, monitor: monitor)
        
        repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
        
        // Generate test data
        try await generateTestData()
    }
    
    override func tearDown() async throws {
        compression = nil
        persistence = nil
        monitor = nil
        repository = nil
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Compression Tests
    
    func testLZFSECompression() async throws {
        let report = try await compression.compressMetrics(
            for: repository,
            algorithm: .lzfse
        )
        
        // Verify compression results
        XCTAssertTrue(report.totalCompressionRatio < 1.0)
        XCTAssertGreaterThan(report.storageCompression.originalSize, report.storageCompression.compressedSize)
        XCTAssertGreaterThan(report.transferCompression.originalSize, report.transferCompression.compressedSize)
        XCTAssertGreaterThan(report.costCompression.originalSize, report.costCompression.compressedSize)
    }
    
    func testLZ4Compression() async throws {
        let report = try await compression.compressMetrics(
            for: repository,
            algorithm: .lz4
        )
        
        // Verify compression results
        XCTAssertTrue(report.totalCompressionRatio < 1.0)
        XCTAssertGreaterThan(report.storageCompression.originalSize, report.storageCompression.compressedSize)
    }
    
    func testLZMACompression() async throws {
        let report = try await compression.compressMetrics(
            for: repository,
            algorithm: .lzma
        )
        
        // Verify compression results
        XCTAssertTrue(report.totalCompressionRatio < 1.0)
        XCTAssertGreaterThan(report.storageCompression.originalSize, report.storageCompression.compressedSize)
    }
    
    func testZlibCompression() async throws {
        let report = try await compression.compressMetrics(
            for: repository,
            algorithm: .zlib
        )
        
        // Verify compression results
        XCTAssertTrue(report.totalCompressionRatio < 1.0)
        XCTAssertGreaterThan(report.storageCompression.originalSize, report.storageCompression.compressedSize)
    }
    
    // MARK: - Time Range Tests
    
    func testTimeRangeCompression() async throws {
        let now = Date()
        let timeRange = DateInterval(
            start: now.addingTimeInterval(-3600), // 1 hour ago
            end: now
        )
        
        let report = try await compression.compressMetrics(
            for: repository,
            timeRange: timeRange,
            algorithm: .lzfse
        )
        
        // Verify time range filtering
        XCTAssertNotNil(report.timeRange)
        XCTAssertEqual(report.timeRange?.start, timeRange.start)
        XCTAssertEqual(report.timeRange?.end, timeRange.end)
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidData() async throws {
        persistence.shouldFail = true
        
        do {
            _ = try await compression.compressMetrics(
                for: repository,
                algorithm: .lzfse
            )
            XCTFail("Expected compression to fail")
        } catch let error as CompressionError {
            if case .compressionFailed = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testEmptyData() async throws {
        // Clear test data
        try await persistence.clearMetrics(for: repository)
        
        do {
            _ = try await compression.compressMetrics(
                for: repository,
                algorithm: .lzfse
            )
            XCTFail("Expected compression to fail")
        } catch let error as CompressionError {
            if case .invalidData = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    func testCompressionPerformance() async throws {
        // Generate large dataset
        let largeDataset = generateLargeDataset()
        try await persistence.saveStorageMetricsHistory(largeDataset, for: repository)
        
        measure {
            Task {
                do {
                    _ = try await compression.compressMetrics(
                        for: repository,
                        algorithm: .lzfse
                    )
                } catch {
                    XCTFail("Compression failed: \(error)")
                }
            }
        }
    }
    
    func testAlgorithmComparison() async throws {
        let algorithms: [CompressionAlgorithm] = [.lzfse, .lz4, .lzma, .zlib]
        var results: [CompressionAlgorithm: Double] = [:]
        
        for algorithm in algorithms {
            let report = try await compression.compressMetrics(
                for: repository,
                algorithm: algorithm
            )
            results[algorithm] = report.totalCompressionRatio
        }
        
        // Compare compression ratios
        for (algorithm, ratio) in results {
            XCTAssertTrue(ratio < 1.0, "Algorithm \(algorithm) failed to compress data")
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateTestData() async throws {
        let now = Date()
        var storagePoints: [TimeSeriesPoint<StorageMetrics>] = []
        var transferPoints: [TimeSeriesPoint<TransferMetrics>] = []
        var costPoints: [TimeSeriesPoint<CostMetrics>] = []
        
        for i in 0..<24 {
            let timestamp = now.addingTimeInterval(Double(-i * 3600))
            
            // Storage metrics
            storagePoints.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: StorageMetrics(
                    totalBytes: Int64(i * 1000),
                    compressedBytes: Int64(i * 800),
                    deduplicatedBytes: Int64(i * 600)
                )
            ))
            
            // Transfer metrics
            transferPoints.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: TransferMetrics(
                    uploadedBytes: Int64(i * 100),
                    downloadedBytes: Int64(i * 50),
                    averageTransferSpeed: Double(i * 10),
                    successRate: 0.95 + Double(i) * 0.001
                )
            ))
            
            // Cost metrics
            costPoints.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: CostMetrics(
                    storageUnitCost: 0.02,
                    transferUnitCost: 0.01,
                    totalCost: Double(i) * 0.05
                )
            ))
        }
        
        try await persistence.saveStorageMetricsHistory(storagePoints, for: repository)
        try await persistence.saveTransferMetricsHistory(transferPoints, for: repository)
        try await persistence.saveCostMetricsHistory(costPoints, for: repository)
    }
    
    private func generateLargeDataset() -> [TimeSeriesPoint<StorageMetrics>] {
        let now = Date()
        var points: [TimeSeriesPoint<StorageMetrics>] = []
        
        // Generate 1000 data points
        for i in 0..<1000 {
            let timestamp = now.addingTimeInterval(Double(-i * 3600))
            points.append(TimeSeriesPoint(
                timestamp: timestamp,
                value: StorageMetrics(
                    totalBytes: Int64(i * 1000),
                    compressedBytes: Int64(i * 800),
                    deduplicatedBytes: Int64(i * 600)
                )
            ))
        }
        
        return points
    }
}

// MARK: - Test Extensions

extension MockCloudAnalyticsPersistence {
    func clearMetrics(for repository: Repository) async throws {
        // Clear all metrics for testing
        try await saveStorageMetricsHistory([], for: repository)
        try await saveTransferMetricsHistory([], for: repository)
        try await saveCostMetricsHistory([], for: repository)
    }
}
