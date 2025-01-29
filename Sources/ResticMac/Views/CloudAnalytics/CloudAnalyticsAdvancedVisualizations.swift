import SwiftUI
import Charts

// MARK: - Advanced Storage Analysis

struct StorageAnalysisChart: View {
    let storageData: [TimeSeriesPoint<StorageMetrics>]
    let analysisType: StorageAnalysisType
    
    var body: some View {
        Chart {
            ForEach(analysisMetrics) { metric in
                LineMark(
                    x: .value("Time", metric.timestamp),
                    y: .value("Value", metric.value)
                )
                .foregroundStyle(by: .value("Metric", metric.name))
                .symbol(by: .value("Metric", metric.name))
                .interpolationMethod(.catmullRom)
            }
            
            if showTrend {
                let trend = calculateTrendLine()
                LineMark(
                    x: .value("Time", trend.startDate),
                    y: .value("Value", trend.startValue)
                )
                LineMark(
                    x: .value("Time", trend.endDate),
                    y: .value("Value", trend.endValue)
                )
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(dash: [5, 5]))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    Text(formatSize(value.as(Double.self) ?? 0))
                }
            }
        }
        .chartLegend(position: .bottom)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture()
                        .onChanged { value in
                            updateTooltip(at: value.location, proxy: proxy, geometry: geometry)
                        }
                    )
            }
        }
    }
    
    private var analysisMetrics: [AnalysisMetric] {
        switch analysisType {
        case .compression:
            return compressionAnalysis
        case .deduplication:
            return deduplicationAnalysis
        case .growth:
            return growthAnalysis
        }
    }
    
    private var compressionAnalysis: [AnalysisMetric] {
        storageData.map { point in
            let ratio = Double(point.value.compressedBytes) / Double(point.value.totalBytes)
            return AnalysisMetric(
                timestamp: point.timestamp,
                value: ratio,
                name: "Compression Ratio"
            )
        }
    }
    
    private var deduplicationAnalysis: [AnalysisMetric] {
        storageData.map { point in
            let ratio = Double(point.value.deduplicatedBytes) / Double(point.value.totalBytes)
            return AnalysisMetric(
                timestamp: point.timestamp,
                value: ratio,
                name: "Deduplication Ratio"
            )
        }
    }
    
    private var growthAnalysis: [AnalysisMetric] {
        var metrics: [AnalysisMetric] = []
        var previousBytes: Int64 = 0
        
        for point in storageData {
            let growth = Double(point.value.totalBytes - previousBytes)
            metrics.append(AnalysisMetric(
                timestamp: point.timestamp,
                value: growth,
                name: "Storage Growth"
            ))
            previousBytes = point.value.totalBytes
        }
        
        return metrics
    }
}

// MARK: - Cost Analysis

struct CostAnalysisChart: View {
    let costData: [TimeSeriesPoint<CostMetrics>]
    let projectionMonths: Int
    
    var body: some View {
        Chart {
            // Historical cost data
            ForEach(costMetrics) { metric in
                LineMark(
                    x: .value("Time", metric.timestamp),
                    y: .value("Cost", metric.value)
                )
                .foregroundStyle(by: .value("Type", metric.name))
            }
            
            // Cost projection
            if let projection = calculateProjection() {
                AreaMark(
                    x: .value("Time", projection.startDate),
                    y: .value("Cost", projection.lowerBound)
                )
                AreaMark(
                    x: .value("Time", projection.endDate),
                    y: .value("Cost", projection.upperBound)
                )
                .foregroundStyle(.blue.opacity(0.2))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    Text(formatCurrency(value.as(Double.self) ?? 0))
                }
            }
        }
        .chartLegend(position: .bottom)
    }
    
    private var costMetrics: [CostMetric] {
        costData.flatMap { point in
            [
                CostMetric(
                    timestamp: point.timestamp,
                    value: point.value.storageUnitCost,
                    name: "Storage Cost"
                ),
                CostMetric(
                    timestamp: point.timestamp,
                    value: point.value.transferUnitCost,
                    name: "Transfer Cost"
                ),
                CostMetric(
                    timestamp: point.timestamp,
                    value: point.value.totalCost,
                    name: "Total Cost"
                )
            ]
        }
    }
}

// MARK: - Performance Analysis

struct PerformanceAnalysisChart: View {
    let transferData: [TimeSeriesPoint<TransferMetrics>]
    let windowSize: Int
    
