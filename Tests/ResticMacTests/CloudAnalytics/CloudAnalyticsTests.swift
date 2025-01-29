import XCTest
@testable import ResticMac

final class CloudAnalyticsTests: XCTestCase {
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
    
    // MARK: - Storage Metrics Tests
    
    func testStorageMetricsCalculation() async throws {
        // Given
        let testData = StorageMetrics(
            totalBytes: 1000,
            compressedBytes: 800,
            deduplicatedBytes: 600
        )
        mockPersistence.storageMetrics = testData
        
        // When
        let metrics = try await analytics.getStorageMetrics(for: mockRepository)
        
        // Then
        XCTAssertEqual(metrics.totalBytes, 1000)
        XCTAssertEqual(metrics.compressedBytes, 800)
        XCTAssertEqual(metrics.deduplicatedBytes, 600)
        XCTAssertEqual(metrics.compressionRatio, 0.8)
        XCTAssertEqual(metrics.deduplicationRatio, 0.75)
    }
    
    func testStorageMetricsValidation() async throws {
        // Given
        let invalidData = StorageMetrics(
            totalBytes: -1000,
            compressedBytes: 800,
            deduplicatedBytes: 600
        )
        mockPersistence.storageMetrics = invalidData
        
        // When/Then
        await XCTAssertThrowsError(
            try await analytics.getStorageMetrics(for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? CloudAnalyticsError,
                .invalidMetrics(reason: "Total bytes cannot be negative")
            )
        }
    }
    
    // MARK: - Transfer Metrics Tests
    
    func testTransferMetricsCalculation() async throws {
        // Given
        let testData = TransferMetrics(
            uploadedBytes: 1000,
            downloadedBytes: 500,
            averageTransferSpeed: 100,
            successRate: 0.95
        )
        mockPersistence.transferMetrics = testData
        
        // When
        let metrics = try await analytics.getTransferMetrics(for: mockRepository)
        
        // Then
        XCTAssertEqual(metrics.uploadedBytes, 1000)
        XCTAssertEqual(metrics.downloadedBytes, 500)
        XCTAssertEqual(metrics.averageTransferSpeed, 100)
        XCTAssertEqual(metrics.successRate, 0.95)
        XCTAssertEqual(metrics.totalTransferredBytes, 1500)
    }
    
    func testTransferMetricsThrottling() async throws {
        // Given
        let highSpeedData = TransferMetrics(
            uploadedBytes: 1000,
            downloadedBytes: 500,
            averageTransferSpeed: 1_000_000,
            successRate: 1.0
        )
        mockPersistence.transferMetrics = highSpeedData
        
        // When
        analytics.setTransferLimit(500_000) // 500 KB/s
        let metrics = try await analytics.getTransferMetrics(for: mockRepository)
        
        // Then
        XCTAssertEqual(metrics.averageTransferSpeed, 500_000)
        XCTAssertTrue(metrics.isThrottled)
    }
    
    // MARK: - Cost Metrics Tests
    
    func testCostMetricsCalculation() async throws {
        // Given
        let testData = CostMetrics(
            storageUnitCost: 0.02,
            transferUnitCost: 0.01,
            totalCost: 0
        )
        mockPersistence.costMetrics = testData
        mockPersistence.storageMetrics = StorageMetrics(
            totalBytes: 1_000_000,
            compressedBytes: 800_000,
            deduplicatedBytes: 600_000
        )
        mockPersistence.transferMetrics = TransferMetrics(
            uploadedBytes: 100_000,
            downloadedBytes: 50_000,
            averageTransferSpeed: 1000,
            successRate: 1.0
        )
        
        // When
        let metrics = try await analytics.getCostMetrics(for: mockRepository)
        
        // Then
        XCTAssertEqual(metrics.storageUnitCost, 0.02)
        XCTAssertEqual(metrics.transferUnitCost, 0.01)
        XCTAssertEqual(metrics.storageCost, 0.012) // 600KB * $0.02/GB
        XCTAssertEqual(metrics.transferCost, 0.0015) // 150KB * $0.01/GB
        XCTAssertEqual(metrics.totalCost, 0.0135)
    }
    
    // MARK: - Snapshot Metrics Tests
    
    func testSnapshotMetricsCalculation() async throws {
        // Given
        let testData = SnapshotMetrics(
            totalSnapshots: 10,
            averageSnapshotSize: 1000,
            retentionDays: 30
        )
        mockPersistence.snapshotMetrics = testData
        
        // When
        let metrics = try await analytics.getSnapshotMetrics(for: mockRepository)
        
        // Then
        XCTAssertEqual(metrics.totalSnapshots, 10)
        XCTAssertEqual(metrics.averageSnapshotSize, 1000)
        XCTAssertEqual(metrics.retentionDays, 30)
        XCTAssertEqual(metrics.snapshotsPerDay, 0.33, accuracy: 0.01)
    }
    
    // MARK: - Trend Analysis Tests
    
