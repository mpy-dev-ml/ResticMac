import XCTest
@testable import ResticMac

final class CloudAnalyticsImportTests: XCTestCase {
    var importer: CloudAnalyticsImport!
    var mockPersistence: MockCloudAnalyticsPersistence!
    var mockRepository: Repository!
    
    override func setUp() async throws {
        mockPersistence = MockCloudAnalyticsPersistence()
        mockRepository = Repository(
            path: URL(fileURLWithPath: "/test/repo"),
            password: "test",
            provider: .local
        )
        importer = CloudAnalyticsImport(persistence: mockPersistence)
    }
    
    override func tearDown() async throws {
        importer = nil
        mockPersistence = nil
        mockRepository = nil
    }
    
    // MARK: - CSV Import Tests
    
    func testValidCSVImport() async throws {
        // Given
        let csvURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.csv")
        let csvContent = """
        timestamp,total_bytes,compressed_bytes,deduplicated_bytes,uploaded_bytes,downloaded_bytes,transfer_speed,storage_cost,transfer_cost,snapshot_count,average_snapshot_size
        2025-01-01T00:00:00Z,1000,800,600,100,50,1000,0.02,0.01,5,200
        2025-01-02T00:00:00Z,1200,900,700,150,75,1200,0.02,0.01,6,200
        """
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
        
        // When
        try await importer.importAnalytics(from: csvURL, for: mockRepository)
        
        // Then
        XCTAssertEqual(mockPersistence.storageMetricsHistory.count, 2)
        XCTAssertEqual(mockPersistence.transferMetricsHistory.count, 2)
        XCTAssertEqual(mockPersistence.costMetricsHistory.count, 2)
        XCTAssertEqual(mockPersistence.snapshotMetricsHistory.count, 2)
        
        try FileManager.default.removeItem(at: csvURL)
    }
    
    func testInvalidCSVFormat() async throws {
        // Given
        let csvURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.csv")
        let csvContent = """
        invalid,header,format
        1,2,3
        """
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
        
        // When/Then
        await XCTAssertThrowsError(
            try await importer.importAnalytics(from: csvURL, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? CloudAnalyticsError,
                .invalidFileFormat(details: "Missing required columns")
            )
        }
        
        try FileManager.default.removeItem(at: csvURL)
    }
    
    // MARK: - JSON Import Tests
    
    func testValidJSONImport() async throws {
        // Given
        let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.json")
        let jsonContent = """
        {
            "records": [
                {
                    "timestamp": "2025-01-01T00:00:00Z",
                    "storageMetrics": {
                        "totalBytes": 1000,
                        "compressedBytes": 800,
                        "deduplicatedBytes": 600
                    },
                    "transferMetrics": {
                        "uploadedBytes": 100,
                        "downloadedBytes": 50,
                        "averageTransferSpeed": 1000,
                        "successRate": 1.0
                    },
                    "costMetrics": {
                        "storageUnitCost": 0.02,
                        "transferUnitCost": 0.01,
                        "totalCost": 0.03
                    },
                    "snapshotMetrics": {
                        "totalSnapshots": 5,
                        "averageSnapshotSize": 200,
                        "retentionDays": 30
                    }
                }
            ]
        }
        """
        try jsonContent.write(to: jsonURL, atomically: true, encoding: .utf8)
        
        // When
        try await importer.importAnalytics(from: jsonURL, for: mockRepository)
        
        // Then
        XCTAssertEqual(mockPersistence.storageMetricsHistory.count, 1)
        XCTAssertEqual(mockPersistence.transferMetricsHistory.count, 1)
        XCTAssertEqual(mockPersistence.costMetricsHistory.count, 1)
        XCTAssertEqual(mockPersistence.snapshotMetricsHistory.count, 1)
        
        try FileManager.default.removeItem(at: jsonURL)
    }
    
    func testInvalidJSONFormat() async throws {
        // Given
        let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.json")
        let jsonContent = """
        {
            "invalid": "format"
        }
        """
        try jsonContent.write(to: jsonURL, atomically: true, encoding: .utf8)
        
        // When/Then
        await XCTAssertThrowsError(
            try await importer.importAnalytics(from: jsonURL, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? CloudAnalyticsError,
                .invalidFileFormat(details: "Invalid JSON structure")
            )
        }
        
        try FileManager.default.removeItem(at: jsonURL)
    }
    
    // MARK: - Restic Stats Import Tests
    
    func testValidResticStatsImport() async throws {
        // Given
        let statsURL = FileManager.default.temporaryDirectory.appendingPathComponent("stats.json")
        let statsContent = """
        {
            "snapshots": [
                {
                    "id": "abc123",
                    "time": "2025-01-01T00:00:00Z",
                    "stats": {
                        "totalSize": 1000,
                        "dataSize": 600,
                        "fileCount": 10
                    }
                }
            ],
            "totalSize": 1000,
            "totalFileCount": 10
        }
        """
        try statsContent.write(to: statsURL, atomically: true, encoding: .utf8)
        
        // When
        try await importer.importAnalytics(from: statsURL, for: mockRepository)
        
        // Then
        XCTAssertEqual(mockPersistence.storageMetricsHistory.count, 1)
        let metrics = mockPersistence.storageMetricsHistory.first
        XCTAssertEqual(metrics?.totalBytes, 1000)
        XCTAssertEqual(metrics?.deduplicatedBytes, 600)
        
        try FileManager.default.removeItem(at: statsURL)
    }
    
    // MARK: - Edge Cases and Error Handling
    
    func testEmptyFile() async throws {
        // Given
        let emptyURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty.csv")
        try Data().write(to: emptyURL)
        
        // When/Then
        await XCTAssertThrowsError(
            try await importer.importAnalytics(from: emptyURL, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? CloudAnalyticsError,
                .invalidFileFormat(details: "Empty file")
            )
        }
        
        try FileManager.default.removeItem(at: emptyURL)
    }
    
    func testInvalidEncoding() async throws {
        // Given
        let invalidURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.csv")
        let invalidData = Data([0xFF, 0xFE, 0xFD]) // Invalid UTF-8
        try invalidData.write(to: invalidURL)
        
        // When/Then
        await XCTAssertThrowsError(
            try await importer.importAnalytics(from: invalidURL, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? CloudAnalyticsError,
                .invalidEncoding
            )
        }
        
        try FileManager.default.removeItem(at: invalidURL)
    }
    
    func testUnsupportedFileType() async throws {
        // Given
        let unsupportedURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.txt")
        try "Some text".write(to: unsupportedURL, atomically: true, encoding: .utf8)
        
        // When/Then
        await XCTAssertThrowsError(
            try await importer.importAnalytics(from: unsupportedURL, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? CloudAnalyticsError,
                .unsupportedFileType
            )
        }
        
        try FileManager.default.removeItem(at: unsupportedURL)
    }
    
    func testInconsistentData() async throws {
        // Given
        let inconsistentURL = FileManager.default.temporaryDirectory.appendingPathComponent("inconsistent.csv")
        let csvContent = """
        timestamp,total_bytes,compressed_bytes,deduplicated_bytes
        2025-01-01T00:00:00Z,1000,1200,600
        """
        try csvContent.write(to: inconsistentURL, atomically: true, encoding: .utf8)
        
        // When/Then
        await XCTAssertThrowsError(
            try await importer.importAnalytics(from: inconsistentURL, for: mockRepository)
        ) { error in
            XCTAssertEqual(
                error as? CloudAnalyticsError,
                .inconsistentData(details: "Compressed bytes cannot be greater than total bytes")
            )
        }
        
        try FileManager.default.removeItem(at: inconsistentURL)
    }
}
