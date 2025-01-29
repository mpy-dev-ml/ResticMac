import XCTest
@testable import ResticMac

final class CloudAnalyticsMonitorTests: XCTestCase {
    var monitor: CloudAnalyticsMonitor!
    
    override func setUp() async throws {
        monitor = CloudAnalyticsMonitor.shared
    }
    
    // MARK: - Performance Monitoring Tests
    
    func testOperationTracking() async throws {
        let tracker = await monitor.trackOperation("test_operation")
        
        // Simulate work
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let duration = tracker.stop()
        XCTAssertGreaterThanOrEqual(duration, 1.0)
        XCTAssertLessThan(duration, 1.5) // Allow some overhead
    }
    
    func testMetricRecording() async throws {
        // Record various metrics
        await monitor.recordMetric(.processingTime, value: 1.5)
        await monitor.recordMetric(.errorRate, value: 0.02)
        await monitor.recordMetric(.queueDepth, value: 50)
        
        // Export and verify
        let exportData = try await monitor.exportMetrics()
        let metrics = try JSONDecoder().decode(MetricsExport.self, from: exportData)
        
        XCTAssertFalse(metrics.systemMetrics.metricValues.isEmpty)
    }
    
    // MARK: - Health Monitoring Tests
    
    func testSystemHealthCheck() async throws {
        let health = await monitor.checkSystemHealth()
        
        XCTAssertNotNil(health)
        XCTAssertEqual(health.status, .healthy)
        XCTAssertFalse(health.details.isEmpty)
    }
    
    func testResourceMonitoring() async throws {
        await monitor.monitorResourceUsage()
        
        let exportData = try await monitor.exportMetrics()
        let metrics = try JSONDecoder().decode(MetricsExport.self, from: exportData)
        
        XCTAssertFalse(metrics.healthHistory.isEmpty)
    }
    
    // MARK: - Alert Tests
    
    func testPerformanceAlert() async throws {
        let alertExpectation = expectation(description: "Performance alert received")
        let testSubscriber = TestAlertSubscriber { alert in
            if case .performanceWarning = alert {
                alertExpectation.fulfill()
            }
        }
        
        await monitor.recordMetric(.processingTime, value: 10.0) // Should trigger alert
        
        await waitForExpectations(timeout: 5.0)
    }
    
    func testErrorRateAlert() async throws {
        let alertExpectation = expectation(description: "Error rate alert received")
        let testSubscriber = TestAlertSubscriber { alert in
            if case .errorRateWarning = alert {
                alertExpectation.fulfill()
            }
        }
        
        await monitor.recordMetric(.errorRate, value: 0.1) // Should trigger alert
        
        await waitForExpectations(timeout: 5.0)
    }
    
    func testResourceAlert() async throws {
        let alertExpectation = expectation(description: "Resource alert received")
        let testSubscriber = TestAlertSubscriber { alert in
            if case .resourceWarning = alert {
                alertExpectation.fulfill()
            }
        }
        
        await monitor.recordMetric(.queueDepth, value: 150) // Should trigger alert
        
        await waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Export Tests
    
    func testMetricsExport() async throws {
        // Record some test data
        let tracker = await monitor.trackOperation("export_test")
        try await Task.sleep(nanoseconds: 100_000_000)
        tracker.stop()
        
        await monitor.recordMetric(.processingTime, value: 1.0)
        await monitor.recordMetric(.errorRate, value: 0.01)
        
        let health = await monitor.checkSystemHealth()
        XCTAssertEqual(health.status, .healthy)
        
        // Export and verify
        let exportData = try await monitor.exportMetrics()
        let metrics = try JSONDecoder().decode(MetricsExport.self, from: exportData)
        
        XCTAssertFalse(metrics.systemMetrics.operationTimes.isEmpty)
        XCTAssertFalse(metrics.healthHistory.isEmpty)
    }
    
    // MARK: - Stress Tests
    
    func testConcurrentMetricRecording() async throws {
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let tracker = await self.monitor.trackOperation("concurrent_test_\(i)")
                    try await Task.sleep(nanoseconds: UInt64.random(in: 1000...1_000_000))
                    tracker.stop()
                    
                    await self.monitor.recordMetric(.processingTime, value: Double.random(in: 0.1...5.0))
                    await self.monitor.recordMetric(.errorRate, value: Double.random(in: 0...0.1))
                    await self.monitor.recordMetric(.queueDepth, value: Double.random(in: 0...200))
                }
            }
        }
        
        let exportData = try await monitor.exportMetrics()
        let metrics = try JSONDecoder().decode(MetricsExport.self, from: exportData)
        
        XCTAssertFalse(metrics.systemMetrics.operationTimes.isEmpty)
        XCTAssertFalse(metrics.systemMetrics.metricValues.isEmpty)
    }
    
    func testLongRunningMonitoring() async throws {
        let duration: TimeInterval = 5 // 5 seconds
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < duration {
            let tracker = await monitor.trackOperation("long_running_test")
            try await Task.sleep(nanoseconds: 100_000_000)
            tracker.stop()
            
            await monitor.recordMetric(.processingTime, value: Double.random(in: 0.1...5.0))
            await monitor.checkSystemHealth()
            await monitor.monitorResourceUsage()
        }
        
        let exportData = try await monitor.exportMetrics()
        let metrics = try JSONDecoder().decode(MetricsExport.self, from: exportData)
        
        XCTAssertFalse(metrics.systemMetrics.operationTimes.isEmpty)
        XCTAssertFalse(metrics.healthHistory.isEmpty)
        XCTAssertFalse(metrics.alertHistory.isEmpty)
    }
}

// MARK: - Test Helpers

class TestAlertSubscriber: AlertSubscriber {
    private let callback: (Alert) -> Void
    
    init(callback: @escaping (Alert) -> Void) {
        self.callback = callback
    }
    
    func onAlert(_ alert: Alert) {
        callback(alert)
    }
}
