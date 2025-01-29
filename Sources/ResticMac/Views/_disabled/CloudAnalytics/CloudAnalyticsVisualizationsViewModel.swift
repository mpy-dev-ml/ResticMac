import Foundation
import SwiftUI

@MainActor
final class CloudAnalyticsVisualizationsViewModel: ObservableObject {
    private let repository: Repository
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    private let optimizer: CloudAnalyticsOptimizer
    
    // MARK: - Published Properties
    
    @Published private(set) var totalStorage: Int64 = 0
    @Published private(set) var transferRate: Int64 = 0
    @Published private(set) var monthlyCost: Double = 0.0
    
    @Published private(set) var storageTrend: Double = 0.0
    @Published private(set) var transferTrend: Double = 0.0
    @Published private(set) var costTrend: Double = 0.0
    
    @Published private(set) var storageHistory: [TimeSeriesPoint<StorageMetrics>] = []
    @Published private(set) var storageDistribution: [StorageDistributionItem] = []
    @Published private(set) var compressionHistory: [CompressionDataPoint] = []
    
    @Published private(set) var cpuUsage: Double = 0.0
    @Published private(set) var memoryUsage: Double = 0.0
    @Published private(set) var diskUsage: Double = 0.0
    
    @Published private(set) var performanceHistory: [PerformanceMetrics] = []
    
    @Published private(set) var costHistory: [TimeSeriesPoint<CostMetrics>] = []
    @Published private(set) var costBreakdown: [CostBreakdownItem] = []
    @Published private(set) var costProjection: [CostProjectionPoint] = []
    
    @Published private(set) var insights: [AnalyticsInsight] = []
    
    // MARK: - Initialization
    
    init(repository: Repository) {
        self.repository = repository
        self.persistence = CloudAnalyticsPersistence.shared
        self.monitor = CloudAnalyticsMonitor.shared
        self.optimizer = CloudAnalyticsOptimizer(
            persistence: persistence,
            monitor: monitor
        )
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        do {
            // Load storage data
            try await loadStorageData()
            
            // Load performance data
            try await loadPerformanceData()
            
            // Load cost data
            try await loadCostData()
            
            // Generate insights
            try await generateInsights()
            
        } catch {
            print("Failed to load analytics data: \(error)")
        }
    }
    
    private func loadStorageData() async throws {
        // Load storage history
        storageHistory = try await persistence.getStorageMetricsHistory(for: repository)
        
        // Calculate total storage and trend
        if let latest = storageHistory.last?.value {
            totalStorage = latest.totalBytes
            
            if let previousMonth = storageHistory.first(where: { 
                $0.timestamp <= Date().addingTimeInterval(-30 * 24 * 3600)
            })?.value {
                storageTrend = calculateTrend(
                    current: Double(latest.totalBytes),
                    previous: Double(previousMonth.totalBytes)
                )
            }
        }
        
        // Calculate storage distribution
        storageDistribution = try await calculateStorageDistribution()
        
        // Calculate compression history
        compressionHistory = try await calculateCompressionHistory()
    }
    
    private func loadPerformanceData() async throws {
        // Load performance history
        performanceHistory = try await persistence.getPerformanceHistory(for: repository)
        
        // Calculate current usage
        if let latest = performanceHistory.last {
            cpuUsage = latest.cpu.usage
            memoryUsage = Double(latest.memory.residentSize) / Double(latest.memory.peakResidentSize)
            diskUsage = min(Double(latest.disk.operations) / 100.0, 1.0)
        }
        
        // Calculate transfer rate and trend
        if let latestTransfer = await monitor.getCurrentTransferRate() {
            transferRate = latestTransfer
            
            if let previousMonth = await monitor.getAverageTransferRate(
                for: DateInterval(
                    start: Date().addingTimeInterval(-30 * 24 * 3600),
                    duration: 30 * 24 * 3600
                )
            ) {
                transferTrend = calculateTrend(
                    current: Double(latestTransfer),
                    previous: Double(previousMonth)
                )
            }
        }
    }
    
    private func loadCostData() async throws {
        // Load cost history
        costHistory = try await persistence.getCostMetricsHistory(for: repository)
        
        // Calculate monthly cost and trend
        if let latest = costHistory.last?.value {
            monthlyCost = latest.totalCost
            
            if let previousMonth = costHistory.first(where: {
                $0.timestamp <= Date().addingTimeInterval(-30 * 24 * 3600)
            })?.value {
                costTrend = calculateTrend(
                    current: latest.totalCost,
                    previous: previousMonth.totalCost
                )
            }
        }
        
        // Calculate cost breakdown
        costBreakdown = try await calculateCostBreakdown()
        
        // Generate cost projection
        costProjection = try await generateCostProjection()
    }
    
