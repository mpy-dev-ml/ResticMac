import SwiftUI
import Charts

struct CloudAnalyticsView: View {
    @StateObject private var viewModel: CloudAnalyticsViewModel
    @State private var selectedTimeRange: TimeRange = .month
    @State private var selectedMetricType: MetricType = .storage
    @State private var selectedChart: ChartType = .timeline
    
    init(repository: Repository) {
        _viewModel = StateObject(wrappedValue: CloudAnalyticsViewModel(repository: repository))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header Controls
            HStack {
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                
                Picker("Metric Type", selection: $selectedMetricType) {
                    ForEach(MetricType.allCases) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                
                Picker("Chart Type", selection: $selectedChart) {
                    ForEach(ChartType.allCases) { chart in
                        Label(chart.displayName, systemImage: chart.iconName).tag(chart)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            
            // Main Content
            if viewModel.isLoading {
                ProgressView("Loading Analytics...")
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Summary Cards
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            MetricCard(
                                title: "Storage Used",
                                value: viewModel.formattedStorageUsed,
                                trend: viewModel.storageGrowthRate,
                                icon: "externaldrive.fill"
                            )
                            
                            MetricCard(
                                title: "Monthly Cost",
                                value: viewModel.formattedMonthlyCost,
                                trend: viewModel.costTrend,
                                icon: "creditcard.fill"
                            )
                            
                            MetricCard(
                                title: "Transfer Rate",
                                value: viewModel.formattedTransferRate,
                                trend: viewModel.transferTrend,
                                icon: "arrow.up.arrow.down"
                            )
                        }
                        .padding(.horizontal)
                        
                        // Main Chart
                        ChartContainer(
                            title: selectedMetricType.displayName,
                            chart: selectedChart,
                            data: viewModel.chartData(for: selectedMetricType, range: selectedTimeRange)
                        )
                        .frame(height: 300)
                        .padding()
                        
                        // Details Grid
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 20) {
                            // Storage Details
                            DetailSection(
                                title: "Storage Details",
                                items: [
                                    ("Total Size", viewModel.formattedStorageUsed),
                                    ("Compressed", viewModel.formattedCompressedSize),
                                    ("Deduplicated", viewModel.formattedDeduplicatedSize),
                                    ("Pack Files", "\(viewModel.analytics?.storageMetrics.packFiles ?? 0)")
                                ]
                            )
                            
                            // Transfer Details
                            DetailSection(
                                title: "Transfer Details",
                                items: [
                                    ("Uploaded", viewModel.formattedUploadedBytes),
                                    ("Downloaded", viewModel.formattedDownloadedBytes),
                                    ("Success Rate", viewModel.formattedSuccessRate),
                                    ("Avg Speed", viewModel.formattedAverageSpeed)
                                ]
                            )
                            
                            // Cost Details
                            DetailSection(
                                title: "Cost Details",
                                items: [
                                    ("Storage Cost", viewModel.formattedStorageCost),
                                    ("Transfer Cost", viewModel.formattedTransferCost),
                                    ("Total Cost", viewModel.formattedTotalCost),
                                    ("Billing Cycle", viewModel.formattedBillingCycle)
                                ]
                            )
                            
                            // Snapshot Details
                            DetailSection(
                                title: "Snapshot Details",
                                items: [
                                    ("Total Snapshots", "\(viewModel.analytics?.snapshotMetrics.totalSnapshots ?? 0)"),
                                    ("Daily Average", String(format: "%.1f", viewModel.analytics?.snapshotMetrics.snapshotsPerDay ?? 0)),
                                    ("Avg Size", viewModel.formattedAverageSnapshotSize),
                                    ("Retention", "\(viewModel.analytics?.snapshotMetrics.retentionDays ?? 0) days")
                                ]
                            )
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Cloud Analytics")
        .task {
            await viewModel.loadAnalytics()
        }
        .refreshable {
            await viewModel.loadAnalytics()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error occurred")
        }
    }
}

// MARK: - Supporting Views

struct MetricCard: View {
    let title: String
    let value: String
    let trend: Double
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .bold()
            
            HStack {
                Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(abs(trend), specifier: "%.1f")%")
            }
            .font(.caption)
            .foregroundColor(trend >= 0 ? .red : .green)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ChartContainer: View {
    let title: String
    let chart: ChartType
    let data: [ChartDataPoint]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            
            Chart {
                ForEach(data) { point in
                    switch chart {
                    case .timeline:
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                    case .bar:
                        BarMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                    case .area:
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct DetailSection: View {
    let title: String
    let items: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            ForEach(items, id: \.0) { item in
                HStack {
                    Text(item.0)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(item.1)
                        .bold()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Enums

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
    
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        }
    }
}

enum MetricType: String, CaseIterable, Identifiable {
    case storage = "Storage"
    case cost = "Cost"
    case transfer = "Transfer"
    case snapshots = "Snapshots"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
}

enum ChartType: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case bar = "Bar"
    case area = "Area"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
    
    var iconName: String {
        switch self {
        case .timeline: return "chart.xyaxis.line"
        case .bar: return "chart.bar.fill"
        case .area: return "chart.area.fill"
        }
    }
}

// MARK: - Preview

struct CloudAnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CloudAnalyticsView(repository: Repository.preview)
        }
    }
}