    func testTrendAnalysis() async throws {
        // Given
        let historicalData = [
            StorageMetrics(totalBytes: 1000, compressedBytes: 800, deduplicatedBytes: 600),
            StorageMetrics(totalBytes: 1200, compressedBytes: 900, deduplicatedBytes: 700),
            StorageMetrics(totalBytes: 1400, compressedBytes: 1000, deduplicatedBytes: 800)
        ]
        mockPersistence.storageMetricsHistory = historicalData
        
        // When
        let trend = try await analytics.analyzeStorageTrend(for: mockRepository)
        
        // Then
        XCTAssertEqual(trend.direction, .increasing)
        XCTAssertEqual(trend.rate, 200) // Bytes per period
        XCTAssertEqual(trend.confidence, 1.0) // Perfect linear trend
    }
    
    func testOutlierDetection() async throws {
        // Given
        let dataWithOutlier = [
            StorageMetrics(totalBytes: 1000, compressedBytes: 800, deduplicatedBytes: 600),
            StorageMetrics(totalBytes: 1200, compressedBytes: 900, deduplicatedBytes: 700),
            StorageMetrics(totalBytes: 10000, compressedBytes: 8000, deduplicatedBytes: 6000), // Outlier
            StorageMetrics(totalBytes: 1400, compressedBytes: 1000, deduplicatedBytes: 800)
        ]
        mockPersistence.storageMetricsHistory = dataWithOutlier
        
        // When
        let outliers = try await analytics.detectStorageOutliers(for: mockRepository)
        
        // Then
        XCTAssertEqual(outliers.count, 1)
        XCTAssertEqual(outliers.first?.totalBytes, 10000)
    }
    
    // MARK: - Import/Export Tests
    
    func testDataImport() async throws {
        // Given
        let importData = """
        timestamp,total_bytes,compressed_bytes,deduplicated_bytes
        2025-01-01T00:00:00Z,1000,800,600
        2025-01-02T00:00:00Z,1200,900,700
        """.data(using: .utf8)!
        
        // When
        try await analytics.importData(importData, format: .csv, for: mockRepository)
        
        // Then
        XCTAssertEqual(mockPersistence.storageMetricsHistory.count, 2)
        XCTAssertEqual(mockPersistence.storageMetricsHistory.first?.totalBytes, 1000)
    }
    
    func testInvalidDataImport() async throws {
        // Given
        let invalidData = """
        invalid,csv,format
        1,2,3
        """.data(using: .utf8)!
        
        // When/Then
        await XCTAssertThrowsError(
            try await analytics.importData(invalidData, format: .csv, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? CloudAnalyticsError,
                .invalidFileFormat(details: "Missing required columns")
            )
        }
    }
}

// MARK: - Mock Implementation

class MockCloudAnalyticsPersistence: CloudAnalyticsPersistence {
    var storageMetrics: StorageMetrics?
    var transferMetrics: TransferMetrics?
    var costMetrics: CostMetrics?
    var snapshotMetrics: SnapshotMetrics?
    
    var storageMetricsHistory: [StorageMetrics] = []
    var transferMetricsHistory: [TransferMetrics] = []
    var costMetricsHistory: [CostMetrics] = []
    var snapshotMetricsHistory: [SnapshotMetrics] = []
    
    override func getStorageMetrics(for repository: Repository) async throws -> StorageMetrics {
        guard let metrics = storageMetrics else {
            throw CloudAnalyticsError.dataCollectionFailed(reason: "No mock data")
        }
        return metrics
    }
    
    override func getTransferMetrics(for repository: Repository) async throws -> TransferMetrics {
        guard let metrics = transferMetrics else {
            throw CloudAnalyticsError.dataCollectionFailed(reason: "No mock data")
        }
        return metrics
    }
    
    override func getCostMetrics(for repository: Repository) async throws -> CostMetrics {
        guard let metrics = costMetrics else {
            throw CloudAnalyticsError.dataCollectionFailed(reason: "No mock data")
        }
        return metrics
    }
    
    override func getSnapshotMetrics(for repository: Repository) async throws -> SnapshotMetrics {
        guard let metrics = snapshotMetrics else {
            throw CloudAnalyticsError.dataCollectionFailed(reason: "No mock data")
        }
        return metrics
    }
    
    override func getStorageMetricsHistory(
        for repository: Repository,
        range: DateInterval? = nil
    ) async throws -> [StorageMetrics] {
        return storageMetricsHistory
    }
    
    override func getTransferMetricsHistory(
        for repository: Repository,
        range: DateInterval? = nil
    ) async throws -> [TransferMetrics] {
        return transferMetricsHistory
    }
    
    override func getCostMetricsHistory(
        for repository: Repository,
        range: DateInterval? = nil
    ) async throws -> [CostMetrics] {
        return costMetricsHistory
    }
    
    override func getSnapshotMetricsHistory(
        for repository: Repository,
        range: DateInterval? = nil
    ) async throws -> [SnapshotMetrics] {
        return snapshotMetricsHistory
    }
}
