import SwiftUI

struct CloudAnalyticsDashboard: View {
    @StateObject private var viewModel: CloudAnalyticsDashboardViewModel
    @State private var selectedTimeRange: TimeRange = .month
    @State private var showingExport = false
    
    init(repository: Repository) {
        _viewModel = StateObject(wrappedValue: CloudAnalyticsDashboardViewModel(repository: repository))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Time Range Selector
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Storage Metrics Card
                MetricCard(title: "Storage Usage") {
                    StorageUsageChart(
                        data: viewModel.storageRecords,
                        timeRange: selectedTimeRange
                    )
                } footer: {
                    StorageMetricsFooter(metrics: viewModel.latestStorageMetrics)
                }
                
                // Transfer Metrics Card
                MetricCard(title: "Transfer Activity") {
                    TransferSpeedChart(
                        data: viewModel.transferRecords,
                        timeRange: selectedTimeRange
                    )
                } footer: {
                    TransferMetricsFooter(metrics: viewModel.latestTransferMetrics)
                }
                
                // Cost Analysis Card
                MetricCard(title: "Cost Analysis") {
                    CostAnalysisChart(
                        data: viewModel.costRecords,
                        timeRange: selectedTimeRange
                    )
                } footer: {
                    CostMetricsFooter(metrics: viewModel.latestCostMetrics)
                }
                
                // Snapshot Distribution Card
                MetricCard(title: "Snapshot Distribution") {
                    SnapshotDistributionChart(
                        data: viewModel.snapshotRecords,
                        timeRange: selectedTimeRange
                    )
                } footer: {
                    SnapshotMetricsFooter(metrics: viewModel.latestSnapshotMetrics)
                }
                
                // Trend Analysis Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    TrendCard(
                        title: "Storage Trend",
                        data: viewModel.storageRecords.map { Double($0.metrics.totalBytes) },
                        timestamps: viewModel.storageRecords.map(\.timestamp),
                        analysis: viewModel.storageTrends,
                        timeRange: selectedTimeRange,
                        valueFormatter: { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
                    )
                    
                    TrendCard(
                        title: "Transfer Trend",
                        data: viewModel.transferRecords.map { Double($0.metrics.totalTransferredBytes) },
                        timestamps: viewModel.transferRecords.map(\.timestamp),
                        analysis: viewModel.transferTrends,
                        timeRange: selectedTimeRange,
                        valueFormatter: { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) + "/s" }
                    )
                    
                    TrendCard(
                        title: "Cost Trend",
                        data: viewModel.costRecords.map(\.metrics.totalCost),
                        timestamps: viewModel.costRecords.map(\.timestamp),
                        analysis: viewModel.costTrends,
                        timeRange: selectedTimeRange,
                        valueFormatter: { NumberFormatter.currency.string(from: NSNumber(value: $0)) ?? "" }
                    )
                    
                    TrendCard(
                        title: "Snapshot Trend",
                        data: viewModel.snapshotRecords.map { Double($0.metrics.totalSnapshots) },
                        timestamps: viewModel.snapshotRecords.map(\.timestamp),
                        analysis: viewModel.snapshotTrends,
                        timeRange: selectedTimeRange,
                        valueFormatter: { String(Int($0)) }
                    )
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Analytics Dashboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingExport = true
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    
                    Button {
                        Task {
                            await viewModel.refreshData(timeRange: selectedTimeRange)
                        }
                    } label: {
                        Label("Refresh Data", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingExport) {
            CloudAnalyticsExportView(repository: viewModel.repository)
        }
        .onChange(of: selectedTimeRange) { newRange in
            Task {
                await viewModel.refreshData(timeRange: newRange)
            }
        }
        .task {
            await viewModel.refreshData(timeRange: selectedTimeRange)
        }
    }
}

// MARK: - Supporting Views

