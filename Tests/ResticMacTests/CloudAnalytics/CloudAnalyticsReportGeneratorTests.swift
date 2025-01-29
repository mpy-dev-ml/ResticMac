import XCTest
@testable import ResticMac

final class CloudAnalyticsReportGeneratorTests: XCTestCase {
    var generator: CloudAnalyticsReportGenerator!
    var persistence: MockCloudAnalyticsPersistence!
    var monitor: CloudAnalyticsMonitor!
    var optimizer: CloudAnalyticsOptimizer!
    var testDataDirectory: URL!
    var repository: Repository!
    
    override func setUp() async throws {
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacReportTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        persistence = MockCloudAnalyticsPersistence(storageURL: testDataDirectory)
        monitor = CloudAnalyticsMonitor.shared
        optimizer = CloudAnalyticsOptimizer(persistence: persistence, monitor: monitor)
        generator = CloudAnalyticsReportGenerator(
            persistence: persistence,
            monitor: monitor,
            optimizer: optimizer
        )
        
        repository = Repository(
            path: testDataDirectory.appendingPathComponent("test-repo"),
            password: "test-password",
            provider: .local
        )
        
        // Generate test data
        try await generateTestData()
    }
    
    override func tearDown() async throws {
        generator = nil
        persistence = nil
        monitor = nil
        optimizer = nil
        repository = nil
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Report Generation Tests
    
    func testExecutiveReport() async throws {
        let report = try await generator.generateReport(
            for: repository,
            type: .executive
        )
        
        // Verify executive report structure
        XCTAssertEqual(report.type, .executive)
        XCTAssertTrue(report.sections.contains { $0.title == "Executive Summary" })
        XCTAssertTrue(report.sections.contains { $0.title == "Key Metrics" })
        XCTAssertTrue(report.sections.contains { $0.title == "Cost Analysis" })
    }
    
    func testTechnicalReport() async throws {
        let report = try await generator.generateReport(
            for: repository,
            type: .technical
        )
        
        // Verify technical report structure
        XCTAssertEqual(report.type, .technical)
        XCTAssertTrue(report.sections.contains { $0.title == "Performance Analysis" })
        XCTAssertTrue(report.sections.contains { $0.title == "Error Analysis" })
        XCTAssertTrue(report.sections.contains { $0.title == "Optimisations" })
    }
    
    func testCostReport() async throws {
        let report = try await generator.generateReport(
            for: repository,
            type: .cost
        )
        
        // Verify cost report structure
        XCTAssertEqual(report.type, .cost)
        XCTAssertTrue(report.sections.contains { $0.title == "Cost Trends" })
        XCTAssertTrue(report.sections.contains { $0.title == "Cost Projections" })
        XCTAssertTrue(report.sections.contains { $0.title == "Cost Optimisations" })
    }
    
    func testPerformanceReport() async throws {
        let report = try await generator.generateReport(
            for: repository,
            type: .performance
        )
        
        // Verify performance report structure
        XCTAssertEqual(report.type, .performance)
        XCTAssertTrue(report.sections.contains { $0.title == "Resource Utilisation" })
        XCTAssertTrue(report.sections.contains { $0.title == "Bottleneck Analysis" })
        XCTAssertTrue(report.sections.contains { $0.title == "Performance Optimisations" })
    }
    
    func testCustomReport() async throws {
        var options = ReportOptions()
        options.includeSections = ["Storage Analysis", "Cost Analysis"]
        options.excludeSections = ["Error Analysis"]
        
        let report = try await generator.generateReport(
            for: repository,
            type: .custom,
            options: options
        )
        
        // Verify custom report structure
        XCTAssertEqual(report.type, .custom)
        XCTAssertTrue(report.sections.contains { $0.title == "Storage Analysis" })
        XCTAssertTrue(report.sections.contains { $0.title == "Cost Analysis" })
        XCTAssertFalse(report.sections.contains { $0.title == "Error Analysis" })
    }
    
    // MARK: - Time Range Tests
    
    func testTimeRangeFiltering() async throws {
        let now = Date()
        let timeRange = DateInterval(
            start: now.addingTimeInterval(-7 * 24 * 3600), // 1 week ago
            end: now
        )
        
        let report = try await generator.generateReport(
            for: repository,
            type: .executive,
            timeRange: timeRange
        )
        
        // Verify time range filtering
        XCTAssertEqual(report.timeRange?.start, timeRange.start)
        XCTAssertEqual(report.timeRange?.end, timeRange.end)
    }
    
    // MARK: - Insight Tests
    
    func testStorageInsights() async throws {
        // Generate high storage growth
        try await generateHighStorageGrowth()
        
        let report = try await generator.generateReport(
            for: repository,
            type: .executive
        )
        
        // Verify storage insights
        XCTAssertTrue(report.insights.contains { 
            $0.title == "High Storage Growth" &&
            $0.category == .storage &&
            $0.severity == .warning
        })
    }
    
    func testPerformanceInsights() async throws {
        // Generate high CPU usage
        try await generateHighCPUUsage()
        
        let report = try await generator.generateReport(
            for: repository,
            type: .technical
        )
        
        // Verify performance insights
        XCTAssertTrue(report.insights.contains {
            $0.title == "High CPU Utilisation" &&
            $0.category == .performance &&
            $0.severity == .warning
        })
    }
    
    func testCostInsights() async throws {
        // Generate rising costs
        try await generateRisingCosts()
        
        let report = try await generator.generateReport(
            for: repository,
            type: .cost
        )
        
        // Verify cost insights
        XCTAssertTrue(report.insights.contains {
            $0.title == "Rising Costs" &&
            $0.category == .cost &&
            $0.severity == .warning
        })
    }
    
    // MARK: - Recommendation Tests
    
    func testStorageRecommendations() async throws {
        let report = try await generator.generateReport(
            for: repository,
            type: .executive
        )
        
        // Verify storage recommendations
        XCTAssertTrue(report.recommendations.contains {
            $0.title.contains("Storage") &&
            $0.impact == .high
        })
    }
    
    func testPerformanceRecommendations() async throws {
        let report = try await generator.generateReport(
            for: repository,
            type: .performance
        )
        
        // Verify performance recommendations
        XCTAssertTrue(report.recommendations.contains {
            $0.title.contains("Performance") &&
            $0.effort == .medium
        })
    }
    
    func testCostRecommendations() async throws {
        let report = try await generator.generateReport(
            for: repository,
            type: .cost
        )
        
        // Verify cost recommendations
        XCTAssertTrue(report.recommendations.contains {
            $0.title.contains("Cost") &&
            $0.priority == .high
        })
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidData() async throws {
        persistence.shouldFail = true
        
        do {
            _ = try await generator.generateReport(
                for: repository,
                type: .executive
            )
            XCTFail("Expected report generation to fail")
        } catch let error as ReportError {
            if case .invalidData = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testMissingMetrics() async throws {
        // Clear all metrics
        try await persistence.clearMetrics(for: repository)
        
        do {
            _ = try await generator.generateReport(
                for: repository,
                type: .executive
            )
            XCTFail("Expected report generation to fail")
        } catch let error as ReportError {
            if case .missingMetrics = error {
                // Expected error
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateTestData() async throws {
        let now = Date()
        
        // Generate storage metrics
        var storagePoints: [TimeSeriesPoint<StorageMetrics>] = []
        for i in 0..<30 {
            storagePoints.append(TimeSeriesPoint(
                timestamp: now.addingTimeInterval(Double(-i * 24 * 3600)),
                value: StorageMetrics(
                    totalBytes: Int64(1_000_000 + i * 50_000),
                    compressedBytes: Int64(800_000 + i * 40_000),
                    deduplicatedBytes: Int64(600_000 + i * 30_000)
                )
            ))
        }
        try await persistence.saveStorageMetricsHistory(storagePoints, for: repository)
        
        // Generate performance metrics
        var performancePoints: [PerformanceMetrics] = []
        for i in 0..<30 {
            performancePoints.append(PerformanceMetrics(
                cpu: CPUMetrics(
                    usage: 0.5 + Double(i) * 0.01,
                    systemTime: TimeInterval(i * 60),
                    userTime: TimeInterval(i * 30)
                ),
                memory: MemoryMetrics(
                    residentSize: Int64(100_000_000 + i * 1_000_000),
                    virtualSize: Int64(200_000_000 + i * 2_000_000),
                    peakResidentSize: Int64(150_000_000 + i * 1_500_000)
                ),
                disk: DiskMetrics(
                    bytesRead: Int64(1_000_000 + i * 100_000),
                    bytesWritten: Int64(500_000 + i * 50_000),
                    operations: i * 100
                ),
                network: NetworkMetrics(
                    bytesTransferred: Int64(2_000_000 + i * 200_000),
                    requests: i * 50,
                    latency: TimeInterval(0.1 + Double(i) * 0.01)
                ),
                timestamp: now.addingTimeInterval(Double(-i * 24 * 3600))
            ))
        }
        try await persistence.savePerformanceHistory(performancePoints, for: repository)
        
        // Generate cost metrics
        var costPoints: [TimeSeriesPoint<CostMetrics>] = []
        for i in 0..<30 {
            costPoints.append(TimeSeriesPoint(
                timestamp: now.addingTimeInterval(Double(-i * 24 * 3600)),
                value: CostMetrics(
                    storageUnitCost: 0.02,
                    transferUnitCost: 0.01,
                    totalCost: Double(100 + i * 5)
                )
            ))
        }
        try await persistence.saveCostMetricsHistory(costPoints, for: repository)
    }
    
    private func generateHighStorageGrowth() async throws {
        let now = Date()
        var points: [TimeSeriesPoint<StorageMetrics>] = []
        
        for i in 0..<30 {
            points.append(TimeSeriesPoint(
                timestamp: now.addingTimeInterval(Double(-i * 24 * 3600)),
                value: StorageMetrics(
                    totalBytes: Int64(1_000_000 * pow(1.2, Double(30 - i))),
                    compressedBytes: Int64(800_000 * pow(1.2, Double(30 - i))),
                    deduplicatedBytes: Int64(600_000 * pow(1.2, Double(30 - i)))
                )
            ))
        }
        
        try await persistence.saveStorageMetricsHistory(points, for: repository)
    }
    
    private func generateHighCPUUsage() async throws {
        let now = Date()
        var points: [PerformanceMetrics] = []
        
        for i in 0..<30 {
            points.append(PerformanceMetrics(
                cpu: CPUMetrics(
                    usage: 0.85 + Double(i) * 0.005,
                    systemTime: TimeInterval(i * 60),
                    userTime: TimeInterval(i * 30)
                ),
                memory: MemoryMetrics(
                    residentSize: Int64(100_000_000),
                    virtualSize: Int64(200_000_000),
                    peakResidentSize: Int64(150_000_000)
                ),
                disk: DiskMetrics(
                    bytesRead: Int64(1_000_000),
                    bytesWritten: Int64(500_000),
                    operations: 100
                ),
                network: NetworkMetrics(
                    bytesTransferred: Int64(2_000_000),
                    requests: 50,
                    latency: 0.1
                ),
                timestamp: now.addingTimeInterval(Double(-i * 24 * 3600))
            ))
        }
        
        try await persistence.savePerformanceHistory(points, for: repository)
    }
    
    private func generateRisingCosts() async throws {
        let now = Date()
        var points: [TimeSeriesPoint<CostMetrics>] = []
        
        for i in 0..<30 {
            points.append(TimeSeriesPoint(
                timestamp: now.addingTimeInterval(Double(-i * 24 * 3600)),
                value: CostMetrics(
                    storageUnitCost: 0.02,
                    transferUnitCost: 0.01,
                    totalCost: Double(100 * pow(1.15, Double(30 - i)))
                )
            ))
        }
        
        try await persistence.saveCostMetricsHistory(points, for: repository)
    }
}

// MARK: - Test Extensions

extension MockCloudAnalyticsPersistence {
    func clearMetrics(for repository: Repository) async throws {
        // Clear all metrics for testing
        try await saveStorageMetricsHistory([], for: repository)
        try await savePerformanceHistory([], for: repository)
        try await saveCostMetricsHistory([], for: repository)
    }
    
    func savePerformanceHistory(
        _ metrics: [PerformanceMetrics],
        for repository: Repository
    ) async throws {
        guard !shouldFail else {
            throw PersistenceError.saveFailed(error: NSError(domain: "Test", code: -1))
        }
    }
}
