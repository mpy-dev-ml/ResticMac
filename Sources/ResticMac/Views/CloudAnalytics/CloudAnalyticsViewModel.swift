import Foundation
import SwiftUI

@MainActor
class CloudAnalyticsViewModel: ObservableObject {
    private let repository: Repository
    private let cloudAnalytics: CloudAnalytics
    private let byteFormatter = ByteCountFormatter()
    private let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    
    @Published private(set) var analytics: CloudAnalytics.RepositoryAnalytics?
    @Published private(set) var forecast: [CloudAnalytics.ForecastPoint] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage: String?
    
    init(repository: Repository) {
        self.repository = repository
        self.cloudAnalytics = CloudAnalytics()
        self.byteFormatter.countStyle = .file
        self.byteFormatter.includesUnit = true
    }
    
    func loadAnalytics() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await cloudAnalytics.updateAnalytics(for: repository)
            analytics = try await cloudAnalytics.getAnalytics(for: repository)
            forecast = try await cloudAnalytics.getStorageForecast(for: repository)
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Formatted Values
    
    var formattedStorageUsed: String {
        guard let analytics = analytics else { return "N/A" }
        return byteFormatter.string(fromByteCount: analytics.storageMetrics.totalBytes)
    }
    
    var formattedCompressedSize: String {
        guard let analytics = analytics else { return "N/A" }
        return byteFormatter.string(fromByteCount: analytics.storageMetrics.compressedBytes)
    }
    
    var formattedDeduplicatedSize: String {
        guard let analytics = analytics else { return "N/A" }
        return byteFormatter.string(fromByteCount: analytics.storageMetrics.deduplicatedBytes)
    }
    
    var formattedUploadedBytes: String {
        guard let analytics = analytics else { return "N/A" }
        return byteFormatter.string(fromByteCount: analytics.transferMetrics.uploadedBytes)
    }
    
    var formattedDownloadedBytes: String {
        guard let analytics = analytics else { return "N/A" }
        return byteFormatter.string(fromByteCount: analytics.transferMetrics.downloadedBytes)
    }
    
    var formattedSuccessRate: String {
        guard let analytics = analytics else { return "N/A" }
        return String(format: "%.1f%%", analytics.transferMetrics.successRate * 100)
    }
    
    var formattedAverageSpeed: String {
        guard let analytics = analytics else { return "N/A" }
        return "\(byteFormatter.string(fromByteCount: Int64(analytics.transferMetrics.averageTransferSpeed)))/s"
    }
    
    var formattedStorageCost: String {
        guard let analytics = analytics else { return "N/A" }
        return currencyFormatter.string(from: NSNumber(value: analytics.monthlyStorageCost)) ?? "N/A"
    }
    
    var formattedTransferCost: String {
        guard let analytics = analytics else { return "N/A" }
        return currencyFormatter.string(from: NSNumber(value: analytics.monthlyTransferCost)) ?? "N/A"
    }
    
    var formattedTotalCost: String {
        guard let analytics = analytics else { return "N/A" }
        return currencyFormatter.string(from: NSNumber(value: analytics.totalMonthlyCost)) ?? "N/A"
    }
    
    var formattedMonthlyCost: String {
        guard let analytics = analytics else { return "N/A" }
        return currencyFormatter.string(from: NSNumber(value: analytics.totalMonthlyCost)) ?? "N/A"
    }
    
    var formattedBillingCycle: String {
        guard let analytics = analytics else { return "N/A" }
        let start = analytics.costMetrics.billingCycle.start
        let end = analytics.costMetrics.billingCycle.end
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return "\(dateFormatter.string(from: start)) - \(dateFormatter.string(from: end))"
    }
    
    var formattedAverageSnapshotSize: String {
        guard let analytics = analytics else { return "N/A" }
        return byteFormatter.string(fromByteCount: analytics.snapshotMetrics.averageSnapshotSize)
    }
    
    var formattedTransferRate: String {
        guard let analytics = analytics else { return "N/A" }
        return "\(byteFormatter.string(fromByteCount: Int64(analytics.transferMetrics.averageTransferSpeed)))/s"
    }
    
    // MARK: - Trends and Rates
    
    var storageGrowthRate: Double {
        guard let analytics = analytics else { return 0 }
        // Calculate month-over-month growth rate
        return 5.2 // Placeholder value
    }
    
    var costTrend: Double {
        guard let analytics = analytics else { return 0 }
        // Calculate month-over-month cost trend
        return 3.8 // Placeholder value
    }
    
    var transferTrend: Double {
        guard let analytics = analytics else { return 0 }
        // Calculate month-over-month transfer trend
        return -2.1 // Placeholder value
    }
    
    // MARK: - Chart Data
    
    func chartData(for metricType: MetricType, range: TimeRange) -> [ChartDataPoint] {
        guard let analytics = analytics else { return [] }
        
        switch metricType {
        case .storage:
            return storageChartData(range)
        case .cost:
            return costChartData(range)
        case .transfer:
            return transferChartData(range)
        case .snapshots:
            return snapshotChartData(range)
        }
    }
    
    private func storageChartData(_ range: TimeRange) -> [ChartDataPoint] {
        guard let analytics = analytics else { return [] }
        
        // Generate sample data points for storage
        let calendar = Calendar.current
        var points: [ChartDataPoint] = []
        let now = Date()
        
        for day in 0..<range.days {
            guard let date = calendar.date(byAdding: .day, value: -day, to: now) else { continue }
            let value = Double(analytics.storageMetrics.totalBytes) * (1 + Double(day) * 0.001)
            points.append(ChartDataPoint(date: date, value: value))
        }
        
        return points.reversed()
    }
    
    private func costChartData(_ range: TimeRange) -> [ChartDataPoint] {
        guard let analytics = analytics else { return [] }
        
        // Generate sample data points for cost
        return analytics.costMetrics.costHistory.map {
            ChartDataPoint(date: $0.date, value: $0.storageCost + $0.transferCost + $0.operationsCost)
        }
    }
    
    private func transferChartData(_ range: TimeRange) -> [ChartDataPoint] {
        guard let analytics = analytics else { return [] }
        
        // Generate sample data points for transfers
        return analytics.transferMetrics.transferHistory.map {
            ChartDataPoint(date: $0.timestamp, value: Double($0.bytesTransferred))
        }
    }
    
    private func snapshotChartData(_ range: TimeRange) -> [ChartDataPoint] {
        guard let analytics = analytics else { return [] }
        
        // Generate sample data points for snapshots
        return analytics.snapshotMetrics.snapshotHistory.map {
            ChartDataPoint(date: $0.timestamp, value: Double($0.size))
        }
    }
}

// MARK: - Chart Data Point

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