    var body: some View {
        Chart {
            // Transfer speed
            ForEach(speedMetrics) { metric in
                LineMark(
                    x: .value("Time", metric.timestamp),
                    y: .value("Speed", metric.value)
                )
                .foregroundStyle(by: .value("Type", "Transfer Speed"))
            }
            
            // Moving average
            ForEach(movingAverageMetrics) { metric in
                LineMark(
                    x: .value("Time", metric.timestamp),
                    y: .value("Speed", metric.value)
                )
                .foregroundStyle(by: .value("Type", "Moving Average"))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            
            // Success rate
            ForEach(successRateMetrics) { metric in
                PointMark(
                    x: .value("Time", metric.timestamp),
                    y: .value("Rate", metric.value)
                )
                .foregroundStyle(by: .value("Type", "Success Rate"))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    Text(formatSpeed(value.as(Double.self) ?? 0))
                }
            }
        }
        .chartLegend(position: .bottom)
    }
    
    private var speedMetrics: [PerformanceMetric] {
        transferData.map { point in
            PerformanceMetric(
                timestamp: point.timestamp,
                value: point.value.averageTransferSpeed,
                name: "Transfer Speed"
            )
        }
    }
    
    private var movingAverageMetrics: [PerformanceMetric] {
        calculateMovingAverage(windowSize: windowSize)
    }
    
    private var successRateMetrics: [PerformanceMetric] {
        transferData.map { point in
            PerformanceMetric(
                timestamp: point.timestamp,
                value: point.value.successRate * 100,
                name: "Success Rate"
            )
        }
    }
}

// MARK: - Insights View

struct AnalyticsInsightsView: View {
    let storageData: [TimeSeriesPoint<StorageMetrics>]
    let transferData: [TimeSeriesPoint<TransferMetrics>]
    let costData: [TimeSeriesPoint<CostMetrics>]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Analytics Insights")
                .font(.title)
            
            // Storage insights
            InsightCard(
                title: "Storage Efficiency",
                insights: calculateStorageInsights(),
                icon: "chart.bar.fill"
            )
            
            // Performance insights
            InsightCard(
                title: "Performance Metrics",
                insights: calculatePerformanceInsights(),
                icon: "speedometer"
            )
            
            // Cost insights
            InsightCard(
                title: "Cost Analysis",
                insights: calculateCostInsights(),
                icon: "dollarsign.circle.fill"
            )
            
            // Recommendations
            RecommendationsView(
                recommendations: generateRecommendations()
            )
        }
        .padding()
    }
    
    private func calculateStorageInsights() -> [Insight] {
        let compressionRatio = calculateCompressionRatio()
        let deduplicationRatio = calculateDeduplicationRatio()
        let growthRate = calculateGrowthRate()
        
        return [
            Insight(
                title: "Compression Efficiency",
                value: String(format: "%.1f%%", compressionRatio * 100),
                trend: .up,
                description: "Space saved through compression"
            ),
            Insight(
                title: "Deduplication Rate",
                value: String(format: "%.1f%%", deduplicationRatio * 100),
                trend: .up,
                description: "Space saved through deduplication"
            ),
            Insight(
                title: "Growth Rate",
                value: String(format: "%.1f GB/month", growthRate / 1_000_000_000),
                trend: .neutral,
                description: "Average monthly storage growth"
            )
        ]
    }
}

// MARK: - Supporting Types

struct AnalysisMetric: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let name: String
}

struct CostMetric: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let name: String
}

struct PerformanceMetric: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let name: String
}

enum StorageAnalysisType {
    case compression
    case deduplication
    case growth
}

struct Insight {
    let title: String
    let value: String
    let trend: InsightTrend
    let description: String
}

enum InsightTrend {
    case up
    case down
    case neutral
}

struct CostProjection {
    let startDate: Date
    let endDate: Date
    let lowerBound: Double
    let upperBound: Double
}

// MARK: - Helper Views

struct InsightCard: View {
    let title: String
    let insights: [Insight]
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.headline)
            }
            
            ForEach(insights, id: \.title) { insight in
                HStack {
                    VStack(alignment: .leading) {
                        Text(insight.title)
                            .font(.subheadline)
                        Text(insight.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(insight.value)
                        .font(.title3)
                        .foregroundColor(trendColor(insight.trend))
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private func trendColor(_ trend: InsightTrend) -> Color {
        switch trend {
        case .up: return .green
        case .down: return .red
        case .neutral: return .primary
        }
    }
}

struct RecommendationsView: View {
    let recommendations: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendations")
                .font(.headline)
            
            ForEach(recommendations, id: \.self) { recommendation in
                HStack(alignment: .top) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text(recommendation)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Helper Functions

private func formatSize(_ bytes: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    return formatter.string(fromByteCount: Int64(bytes))
}

private func formatCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
}

private func formatSpeed(_ bytesPerSecond: Double) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
}
