import XCTest
@testable import ResticMac

final class CloudAnalyticsPerformanceTests: XCTestCase {
    var analytics: CloudAnalytics!
    var mockPersistence: MockCloudAnalyticsPersistence!
    var mockRepository: Repository!
    
    override func setUp() async throws {
        mockPersistence = MockCloudAnalyticsPersistence()
        mockRepository = Repository(
            path: URL(fileURLWithPath: "/test/repo"),
            password: "test",
            provider: .local
        )
        analytics = CloudAnalytics(persistence: mockPersistence)
    }
    
    override func tearDown() async throws {
        analytics = nil
        mockPersistence = nil
        mockRepository = nil
    }
    
    // MARK: - Data Processing Performance
    
    func testLargeDatasetProcessingPerformance() async throws {
        // Generate large dataset
        let dataPoints = 100_000
        var storageHistory: [StorageMetrics] = []
        var transferHistory: [TransferMetrics] = []
        
        let startDate = Date()
        for i in 0..<dataPoints {
            let timestamp = startDate.addingTimeInterval(Double(i * 3600)) // Hourly data
            
            storageHistory.append(StorageMetrics(
                totalBytes: Int64(i * 1000),
                compressedBytes: Int64(i * 800),
                deduplicatedBytes: Int64(i * 600)
            ))
            
            transferHistory.append(TransferMetrics(
                uploadedBytes: Int64(i * 100),
                downloadedBytes: Int64(i * 50),
                averageTransferSpeed: Double(i * 10),
                successRate: 1.0
            ))
        }
        
        mockPersistence.storageMetricsHistory = storageHistory
        mockPersistence.transferMetricsHistory = transferHistory
        
        // Measure trend analysis performance
        measure {
            Task {
                let trend = try await analytics.analyzeStorageTrend(for: mockRepository)
                XCTAssertNotNil(trend)
            }
        }
    }
    
    func testConcurrentMetricsProcessing() async throws {
        measure {
            Task {
                async let storageMetrics = analytics.getStorageMetrics(for: mockRepository)
                async let transferMetrics = analytics.getTransferMetrics(for: mockRepository)
                async let costMetrics = analytics.getCostMetrics(for: mockRepository)
                async let snapshotMetrics = analytics.getSnapshotMetrics(for: mockRepository)
                
                let _ = try await [storageMetrics, transferMetrics, costMetrics, snapshotMetrics]
            }
        }
    }
    
    // MARK: - Import Performance
    
    func testLargeCSVImportPerformance() async throws {
        // Generate large CSV file
        let csvURL = FileManager.default.temporaryDirectory.appendingPathComponent("large_test.csv")
        var csvContent = "timestamp,total_bytes,compressed_bytes,deduplicated_bytes,uploaded_bytes,downloaded_bytes,transfer_speed,storage_cost,transfer_cost,snapshot_count,average_snapshot_size\n"
        
        let startDate = Date()
        for i in 0..<100_000 {
            let timestamp = startDate.addingTimeInterval(Double(i * 3600))
            csvContent += "\(timestamp.ISO8601Format()),"
            csvContent += "\(i * 1000)," // total_bytes
            csvContent += "\(i * 800)," // compressed_bytes
            csvContent += "\(i * 600)," // deduplicated_bytes
            csvContent += "\(i * 100)," // uploaded_bytes
            csvContent += "\(i * 50)," // downloaded_bytes
            csvContent += "\(i * 10)," // transfer_speed
            csvContent += "0.02," // storage_cost
            csvContent += "0.01," // transfer_cost
            csvContent += "5," // snapshot_count
            csvContent += "200\n" // average_snapshot_size
        }
        
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
        
        // Measure import performance
        measure {
            Task {
                let importer = CloudAnalyticsImport(persistence: mockPersistence)
                try await importer.importAnalytics(from: csvURL, for: mockRepository)
            }
        }
        
        try FileManager.default.removeItem(at: csvURL)
    }
    
    // MARK: - Memory Usage Tests
    
