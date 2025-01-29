import XCTest
import MetricKit
@testable import ResticMac

final class CloudAnalyticsOptimizerTests: XCTestCase {
    var optimizer: CloudAnalyticsOptimizer!
    var persistence: MockCloudAnalyticsPersistence!
    var monitor: CloudAnalyticsMonitor!
    var testDataDirectory: URL!
    var repository: Repository!
    
    override func setUp() async throws {
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacOptimizerTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        persistence = MockCloudAnalyticsPersistence(storageURL: testDataDirectory)
        monitor = CloudAnalyticsMonitor.shared
        optimizer = CloudAnalyticsOptimizer(persistence: persistence, monitor: monitor)
        
        repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
    }
    
    override func tearDown() async throws {
        optimizer = nil
        persistence = nil
        monitor = nil
        repository = nil
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Performance Optimization Tests
    
    func testAutomaticOptimization() async throws {
        let report = try await optimizer.optimizeAnalytics(
            for: repository,
            strategy: .automatic
        )
        
        // Verify optimizations were applied
        XCTAssertFalse(report.optimizations.isEmpty)
        XCTAssertTrue(report.improvements["CPU"] ?? 1.0 <= 1.0)
        XCTAssertTrue(report.improvements["Memory"] ?? 1.0 <= 1.0)
    }
    
    func testAggressiveOptimization() async throws {
        let report = try await optimizer.optimizeAnalytics(
            for: repository,
            strategy: .aggressive
        )
        
        // Verify aggressive optimizations
        XCTAssertTrue(report.optimizations.count > 2)
        XCTAssertTrue(report.improvements["CPU"] ?? 1.0 < 0.8)
        XCTAssertTrue(report.improvements["Memory"] ?? 1.0 < 0.8)
    }
    
    func testConservativeOptimization() async throws {
        let report = try await optimizer.optimizeAnalytics(
            for: repository,
            strategy: .conservative
        )
        
        // Verify conservative optimizations
        XCTAssertTrue(report.optimizations.count <= 2)
        XCTAssertTrue(report.improvements["CPU"] ?? 1.0 <= 1.0)
        XCTAssertTrue(report.improvements["Memory"] ?? 1.0 <= 1.0)
    }
    
    func testCustomOptimization() async throws {
        let config = OptimizationStrategy.Configuration(
            cacheSize: 100 * 1024 * 1024,
            queryOptimization: true,
            memoryOptimization: false
        )
        
        let report = try await optimizer.optimizeAnalytics(
            for: repository,
            strategy: .custom(config)
        )
        
        // Verify custom optimizations
        XCTAssertTrue(report.optimizations.contains { $0.contains("cache") })
        XCTAssertTrue(report.optimizations.contains { $0.contains("query") })
        XCTAssertFalse(report.optimizations.contains { $0.contains("memory") })
    }
    
    // MARK: - Cache Optimization Tests
    
    func testCacheOptimization() async throws {
        let result = try await optimizer.optimizeCache(for: repository)
        
        // Verify cache optimization
        XCTAssertGreaterThan(result.hitRate, 0.0)
        XCTAssertLessThan(result.missRate, 1.0)
        XCTAssertLessThan(result.evictionRate, 0.3)
    }
    
    func testCacheConfigurationOptimization() async throws {
        // Generate cache pressure
        for i in 0..<1000 {
            let key = NSString(string: "key\(i)")
            let value = String(repeating: "a", count: 1024) // 1KB
            let item = CacheItem(value: value, size: 1024)
            optimizer.cache.setObject(item, forKey: key)
        }
        
        let result = try await optimizer.optimizeCache(for: repository)
        
        // Verify configuration adjustments
        XCTAssertGreaterThan(result.configuration.countLimit, 1000)
        XCTAssertGreaterThan(result.configuration.totalCostLimit, 50 * 1024 * 1024)
    }
    
    // MARK: - Query Optimization Tests
    
    func testQueryOptimization() async throws {
        let result = try await optimizer.optimizeQueries(for: repository)
        
        // Verify query patterns
        XCTAssertFalse(result.patterns.isEmpty)
        XCTAssertFalse(result.plans.isEmpty)
    }
    
    func testQueryPatternDetection() async throws {
        // Generate query history
        try await generateQueryHistory()
        
        let result = try await optimizer.optimizeQueries(for: repository)
        
        // Verify pattern detection
        XCTAssertTrue(result.patterns.contains { $0.type == .storage })
        XCTAssertTrue(result.patterns.contains { $0.type == .transfer })
    }
    
    // MARK: - Memory Optimization Tests
    
    func testMemoryOptimization() async throws {
        let result = try await optimizer.optimizeMemoryUsage(for: repository)
        
        // Verify memory improvements
        XCTAssertLessThanOrEqual(
            result.improved.residentSize,
            result.baseline.residentSize
        )
    }
    
    func testMemoryPressureHandling() async throws {
        // Generate memory pressure
        var data: [String] = []
        for _ in 0..<1000 {
            data.append(String(repeating: "a", count: 1024 * 1024)) // 1MB each
        }
        
        let result = try await optimizer.optimizeMemoryUsage(for: repository)
        
        // Verify memory pressure handling
        XCTAssertLessThanOrEqual(
            result.improved.residentSize,
            result.baseline.residentSize
        )
        
        // Clear reference to force release
        data = []
    }
    
    // MARK: - MetricKit Tests
    
    func testMetricKitIntegration() async throws {
        // Create mock MetricKit payload
        let payload = MockMetricPayload()
        
        // Process payload
        optimizer.didReceive([payload])
        
        // Verify metrics processing
        // Note: MetricKit processing is mostly observational
        // We mainly verify it doesn't crash
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidConfiguration() async throws {
        let config = OptimizationStrategy.Configuration(
            cacheSize: -1,
            queryOptimization: true,
            memoryOptimization: true
        )
        
        do {
            _ = try await optimizer.optimizeAnalytics(
                for: repository,
                strategy: .custom(config)
            )
            XCTFail("Expected optimization to fail")
        } catch let error as OptimizationError {
            if case .invalidConfiguration = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testResourceConstraints() async throws {
        // Simulate resource constraint
        persistence.shouldFail = true
        
        do {
            _ = try await optimizer.optimizeAnalytics(
                for: repository,
                strategy: .aggressive
            )
            XCTFail("Expected optimization to fail")
        } catch let error as OptimizationError {
            if case .resourceConstraint = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateQueryHistory() async throws {
        // Generate storage queries
        for i in 0..<100 {
            let query = QueryRecord(
                type: .storage,
                timestamp: Date().addingTimeInterval(Double(-i * 60)),
                duration: 0.1,
                result: .success
            )
            try await persistence.saveQueryRecord(query, for: repository)
        }
        
        // Generate transfer queries
        for i in 0..<100 {
            let query = QueryRecord(
                type: .transfer,
                timestamp: Date().addingTimeInterval(Double(-i * 60)),
                duration: 0.2,
                result: .success
            )
            try await persistence.saveQueryRecord(query, for: repository)
        }
    }
}

// MARK: - Test Doubles

class MockMetricPayload: MXMetricPayload {
    override var cpuMetrics: MXCPUMetric? {
        // Return mock CPU metrics
        nil
    }
    
    override var memoryMetrics: MXMemoryMetric? {
        // Return mock memory metrics
        nil
    }
    
    override var diskIOMetrics: MXDiskIOMetric? {
        // Return mock disk metrics
        nil
    }
}

// MARK: - Test Extensions

extension MockCloudAnalyticsPersistence {
    func saveQueryRecord(_ record: QueryRecord, for repository: Repository) async throws {
        guard !shouldFail else {
            throw PersistenceError.saveFailed(error: NSError(domain: "Test", code: -1))
        }
    }
}

struct QueryRecord {
    let type: QueryPattern.QueryType
    let timestamp: Date
    let duration: TimeInterval
    let result: QueryResult
    
    enum QueryResult {
        case success
        case failure
    }
}
