import Foundation
import OSLog
import SwiftUI

actor CloudAnalyticsReportGenerator {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsReportGenerator")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    private let optimizer: CloudAnalyticsOptimizer
    
    init(
        persistence: CloudAnalyticsPersistence,
        monitor: CloudAnalyticsMonitor,
        optimizer: CloudAnalyticsOptimizer
    ) {
        self.persistence = persistence
        self.monitor = monitor
        self.optimizer = optimizer
    }
    
    // MARK: - Report Generation
    
    func generateReport(
        for repository: Repository,
        type: ReportType,
        timeRange: DateInterval? = nil,
        options: ReportOptions = ReportOptions()
    ) async throws -> AnalyticsReport {
        let tracker = await monitor.trackOperation("generate_report")
        defer { tracker.stop() }
        
        do {
            // Gather report data
            let data = try await gatherReportData(
                for: repository,
                type: type,
                timeRange: timeRange
            )
            
            // Generate sections
            let sections = try await generateReportSections(
                from: data,
                type: type,
                options: options
            )
            
            // Generate insights
            let insights = try await generateReportInsights(
                from: data,
                type: type
            )
            
            // Generate recommendations
            let recommendations = try await generateRecommendations(
                from: data,
                insights: insights
            )
            
            // Create report
            let report = AnalyticsReport(
                repository: repository,
                type: type,
                timeRange: timeRange,
                sections: sections,
                insights: insights,
                recommendations: recommendations,
                generatedAt: Date()
            )
            
            // Save report
            try await persistence.saveReport(report)
            
            logger.info("Generated \(type.rawValue) report for repository: \(repository.id)")
            return report
            
        } catch {
            logger.error("Report generation failed: \(error.localizedDescription)")
            throw ReportError.generationFailed(error: error)
        }
    }
    
    // MARK: - Data Gathering
    
    private func gatherReportData(
        for repository: Repository,
        type: ReportType,
        timeRange: DateInterval?
    ) async throws -> ReportData {
        var data = ReportData()
        
        // Storage metrics
        data.storageMetrics = try await persistence.getStorageMetricsHistory(
            for: repository,
            timeRange: timeRange
        )
        
        // Transfer metrics
        data.transferMetrics = try await persistence.getTransferMetricsHistory(
            for: repository,
            timeRange: timeRange
        )
        
        // Cost metrics
        data.costMetrics = try await persistence.getCostMetricsHistory(
            for: repository,
            timeRange: timeRange
        )
        
        // Performance metrics
        data.performanceMetrics = try await persistence.getPerformanceHistory(
            for: repository,
            timeRange: timeRange
        )
        
        // Error records
        data.errorRecords = try await persistence.getErrorHistory(
            for: repository,
            timeRange: timeRange
        )
        
        // Optimization records
        data.optimizationRecords = try await persistence.getOptimizationHistory(
            for: repository,
            timeRange: timeRange
        )
        
        return data
    }
    
    // MARK: - Section Generation
    
    private func generateReportSections(
        from data: ReportData,
        type: ReportType,
        options: ReportOptions
    ) async throws -> [ReportSection] {
        var sections: [ReportSection] = []
        
        switch type {
        case .executive:
            sections.append(contentsOf: try await generateExecutiveSections(from: data))
        case .technical:
            sections.append(contentsOf: try await generateTechnicalSections(from: data))
        case .cost:
            sections.append(contentsOf: try await generateCostSections(from: data))
        case .performance:
            sections.append(contentsOf: try await generatePerformanceSections(from: data))
        case .custom:
            sections.append(contentsOf: try await generateCustomSections(from: data, options: options))
        }
        
        return sections
    }
    
    private func generateExecutiveSections(
        from data: ReportData
    ) async throws -> [ReportSection] {
        var sections: [ReportSection] = []
        
        // Overview section
        sections.append(ReportSection(
            title: "Executive Summary",
            content: try await generateExecutiveSummary(from: data),
            charts: [
                try await generateStorageChart(from: data.storageMetrics),
                try await generateCostChart(from: data.costMetrics)
            ]
        ))
        
        // Key metrics section
        sections.append(ReportSection(
            title: "Key Metrics",
            content: try await generateKeyMetrics(from: data),
            charts: [
                try await generateMetricsChart(from: data)
            ]
        ))
        
        // Cost analysis section
        sections.append(ReportSection(
            title: "Cost Analysis",
            content: try await generateCostAnalysis(from: data),
            charts: [
                try await generateCostBreakdownChart(from: data.costMetrics)
            ]
        ))
        
        return sections
    }
    
    private func generateTechnicalSections(
        from data: ReportData
    ) async throws -> [ReportSection] {
        var sections: [ReportSection] = []
        
        // Performance section
        sections.append(ReportSection(
            title: "Performance Analysis",
            content: try await generatePerformanceAnalysis(from: data),
            charts: [
                try await generatePerformanceChart(from: data.performanceMetrics)
            ]
        ))
        
        // Error analysis section
        sections.append(ReportSection(
            title: "Error Analysis",
            content: try await generateErrorAnalysis(from: data),
            charts: [
                try await generateErrorChart(from: data.errorRecords)
            ]
        ))
        
        // Optimization section
        sections.append(ReportSection(
            title: "Optimizations",
            content: try await generateOptimizationAnalysis(from: data),
            charts: [
                try await generateOptimizationChart(from: data.optimizationRecords)
            ]
        ))
        
        return sections
    }
    
    private func generateCostSections(
        from data: ReportData
    ) async throws -> [ReportSection] {
        var sections: [ReportSection] = []
        
        // Cost trends section
        sections.append(ReportSection(
            title: "Cost Trends",
            content: try await generateCostTrends(from: data),
            charts: [
                try await generateCostTrendChart(from: data.costMetrics)
            ]
        ))
        
        // Cost projection section
        sections.append(ReportSection(
            title: "Cost Projections",
            content: try await generateCostProjections(from: data),
            charts: [
                try await generateCostProjectionChart(from: data.costMetrics)
            ]
        ))
        
        // Cost optimization section
        sections.append(ReportSection(
            title: "Cost Optimizations",
            content: try await generateCostOptimizations(from: data),
            charts: [
                try await generateCostOptimizationChart(from: data)
            ]
        ))
        
        return sections
    }
    
    private func generatePerformanceSections(
        from data: ReportData
    ) async throws -> [ReportSection] {
        var sections: [ReportSection] = []
        
        // Resource utilization section
        sections.append(ReportSection(
            title: "Resource Utilisation",
            content: try await generateResourceUtilization(from: data),
            charts: [
                try await generateResourceChart(from: data.performanceMetrics)
            ]
        ))
        
        // Bottleneck analysis section
        sections.append(ReportSection(
            title: "Bottleneck Analysis",
            content: try await generateBottleneckAnalysis(from: data),
            charts: [
                try await generateBottleneckChart(from: data.performanceMetrics)
            ]
        ))
        
        // Performance optimization section
        sections.append(ReportSection(
            title: "Performance Optimisations",
            content: try await generatePerformanceOptimizations(from: data),
            charts: [
                try await generatePerformanceOptimizationChart(from: data)
            ]
        ))
        
        return sections
    }
    
    // MARK: - Insight Generation
    
    private func generateReportInsights(
        from data: ReportData,
        type: ReportType
    ) async throws -> [ReportInsight] {
        var insights: [ReportInsight] = []
        
        // Storage insights
        insights.append(contentsOf: try await generateStorageInsights(from: data))
        
        // Performance insights
        insights.append(contentsOf: try await generatePerformanceInsights(from: data))
        
        // Cost insights
        insights.append(contentsOf: try await generateCostInsights(from: data))
        
        // Filter insights based on report type
        return filterInsights(insights, for: type)
    }
    
    private func generateStorageInsights(
        from data: ReportData
    ) async throws -> [ReportInsight] {
        var insights: [ReportInsight] = []
        
        // Analyze storage growth
        if let growth = calculateStorageGrowth(from: data.storageMetrics),
           growth > 0.2 { // 20% growth
            insights.append(ReportInsight(
                title: "High Storage Growth",
                description: "Storage usage is growing at \(String(format: "%.1f%%", growth * 100)) per month",
                severity: .warning,
                category: .storage
            ))
        }
        
        // Analyze compression efficiency
        if let efficiency = calculateCompressionEfficiency(from: data.storageMetrics),
           efficiency < 0.5 { // Less than 50% compression
            insights.append(ReportInsight(
                title: "Low Compression Efficiency",
                description: "Current compression ratio is \(String(format: "%.1f%%", efficiency * 100))",
                severity: .info,
                category: .storage
            ))
        }
        
        return insights
    }
    
    private func generatePerformanceInsights(
        from data: ReportData
    ) async throws -> [ReportInsight] {
        var insights: [ReportInsight] = []
        
        // Analyze CPU usage
        if let cpuUsage = calculateAverageCPUUsage(from: data.performanceMetrics),
           cpuUsage > 0.8 { // 80% CPU usage
            insights.append(ReportInsight(
                title: "High CPU Utilisation",
                description: "Average CPU usage is \(String(format: "%.1f%%", cpuUsage * 100))",
                severity: .warning,
                category: .performance
            ))
        }
        
        // Analyze memory usage
        if let memoryUsage = calculatePeakMemoryUsage(from: data.performanceMetrics),
           memoryUsage > 0.9 { // 90% memory usage
            insights.append(ReportInsight(
                title: "High Memory Usage",
                description: "Peak memory usage is \(String(format: "%.1f%%", memoryUsage * 100))",
                severity: .critical,
                category: .performance
            ))
        }
        
        return insights
    }
    
    private func generateCostInsights(
        from data: ReportData
    ) async throws -> [ReportInsight] {
        var insights: [ReportInsight] = []
        
        // Analyze cost trend
        if let trend = calculateCostTrend(from: data.costMetrics),
           trend > 0.15 { // 15% cost increase
            insights.append(ReportInsight(
                title: "Rising Costs",
                description: "Monthly costs have increased by \(String(format: "%.1f%%", trend * 100))",
                severity: .warning,
                category: .cost
            ))
        }
        
        // Analyze cost efficiency
        if let efficiency = calculateCostEfficiency(from: data),
           efficiency < 0.7 { // Less than 70% efficient
            insights.append(ReportInsight(
                title: "Low Cost Efficiency",
                description: "Current cost efficiency is \(String(format: "%.1f%%", efficiency * 100))",
                severity: .info,
                category: .cost
            ))
        }
        
        return insights
    }
    
    // MARK: - Recommendation Generation
    
    private func generateRecommendations(
        from data: ReportData,
        insights: [ReportInsight]
    ) async throws -> [ReportRecommendation] {
        var recommendations: [ReportRecommendation] = []
        
        // Generate storage recommendations
        recommendations.append(contentsOf: try await generateStorageRecommendations(
            from: data,
            insights: insights.filter { $0.category == .storage }
        ))
        
        // Generate performance recommendations
        recommendations.append(contentsOf: try await generatePerformanceRecommendations(
            from: data,
            insights: insights.filter { $0.category == .performance }
        ))
        
        // Generate cost recommendations
        recommendations.append(contentsOf: try await generateCostRecommendations(
            from: data,
            insights: insights.filter { $0.category == .cost }
        ))
        
        return recommendations
    }
    
    // MARK: - Helper Methods
    
    private func filterInsights(
        _ insights: [ReportInsight],
        for type: ReportType
    ) -> [ReportInsight] {
        switch type {
        case .executive:
            return insights.filter { $0.severity >= .warning }
        case .technical:
            return insights
        case .cost:
            return insights.filter { $0.category == .cost }
        case .performance:
            return insights.filter { $0.category == .performance }
        case .custom:
            return insights
        }
    }
}