struct MetricCard<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            content()
                .frame(height: 200)
            
            Divider()
            
            footer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct TrendCard: View {
    let title: String
    let data: [Double]
    let timestamps: [Date]
    let analysis: TrendAnalysis
    let timeRange: TimeRange
    let valueFormatter: (Double) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            TrendChart(
                data: data,
                timestamps: timestamps,
                analysis: analysis,
                timeRange: timeRange,
                valueFormatter: valueFormatter
            )
            .frame(height: 150)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct StorageMetricsFooter: View {
    let metrics: StorageMetrics?
    
    var body: some View {
        if let metrics = metrics {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                GridRow {
                    Text("Total Size")
                    Text(ByteCountFormatter.string(fromByteCount: metrics.totalBytes, countStyle: .file))
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Compression Ratio")
                    Text(String(format: "%.1f%%", metrics.compressionRatio * 100))
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Deduplication Ratio")
                    Text(String(format: "%.1f%%", metrics.deduplicationRatio * 100))
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
        } else {
            Text("No data available")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct TransferMetricsFooter: View {
    let metrics: TransferMetrics?
    
    var body: some View {
        if let metrics = metrics {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                GridRow {
                    Text("Total Transferred")
                    Text(ByteCountFormatter.string(fromByteCount: metrics.totalTransferredBytes, countStyle: .file))
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Average Speed")
                    Text(ByteCountFormatter.string(fromByteCount: Int64(metrics.averageTransferSpeed), countStyle: .memory) + "/s")
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Success Rate")
                    Text(String(format: "%.1f%%", metrics.successRate * 100))
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
        } else {
            Text("No data available")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct CostMetricsFooter: View {
    let metrics: CostMetrics?
    
    var body: some View {
        if let metrics = metrics {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                GridRow {
                    Text("Total Cost")
                    Text(NumberFormatter.currency.string(from: NSNumber(value: metrics.totalCost)) ?? "")
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Storage Cost")
                    Text(NumberFormatter.currency.string(from: NSNumber(value: metrics.storageUnitCost)) ?? "")
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Transfer Cost")
                    Text(NumberFormatter.currency.string(from: NSNumber(value: metrics.transferUnitCost)) ?? "")
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
        } else {
            Text("No data available")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SnapshotMetricsFooter: View {
    let metrics: SnapshotMetrics?
    
    var body: some View {
        if let metrics = metrics {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                GridRow {
                    Text("Total Snapshots")
                    Text("\(metrics.totalSnapshots)")
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Average Size")
                    Text(ByteCountFormatter.string(fromByteCount: metrics.averageSnapshotSize, countStyle: .file))
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Retention Period")
                    Text("\(metrics.retentionDays) days")
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
        } else {
            Text("No data available")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

@MainActor
class CloudAnalyticsDashboardViewModel: ObservableObject {
    let repository: Repository
    private let analytics: CloudAnalytics
    
    @Published private(set) var storageRecords: [StorageRecord] = []
    @Published private(set) var transferRecords: [TransferRecord] = []
    @Published private(set) var costRecords: [CostRecord] = []
    @Published private(set) var snapshotRecords: [SnapshotRecord] = []
    
    @Published private(set) var storageTrends: TrendAnalysis = TrendAnalysis(changeRate: 0, trend: .stable, confidence: 0, seasonality: nil)
    @Published private(set) var transferTrends: TrendAnalysis = TrendAnalysis(changeRate: 0, trend: .stable, confidence: 0, seasonality: nil)
    @Published private(set) var costTrends: TrendAnalysis = TrendAnalysis(changeRate: 0, trend: .stable, confidence: 0, seasonality: nil)
    @Published private(set) var snapshotTrends: TrendAnalysis = TrendAnalysis(changeRate: 0, trend: .stable, confidence: 0, seasonality: nil)
    
    var latestStorageMetrics: StorageMetrics? {
        storageRecords.last?.metrics
    }
    
    var latestTransferMetrics: TransferMetrics? {
        transferRecords.last?.metrics
    }
    
    var latestCostMetrics: CostMetrics? {
        costRecords.last?.metrics
    }
    
    var latestSnapshotMetrics: SnapshotMetrics? {
        snapshotRecords.last?.metrics
    }
    
    init(repository: Repository) {
        self.repository = repository
        self.analytics = CloudAnalytics()
    }
    
    func refreshData(timeRange: TimeRange) async {
        do {
            let persistence = CloudAnalyticsPersistence()
            
            // Load metrics
            async let storageMetrics = persistence.loadStorageMetrics(for: repository, timeRange: timeRange)
            async let transferMetrics = persistence.loadTransferMetrics(for: repository, timeRange: timeRange)
            async let costMetrics = persistence.loadCostMetrics(for: repository, timeRange: timeRange)
            async let snapshotMetrics = persistence.loadSnapshotMetrics(for: repository, timeRange: timeRange)
            
            // Load trends
            async let storageTrend = analytics.analyseStorageTrends(for: repository, timeRange: timeRange)
            async let transferTrend = analytics.analyseTransferTrends(for: repository, timeRange: timeRange)
            async let costTrend = analytics.analyseCostTrends(for: repository, timeRange: timeRange)
            async let snapshotTrend = analytics.analyseSnapshotTrends(for: repository, timeRange: timeRange)
            
            // Update UI
            self.storageRecords = try await storageMetrics
            self.transferRecords = try await transferMetrics
            self.costRecords = try await costMetrics
            self.snapshotRecords = try await snapshotMetrics
            
            self.storageTrends = try await storageTrend
            self.transferTrends = try await transferTrend
            self.costTrends = try await costTrend
            self.snapshotTrends = try await snapshotTrend
            
        } catch {
            print("Error refreshing analytics data: \(error)")
        }
    }
}
