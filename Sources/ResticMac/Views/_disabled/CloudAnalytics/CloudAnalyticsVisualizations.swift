import SwiftUI
import Charts

struct CloudAnalyticsVisualizations: View {
    @StateObject private var viewModel: CloudAnalyticsVisualizationsViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    init(repository: Repository) {
        _viewModel = StateObject(wrappedValue: CloudAnalyticsVisualizationsViewModel(repository: repository))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Overview Section
                overviewSection
                
                // Storage Analysis
                storageSection
                
                // Performance Analysis
                performanceSection
                
                // Cost Analysis
                costSection
                
                // Insights
                insightsSection
            }
            .padding()
        }
        .navigationTitle("Analytics Visualisations")
        .task {
            await viewModel.loadData()
        }
    }
    
    // MARK: - Overview Section
    
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Overview", systemImage: "chart.xyaxis.line")
            
            HStack(spacing: 20) {
                MetricCard(
                    title: "Total Storage",
                    value: viewModel.formatBytes(viewModel.totalStorage),
                    trend: viewModel.storageTrend,
                    systemImage: "externaldrive.fill"
                )
                
                MetricCard(
                    title: "Transfer Rate",
                    value: viewModel.formatBytes(viewModel.transferRate) + "/s",
                    trend: viewModel.transferTrend,
                    systemImage: "arrow.up.arrow.down"
                )
                
                MetricCard(
                    title: "Monthly Cost",
                    value: viewModel.formatCurrency(viewModel.monthlyCost),
                    trend: viewModel.costTrend,
                    systemImage: "creditcard.fill"
                )
            }
        }
        .cardStyle()
    }
    
    // MARK: - Storage Section
    
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Storage Analysis", systemImage: "cylinder.split.1x2.fill")
            
            TabView {
                // Storage Over Time
                storageTimeChart
                    .tabItem {
                        Label("Timeline", systemImage: "clock.fill")
                    }
                
                // Storage Distribution
                storageDistributionChart
                    .tabItem {
                        Label("Distribution", systemImage: "circle.grid.2x2.fill")
                    }
                
                // Compression Ratio
                compressionChart
                    .tabItem {
                        Label("Compression", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
            }
            .frame(height: 300)
        }
        .cardStyle()
    }
    
    private var storageTimeChart: some View {
        Chart {
            ForEach(viewModel.storageHistory) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Size", point.value.totalBytes)
                )
                .foregroundStyle(Color.accentColor)
                
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Size", point.value.totalBytes)
                )
                .foregroundStyle(Color.accentColor.opacity(0.2))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text(viewModel.formatBytes(Int64(intValue)))
                    }
                }
            }
        }
    }
    
    private var storageDistributionChart: some View {
        Chart {
            ForEach(viewModel.storageDistribution) { item in
                SectorMark(
                    angle: .value("Size", item.size),
                    innerRadius: .ratio(0.618),
                    angularInset: 1.0
                )
                .foregroundStyle(by: .value("Category", item.category))
                .annotation(position: .overlay) {
                    Text(viewModel.formatBytes(item.size))
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private var compressionChart: some View {
        Chart {
            ForEach(viewModel.compressionHistory) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Ratio", point.ratio)
                )
                .foregroundStyle(Color.green)
                
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Ratio", point.ratio)
                )
                .foregroundStyle(Color.green.opacity(0.2))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(String(format: "%.2fx", doubleValue))
                    }
                }
            }
        }
    }
    
    // MARK: - Performance Section
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Performance Analysis", systemImage: "gauge")
            
            HStack(spacing: 20) {
                // CPU Usage
                PerformanceGauge(
                    value: viewModel.cpuUsage,
                    title: "CPU Usage",
                    systemImage: "cpu",
                    color: .blue
                )
                
                // Memory Usage
                PerformanceGauge(
                    value: viewModel.memoryUsage,
                    title: "Memory",
                    systemImage: "memorychip",
                    color: .purple
                )
                
                // Disk I/O
                PerformanceGauge(
                    value: viewModel.diskUsage,
                    title: "Disk I/O",
                    systemImage: "internaldrive",
                    color: .orange
                )
            }
            
            // Performance Timeline
            performanceTimelineChart
                .frame(height: 200)
        }
        .cardStyle()
    }
    
    private var performanceTimelineChart: some View {
        Chart {
            ForEach(viewModel.performanceHistory) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("CPU", point.cpu.usage)
                )
                .foregroundStyle(.blue)
                
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Memory", Double(point.memory.residentSize) / Double(point.memory.peakResidentSize))
                )
                .foregroundStyle(.purple)
                
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Disk", Double(point.disk.operations) / 100.0)
                )
                .foregroundStyle(.orange)
            }
        }
    }
    
    // MARK: - Cost Section
    
    private var costSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Cost Analysis", systemImage: "dollarsign.circle.fill")
            
            TabView {
                // Cost Over Time
                costTimeChart
                    .tabItem {
                        Label("Timeline", systemImage: "clock.fill")
                    }
                
                // Cost Breakdown
                costBreakdownChart
                    .tabItem {
                        Label("Breakdown", systemImage: "chart.pie.fill")
                    }
                
                // Cost Projection
                costProjectionChart
                    .tabItem {
                        Label("Projection", systemImage: "chart.line.uptrend.xyaxis")
                    }
            }
            .frame(height: 300)
        }
        .cardStyle()
    }
    
    private var costTimeChart: some View {
        Chart {
            ForEach(viewModel.costHistory) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Cost", point.value.totalCost)
                )
                .foregroundStyle(Color.green)
                
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Cost", point.value.totalCost)
                )
                .foregroundStyle(Color.green.opacity(0.2))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(viewModel.formatCurrency(doubleValue))
                    }
                }
            }
        }
    }
    
    private var costBreakdownChart: some View {
        Chart {
            ForEach(viewModel.costBreakdown) { item in
                SectorMark(
                    angle: .value("Cost", item.cost),
                    innerRadius: .ratio(0.618),
                    angularInset: 1.0
                )
                .foregroundStyle(by: .value("Category", item.category))
                .annotation(position: .overlay) {
                    Text(viewModel.formatCurrency(item.cost))
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private var costProjectionChart: some View {
        Chart {
            ForEach(viewModel.costProjection) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Cost", point.projectedCost)
                )
                .foregroundStyle(.blue)
                
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Cost", point.projectedCost)
                )
                .foregroundStyle(.blue.opacity(0.2))
                
                if let actualCost = point.actualCost {
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Actual", actualCost)
                    )
                    .foregroundStyle(.green)
                }
            }
        }
    }
    
    // MARK: - Insights Section
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Insights", systemImage: "lightbulb.fill")
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(viewModel.insights) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    let systemImage: String
    
    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.title2)
            .fontWeight(.semibold)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let trend: Double
    let systemImage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            
            HStack {
                Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text(String(format: "%.1f%%", abs(trend)))
                    .font(.caption)
            }
            .foregroundColor(trend >= 0 ? .red : .green)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct PerformanceGauge: View {
    let value: Double
    let title: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        VStack {
            Gauge(value: value) {
                Label(title, systemImage: systemImage)
                    .font(.caption)
            } currentValueLabel: {
                Text(String(format: "%.1f%%", value * 100))
                    .font(.caption2)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct InsightCard: View {
    let insight: AnalyticsInsight
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(insight.title, systemImage: insight.systemImage)
                .font(.headline)
            
            Text(insight.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let action = insight.recommendedAction {
                Text(action)
                    .font(.caption)
                    .padding(4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - View Modifiers

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}

// MARK: - Preview

struct CloudAnalyticsVisualizations_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CloudAnalyticsVisualizations(
                repository: Repository(
                    path: URL(fileURLWithPath: "/tmp/test"),
                    password: "test",
                    provider: .local
                )
            )
        }
    }
}