// MARK: - Supporting Types

enum ReportType: String {
    case executive
    case technical
    case cost
    case performance
    case custom
}

struct ReportOptions {
    var includeSections: Set<String> = []
    var excludeSections: Set<String> = []
    var customMetrics: [String: Any] = [:]
    var chartOptions: ChartOptions = ChartOptions()
    
    struct ChartOptions {
        var style: ChartStyle = .automatic
        var colorScheme: ColorScheme = .automatic
        var interactive: Bool = true
    }
}

struct AnalyticsReport: Codable {
    let repository: Repository
    let type: ReportType
    let timeRange: DateInterval?
    let sections: [ReportSection]
    let insights: [ReportInsight]
    let recommendations: [ReportRecommendation]
    let generatedAt: Date
}

struct ReportSection: Codable {
    let title: String
    let content: String
    let charts: [ReportChart]
}

struct ReportChart: Codable {
    let type: ChartType
    let data: [String: Any]
    let options: ChartOptions
    
    enum ChartType {
        case line
        case bar
        case pie
        case area
        case scatter
    }
    
    struct ChartOptions: Codable {
        let title: String
        let xAxis: String
        let yAxis: String
        let legend: Bool
        let animation: Bool
    }
    
    enum CodingKeys: String, CodingKey {
        case type, options
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(options, forKey: .options)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(ChartType.self, forKey: .type)
        options = try container.decode(ChartOptions.self, forKey: .options)
        data = [:] // Initialize empty as we can't decode [String: Any]
    }
}