    // MARK: - Calculations
    
    private func calculateStorageDistribution() async throws -> [StorageDistributionItem] {
        guard let latest = storageHistory.last?.value else { return [] }
        
        return [
            StorageDistributionItem(
                category: "Total",
                size: latest.totalBytes
            ),
            StorageDistributionItem(
                category: "Compressed",
                size: latest.compressedBytes
            ),
            StorageDistributionItem(
                category: "Deduplicated",
                size: latest.deduplicatedBytes
            )
        ]
    }
    
    private func calculateCompressionHistory() async throws -> [CompressionDataPoint] {
        return storageHistory.map { point in
            CompressionDataPoint(
                timestamp: point.timestamp,
                ratio: Double(point.value.totalBytes) / Double(point.value.compressedBytes)
            )
        }
    }
    
    private func calculateCostBreakdown() async throws -> [CostBreakdownItem] {
        guard let latest = costHistory.last?.value else { return [] }
        
        let storageSize = Double(totalStorage)
        let storageCost = storageSize * latest.storageUnitCost
        
        let transferSize = Double(transferRate * 3600 * 24 * 30) // Monthly transfer
        let transferCost = transferSize * latest.transferUnitCost
        
        return [
            CostBreakdownItem(
                category: "Storage",
                cost: storageCost
            ),
            CostBreakdownItem(
                category: "Transfer",
                cost: transferCost
            ),
            CostBreakdownItem(
                category: "Other",
                cost: latest.totalCost - (storageCost + transferCost)
            )
        ]
    }
    
    private func generateCostProjection() async throws -> [CostProjectionPoint] {
        // Use last 3 months of data for projection
        let threeMonthsAgo = Date().addingTimeInterval(-90 * 24 * 3600)
        let recentCosts = costHistory.filter { $0.timestamp >= threeMonthsAgo }
        
        // Calculate trend
        let trend = calculateProjectionTrend(from: recentCosts)
        
        // Generate 6-month projection
        var projection: [CostProjectionPoint] = []
        let now = Date()
        
        for month in 0..<6 {
            let timestamp = now.addingTimeInterval(Double(month * 30 * 24 * 3600))
            let projectedCost = monthlyCost * (1 + trend * Double(month))
            
            projection.append(CostProjectionPoint(
                timestamp: timestamp,
                projectedCost: projectedCost,
                actualCost: month == 0 ? monthlyCost : nil
            ))
        }
        
        return projection
    }
    
    private func generateInsights() async throws {
        var newInsights: [AnalyticsInsight] = []
        
        // Storage insights
        if storageTrend > 0.2 {
            newInsights.append(AnalyticsInsight(
                title: "High Storage Growth",
                description: "Storage usage is growing rapidly at \(String(format: "%.1f%%", storageTrend * 100)) per month",
                systemImage: "arrow.up.circle.fill",
                recommendedAction: "Consider implementing retention policies"
            ))
        }
        
        // Performance insights
        if cpuUsage > 0.8 {
            newInsights.append(AnalyticsInsight(
                title: "High CPU Usage",
                description: "CPU utilisation is above 80%",
                systemImage: "cpu",
                recommendedAction: "Review and optimize backup schedules"
            ))
        }
        
        // Cost insights
        if costTrend > 0.15 {
            newInsights.append(AnalyticsInsight(
                title: "Rising Costs",
                description: "Monthly costs have increased by \(String(format: "%.1f%%", costTrend * 100))",
                systemImage: "dollarsign.circle.fill",
                recommendedAction: "Analyze cost breakdown for optimization opportunities"
            ))
        }
        
        insights = newInsights
    }
    
    // MARK: - Helper Methods
    
    private func calculateTrend(current: Double, previous: Double) -> Double {
        (current - previous) / previous
    }
    
    private func calculateProjectionTrend(
        from history: [TimeSeriesPoint<CostMetrics>]
    ) -> Double {
        guard history.count >= 2 else { return 0.0 }
        
        let costs = history.map { $0.value.totalCost }
        let averageChange = zip(costs, costs.dropFirst()).map { $1 - $0 }.reduce(0.0, +)
        return averageChange / Double(costs.count - 1) / costs[0]
    }
    
    // MARK: - Formatting
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

// MARK: - Supporting Types

struct StorageDistributionItem: Identifiable {
    let id = UUID()
    let category: String
    let size: Int64
}

struct CompressionDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let ratio: Double
}

struct CostBreakdownItem: Identifiable {
    let id = UUID()
    let category: String
    let cost: Double
}

struct CostProjectionPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let projectedCost: Double
    let actualCost: Double?
}

struct AnalyticsInsight: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let systemImage: String
    let recommendedAction: String?
}
