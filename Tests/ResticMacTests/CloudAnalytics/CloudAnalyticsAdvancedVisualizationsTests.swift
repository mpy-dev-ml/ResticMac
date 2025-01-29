import XCTest
import SwiftUI
@testable import ResticMac

final class CloudAnalyticsAdvancedVisualizationsTests: XCTestCase {
    var storageData: [TimeSeriesPoint<StorageMetrics>]!
    var transferData: [TimeSeriesPoint<TransferMetrics>]!
    var costData: [TimeSeriesPoint<CostMetrics>]!
    
    override func setUp() {
        super.setUp()
        generateTestData()
    }
    
    override func tearDown() {
        storageData = nil
        transferData = nil
        costData = nil
        super.tearDown()
    }
    
    // MARK: - Storage Analysis Tests
    
    func testStorageAnalysisChart() {
        let chart = StorageAnalysisChart(
            storageData: storageData,
            analysisType: .compression
        )
        
        // Test view hierarchy
        XCTAssertNotNil(chart.body)
        
        // Test metrics generation
        let metrics = chart.analysisMetrics
        XCTAssertFalse(metrics.isEmpty)
        
        // Test compression ratio calculation
        let compressionMetrics = metrics.filter { $0.name == "Compression Ratio" }
        XCTAssertFalse(compressionMetrics.isEmpty)
        
        // Verify ratio values are between 0 and 1
        for metric in compressionMetrics {
            XCTAssertGreaterThanOrEqual(metric.value, 0)
            XCTAssertLessThanOrEqual(metric.value, 1)
        }
    }
    
    func testDeduplicationAnalysis() {
        let chart = StorageAnalysisChart(
            storageData: storageData,
            analysisType: .deduplication
        )
        
        let metrics = chart.analysisMetrics
        let deduplicationMetrics = metrics.filter { $0.name == "Deduplication Ratio" }
        
        XCTAssertFalse(deduplicationMetrics.isEmpty)
        
        // Verify deduplication calculations
        for metric in deduplicationMetrics {
            XCTAssertGreaterThanOrEqual(metric.value, 0)
            XCTAssertLessThanOrEqual(metric.value, 1)
        }
    }
    
    func testGrowthAnalysis() {
        let chart = StorageAnalysisChart(
            storageData: storageData,
            analysisType: .growth
        )
        
        let metrics = chart.analysisMetrics
        let growthMetrics = metrics.filter { $0.name == "Storage Growth" }
        
        XCTAssertFalse(growthMetrics.isEmpty)
        
        // Verify growth calculations
        var previousValue: Double?
        for metric in growthMetrics {
            if let previous = previousValue {
                XCTAssertEqual(metric.value, metric.value - previous)
            }
            previousValue = metric.value
        }
    }
    
    // MARK: - Cost Analysis Tests
    
    func testCostAnalysisChart() {
        let chart = CostAnalysisChart(
            costData: costData,
            projectionMonths: 3
        )
        
        // Test view hierarchy
        XCTAssertNotNil(chart.body)
        
        // Test metrics generation
        let metrics = chart.costMetrics
        XCTAssertFalse(metrics.isEmpty)
        
        // Verify cost types
        let costTypes = Set(metrics.map { $0.name })
        XCTAssertTrue(costTypes.contains("Storage Cost"))
        XCTAssertTrue(costTypes.contains("Transfer Cost"))
        XCTAssertTrue(costTypes.contains("Total Cost"))
    }
    
    func testCostProjection() {
        let chart = CostAnalysisChart(
            costData: costData,
            projectionMonths: 3
        )
        
        if let projection = chart.calculateProjection() {
            XCTAssertGreaterThan(projection.endDate, projection.startDate)
            XCTAssertGreaterThanOrEqual(projection.upperBound, projection.lowerBound)
        }
    }
    
    // MARK: - Performance Analysis Tests
    
    func testPerformanceAnalysisChart() {
        let chart = PerformanceAnalysisChart(
            transferData: transferData,
            windowSize: 5
        )
        
        // Test view hierarchy
        XCTAssertNotNil(chart.body)
        
        // Test metrics generation
        let speedMetrics = chart.speedMetrics
        XCTAssertFalse(speedMetrics.isEmpty)
        
        let movingAverageMetrics = chart.movingAverageMetrics
        XCTAssertFalse(movingAverageMetrics.isEmpty)
        
        let successRateMetrics = chart.successRateMetrics
        XCTAssertFalse(successRateMetrics.isEmpty)
    }
    
    func testMovingAverageCalculation() {
        let chart = PerformanceAnalysisChart(
            transferData: transferData,
            windowSize: 5
        )
        
        let movingAverages = chart.movingAverageMetrics
        
        // Verify moving average size
        XCTAssertEqual(movingAverages.count, transferData.count - 4)
        
        // Verify moving average values
        for metric in movingAverages {
            XCTAssertGreaterThanOrEqual(metric.value, 0)
        }
    }
    
    // MARK: - Insights Tests
    
    func testAnalyticsInsights() {
        let insightsView = AnalyticsInsightsView(
            storageData: storageData,
            transferData: transferData,
            costData: costData
        )
        
        // Test view hierarchy
        XCTAssertNotNil(insightsView.body)
        
        // Test insights generation
        let storageInsights = insightsView.calculateStorageInsights()
        XCTAssertFalse(storageInsights.isEmpty)
        
        let performanceInsights = insightsView.calculatePerformanceInsights()
        XCTAssertFalse(performanceInsights.isEmpty)
        
        let costInsights = insightsView.calculateCostInsights()
        XCTAssertFalse(costInsights.isEmpty)
    }
    
    func testRecommendationsGeneration() {
        let insightsView = AnalyticsInsightsView(
            storageData: storageData,
            transferData: transferData,
            costData: costData
        )
        
        let recommendations = insightsView.generateRecommendations()
        XCTAssertFalse(recommendations.isEmpty)
    }
    
    // MARK: - Helper Methods
    
    private func generateTestData() {
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
        
        storageData = storagePoints
        transferData = transferPoints
        costData = costPoints
    }
}