    func testMemoryUsageWithLargeDataset() async throws {
        // Generate large dataset
        let dataPoints = 1_000_000
        var storageHistory: [StorageMetrics] = []
        
        let startDate = Date()
        for i in 0..<dataPoints {
            storageHistory.append(StorageMetrics(
                totalBytes: Int64(i * 1000),
                compressedBytes: Int64(i * 800),
                deduplicatedBytes: Int64(i * 600)
            ))
        }
        
        mockPersistence.storageMetricsHistory = storageHistory
        
        // Measure memory usage during processing
        measure {
            Task {
                let metrics = try await analytics.getStorageMetrics(for: mockRepository)
                XCTAssertNotNil(metrics)
            }
        }
    }
    
    // MARK: - Cache Performance
    
    func testCachePerformance() async throws {
        // Setup test data
        let dataPoints = 10_000
        var storageHistory: [StorageMetrics] = []
        
        for i in 0..<dataPoints {
            storageHistory.append(StorageMetrics(
                totalBytes: Int64(i * 1000),
                compressedBytes: Int64(i * 800),
                deduplicatedBytes: Int64(i * 600)
            ))
        }
        
        mockPersistence.storageMetricsHistory = storageHistory
        
        // First access (no cache)
        measure {
            Task {
                let _ = try await analytics.getStorageMetrics(for: mockRepository)
            }
        }
        
        // Second access (with cache)
        measure {
            Task {
                let _ = try await analytics.getStorageMetrics(for: mockRepository)
            }
        }
    }
    
    // MARK: - Data Validation Performance
    
    func testValidationPerformance() async throws {
        let validator = CloudAnalyticsValidation()
        let dataPoints = 100_000
        var timeSeriesData: [TimeSeriesPoint<StorageMetrics>] = []
        
        let startDate = Date()
        for i in 0..<dataPoints {
            let timestamp = startDate.addingTimeInterval(Double(i * 3600))
            let metrics = StorageMetrics(
                totalBytes: Int64(i * 1000),
                compressedBytes: Int64(i * 800),
                deduplicatedBytes: Int64(i * 600)
            )
            timeSeriesData.append(TimeSeriesPoint(timestamp: timestamp, value: metrics))
        }
        
        // Measure validation performance
        measure {
            Task {
                try await validator.validateTimeSeriesData(timeSeriesData)
            }
        }
    }
    
    // MARK: - Data Repair Performance
    
    func testDataRepairPerformance() async throws {
        let validator = CloudAnalyticsValidation()
        let dataPoints = 10_000
        var timeSeriesData: [TimeSeriesPoint<StorageMetrics>] = []
        
        let startDate = Date()
        for i in 0..<dataPoints {
            // Add gaps every 100 points
            let interval = (i % 100 == 0) ? Double(i * 7200) : Double(i * 3600)
            let timestamp = startDate.addingTimeInterval(interval)
            let metrics = StorageMetrics(
                totalBytes: Int64(i * 1000),
                compressedBytes: Int64(i * 800),
                deduplicatedBytes: Int64(i * 600)
            )
            timeSeriesData.append(TimeSeriesPoint(timestamp: timestamp, value: metrics))
        }
        
        // Measure repair performance
        measure {
            Task {
                let _ = try await validator.repairTimeSeriesGaps(timeSeriesData)
            }
        }
    }
    
    // MARK: - Trend Analysis Performance
    
    func testTrendAnalysisPerformance() async throws {
        let dataPoints = 50_000
        var storageHistory: [StorageMetrics] = []
        
        let startDate = Date()
        for i in 0..<dataPoints {
            // Add some randomness to make trend analysis more realistic
            let randomFactor = Double.random(in: 0.9...1.1)
            storageHistory.append(StorageMetrics(
                totalBytes: Int64(Double(i * 1000) * randomFactor),
                compressedBytes: Int64(Double(i * 800) * randomFactor),
                deduplicatedBytes: Int64(Double(i * 600) * randomFactor)
            ))
        }
        
        mockPersistence.storageMetricsHistory = storageHistory
        
        // Measure trend analysis performance
        measure {
            Task {
                let trend = try await analytics.analyzeStorageTrend(for: mockRepository)
                XCTAssertNotNil(trend)
            }
        }
    }
}

// MARK: - Test Helpers

extension Date {
    func ISO8601Format() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: self)
    }
}
