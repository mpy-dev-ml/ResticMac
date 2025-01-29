import SwiftUI

struct CloudAnalyticsInsights: View {
    @StateObject private var viewModel: CloudAnalyticsInsightsViewModel
    @State private var selectedInsightType: InsightType = .storage
    @State private var showingDetails = false
    @State private var selectedInsight: Insight?
    
    init(repository: Repository) {
        _viewModel = StateObject(wrappedValue: CloudAnalyticsInsightsViewModel(repository: repository))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Insight Type Selector
                Picker("Insight Type", selection: $selectedInsightType) {
                    ForEach(InsightType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Key Metrics Summary
                MetricsSummaryView(metrics: viewModel.currentMetrics)
                    .padding(.horizontal)
                
                // Insights List
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.filteredInsights) { insight in
                        InsightCard(insight: insight) {
                            selectedInsight = insight
                            showingDetails = true
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Analytics Insights")
        .sheet(isPresented: $showingDetails) {
            if let insight = selectedInsight {
                InsightDetailsView(insight: insight, repository: viewModel.repository)
            }
        }
        .onChange(of: selectedInsightType) { _ in
            Task {
                await viewModel.refreshInsights()
            }
        }
        .task {
            await viewModel.refreshInsights()
        }
    }
}

struct MetricsSummaryView: View {
    let metrics: KeyMetrics
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            MetricTile(
                title: "Storage Efficiency",
                value: String(format: "%.1f%%", metrics.storageEfficiency * 100),
                trend: metrics.storageEfficiencyTrend,
                icon: "externaldrive"
            )
            
            MetricTile(
                title: "Cost per GB",
                value: NumberFormatter.currency.string(from: NSNumber(value: metrics.costPerGB)) ?? "",
                trend: metrics.costTrend,
                icon: "dollarsign.circle"
            )
            
            MetricTile(
                title: "Transfer Speed",
                value: ByteCountFormatter.string(fromByteCount: Int64(metrics.averageSpeed), countStyle: .memory) + "/s",
                trend: metrics.speedTrend,
                icon: "arrow.up.arrow.down"
            )
            
            MetricTile(
                title: "Backup Health",
                value: String(format: "%.1f%%", metrics.backupHealth * 100),
                trend: metrics.healthTrend,
                icon: "heart"
            )
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let trend: TrendDirection
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text(value)
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Image(systemName: trend.iconName)
                    .foregroundColor(trend.color)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct InsightCard: View {
    let insight: Insight
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: insight.type.iconName)
                        .foregroundColor(insight.severity.color)
                    
                    Text(insight.title)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(insight.timestamp.formatted(.relative))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(insight.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if !insight.recommendations.isEmpty {
                    HStack {
                        Image(systemName: "lightbulb")
                        Text("\(insight.recommendations.count) recommendations")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct InsightDetailsView: View {
    let insight: Insight
    let repository: Repository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: InsightDetailsViewModel
    
    init(insight: Insight, repository: Repository) {
        self.insight = insight
        self.repository = repository
        _viewModel = StateObject(wrappedValue: InsightDetailsViewModel(insight: insight, repository: repository))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: insight.type.iconName)
                            .foregroundColor(insight.severity.color)
                            .font(.title)
                        
                        VStack(alignment: .leading) {
                            Text(insight.title)
                                .font(.title2)
                                .bold()
                            
                            Text(insight.timestamp.formatted(.dateTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Analysis")
                            .font(.headline)
                        
                        Text(insight.details)
                            .font(.body)
                        
                        if let chart = viewModel.insightChart {
                            chart
                                .frame(height: 200)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Recommendations
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recommendations")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(insight.recommendations) { recommendation in
                            RecommendationCard(
                                recommendation: recommendation,
                                isImplementing: viewModel.implementingRecommendation == recommendation.id,
                                onImplement: {
                                    Task {
                                        await viewModel.implementRecommendation(recommendation)
                                    }
                                }
                            )
                        }
                    }
                    
                    if let error = viewModel.error {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RecommendationCard: View {
    let recommendation: Recommendation
    let isImplementing: Bool
    let onImplement: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: recommendation.type.iconName)
                    .foregroundColor(recommendation.type.color)
                
                Text(recommendation.title)
                    .font(.headline)
            }
            
            Text(recommendation.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if recommendation.isAutomatable {
                Button {
                    onImplement()
                } label: {
                    if isImplementing {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Implement")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImplementing)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

@MainActor
class CloudAnalyticsInsightsViewModel: ObservableObject {
    let repository: Repository
    private let analytics: CloudAnalytics
    
    @Published private(set) var insights: [Insight] = []
    @Published private(set) var currentMetrics = KeyMetrics()
    @Published var selectedType: InsightType = .storage
    
    var filteredInsights: [Insight] {
        insights.filter { $0.type == selectedType }
    }
    
    init(repository: Repository) {
        self.repository = repository
        self.analytics = CloudAnalytics()
    }
    
    func refreshInsights() async {
        // Implement insight generation logic
    }
}

@MainActor
class InsightDetailsViewModel: ObservableObject {
    let insight: Insight
    let repository: Repository
    
    @Published private(set) var insightChart: (any View)?
    @Published private(set) var implementingRecommendation: UUID?
    @Published var error: String?
    
    init(insight: Insight, repository: Repository) {
        self.insight = insight
        self.repository = repository
        generateChart()
    }
    
    private func generateChart() {
        // Implement chart generation logic based on insight type
    }
    
    func implementRecommendation(_ recommendation: Recommendation) async {
        // Implement recommendation application logic
    }
}

// MARK: - Supporting Types

struct KeyMetrics {
    var storageEfficiency: Double = 0
    var costPerGB: Double = 0
    var averageSpeed: Double = 0
    var backupHealth: Double = 0
    
    var storageEfficiencyTrend: TrendDirection = .stable
    var costTrend: TrendDirection = .stable
    var speedTrend: TrendDirection = .stable
    var healthTrend: TrendDirection = .stable
}

enum InsightType: String, CaseIterable, Identifiable {
    case storage = "Storage"
    case cost = "Cost"
    case performance = "Performance"
    case security = "Security"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
    
    var iconName: String {
        switch self {
        case .storage: return "externaldrive"
        case .cost: return "dollarsign.circle"
        case .performance: return "gauge"
        case .security: return "lock.shield"
        }
    }
}

enum InsightSeverity {
    case info
    case warning
    case critical
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

struct Insight: Identifiable {
    let id: UUID
    let type: InsightType
    let severity: InsightSeverity
    let timestamp: Date
    let title: String
    let summary: String
    let details: String
    let recommendations: [Recommendation]
}

struct Recommendation: Identifiable {
    let id: UUID
    let type: RecommendationType
    let title: String
    let description: String
    let isAutomatable: Bool
    let action: (() async throws -> Void)?
}

enum RecommendationType {
    case optimization
    case security
    case cost
    case maintenance
    
    var iconName: String {
        switch self {
        case .optimization: return "bolt"
        case .security: return "lock.shield"
        case .cost: return "dollarsign.circle"
        case .maintenance: return "wrench"
        }
    }
    
    var color: Color {
        switch self {
        case .optimization: return .blue
        case .security: return .red
        case .cost: return .green
        case .maintenance: return .orange
        }
    }
}

extension TrendDirection {
    var iconName: String {
        switch self {
        case .increasing: return "arrow.up"
        case .decreasing: return "arrow.down"
        case .stable: return "arrow.right"
        }
    }
    
    var color: Color {
        switch self {
        case .increasing: return .green
        case .decreasing: return .red
        case .stable: return .blue
        }
    }
}