struct ReportInsight: Codable {
    let title: String
    let description: String
    let severity: InsightSeverity
    let category: InsightCategory
    
    enum InsightSeverity: Int, Codable {
        case info = 0
        case warning = 1
        case critical = 2
    }
    
    enum InsightCategory: String, Codable {
        case storage
        case performance
        case cost
    }
}

struct ReportRecommendation: Codable {
    let title: String
    let description: String
    let impact: Impact
    let effort: Effort
    let priority: Priority
    
    enum Impact: Int, Codable {
        case low = 1
        case medium = 2
        case high = 3
    }
    
    enum Effort: Int, Codable {
        case low = 1
        case medium = 2
        case high = 3
    }
    
    enum Priority: Int, Codable {
        case low = 1
        case medium = 2
        case high = 3
    }
}

struct ReportData {
    var storageMetrics: [TimeSeriesPoint<StorageMetrics>] = []
    var transferMetrics: [TimeSeriesPoint<TransferMetrics>] = []
    var costMetrics: [TimeSeriesPoint<CostMetrics>] = []
    var performanceMetrics: [PerformanceMetrics] = []
    var errorRecords: [ErrorRecord] = []
    var optimizationRecords: [OptimizationRecord] = []
}

enum ReportError: Error {
    case generationFailed(error: Error)
    case invalidData
    case missingMetrics
}
