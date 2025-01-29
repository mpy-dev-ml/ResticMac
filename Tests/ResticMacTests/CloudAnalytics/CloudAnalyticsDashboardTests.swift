import XCTest
import SwiftUI
@testable import ResticMac

final class CloudAnalyticsDashboardTests: XCTestCase {
    // MARK: - Performance Chart Tests
    
    func testPerformanceChartDataDisplay() throws {
        let metrics = [
            PerformanceMetric(name: "CPU", timestamp: Date(), value: 50),
            PerformanceMetric(name: "Memory", timestamp: Date().addingTimeInterval(3600), value: 75)
        ]
        
        let chart = PerformanceChart(metrics: metrics, timeRange: .hour)
        assertSnapshot(matching: chart, as: .image)
    }
    
    func testPerformanceChartTimeRanges() throws {
        let baseDate = Date()
        let metrics = (0..<24).map { hour in
            PerformanceMetric(
                name: "CPU",
                timestamp: baseDate.addingTimeInterval(Double(hour * 3600)),
                value: Double.random(in: 0...100)
            )
        }
        
        let hourChart = PerformanceChart(metrics: metrics, timeRange: .hour)
        let dayChart = PerformanceChart(metrics: metrics, timeRange: .day)
        
        assertSnapshot(matching: hourChart, as: .image)
        assertSnapshot(matching: dayChart, as: .image)
    }
    
    // MARK: - Health Status Card Tests
    
    func testHealthStatusCardStates() throws {
        let healthyStatus = SystemHealth(
            status: .healthy,
            details: "All systems operational",
            timestamp: Date()
        )
        
        let degradedStatus = SystemHealth(
            status: .degraded,
            details: "Performance degradation detected",
            timestamp: Date()
        )
        
        let unhealthyStatus = SystemHealth(
            status: .unhealthy,
            details: "Critical system failure",
            timestamp: Date()
        )
        
        let healthyCard = HealthStatusCard(status: healthyStatus) {}
        let degradedCard = HealthStatusCard(status: degradedStatus) {}
        let unhealthyCard = HealthStatusCard(status: unhealthyStatus) {}
        
        assertSnapshot(matching: healthyCard, as: .image)
        assertSnapshot(matching: degradedCard, as: .image)
        assertSnapshot(matching: unhealthyCard, as: .image)
    }
    
    func testHealthStatusCardInteraction() throws {
        let expectation = XCTestExpectation(description: "Refresh button tapped")
        
        let status = SystemHealth(
            status: .healthy,
            details: "All systems operational",
            timestamp: Date()
        )
        
        let card = HealthStatusCard(status: status) {
            expectation.fulfill()
        }
        
        // Simulate button tap
        let button = try XCTUnwrap(card.find(viewWithId: "refreshButton"))
        button.tap()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Resource Monitor Tests
    
    func testResourceMonitorDisplay() throws {
        let usage = ResourceUsage(
            cpuUsage: 45.5,
            memoryUsage: 2_000_000_000, // 2GB
            diskUsage: 50_000_000_000 // 50GB
        )
        
        let history = (0..<10).map { minute in
            ResourceMetric(
                name: "CPU",
                timestamp: Date().addingTimeInterval(Double(minute * 60)),
                value: Double.random(in: 0...100)
            )
        }
        
        let monitor = ResourceMonitor(usage: usage, history: history)
        assertSnapshot(matching: monitor, as: .image)
    }
    
    func testResourceGaugeThresholds() throws {
        let normalGauge = ResourceGauge(
            title: "CPU",
            value: 50,
            unit: "%",
            threshold: 100
        )
        
        let warningGauge = ResourceGauge(
            title: "CPU",
            value: 75,
            unit: "%",
            threshold: 100
        )
        
        let criticalGauge = ResourceGauge(
            title: "CPU",
            value: 95,
            unit: "%",
            threshold: 100
        )
        
        assertSnapshot(matching: normalGauge, as: .image)
        assertSnapshot(matching: warningGauge, as: .image)
        assertSnapshot(matching: criticalGauge, as: .image)
    }
    
    // MARK: - Alert List Tests
    
    func testAlertListDisplay() throws {
        let alerts: [Alert] = [
            .performanceWarning("High CPU usage detected"),
            .errorRateWarning("Error rate above threshold"),
            .resourceWarning("Low disk space")
        ]
        
        let list = AlertList(alerts: alerts) { _ in }
        assertSnapshot(matching: list, as: .image)
    }
    
    func testAlertDismissal() throws {
        let expectation = XCTestExpectation(description: "Alert dismissed")
        let alert: Alert = .performanceWarning("Test alert")
        
        let list = AlertList(alerts: [alert]) { dismissedAlert in
            XCTAssertEqual(dismissedAlert.id, alert.id)
            expectation.fulfill()
        }
        
        // Simulate dismiss button tap
        let button = try XCTUnwrap(list.find(viewWithId: "dismissButton"))
        button.tap()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testEmptyAlertList() throws {
        let list = AlertList(alerts: []) { _ in }
        assertSnapshot(matching: list, as: .image)
    }
}

// MARK: - Test Helpers

extension View {
    func find<V: View>(viewWithId id: String) -> V? {
        let mirror = Mirror(reflecting: self)
        
        for child in mirror.children {
            if let view = child.value as? V,
               let viewId = view.accessibilityIdentifier,
               viewId == id {
                return view
            }
            
            if let view = (child.value as? View)?.find(viewWithId: id) as? V {
                return view
            }
        }
        
        return nil
    }
}

extension View {
    func assertSnapshot(
        matching value: Self,
        as snapshotting: Snapshotting<Self, NSImage>,
        named name: String? = nil,
        record recording: Bool = false,
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        // Implement snapshot testing logic
    }
}
