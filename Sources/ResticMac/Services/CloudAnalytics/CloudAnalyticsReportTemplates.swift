import Foundation
import SwiftUI
import OSLog

actor CloudAnalyticsReportTemplates {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsReportTemplates")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    private let chartCustomization: CloudAnalyticsChartCustomization
    
    init(
        persistence: CloudAnalyticsPersistence,
        monitor: CloudAnalyticsMonitor,
        chartCustomization: CloudAnalyticsChartCustomization
    ) {
        self.persistence = persistence
        self.monitor = monitor
        self.chartCustomization = chartCustomization
    }
    
    // MARK: - Template Management
    
    func createTemplate(
        _ template: ReportTemplate
    ) async throws {
        let tracker = await monitor.trackOperation("create_template")
        defer { tracker.stop() }
        
        do {
            try validateTemplate(template)
            try await persistence.saveTemplate(template)
            logger.info("Created template: \(template.name)")
        } catch {
            logger.error("Failed to create template: \(error.localizedDescription)")
            throw TemplateError.creationFailed(error: error)
        }
    }
    
    func updateTemplate(
        _ template: ReportTemplate
    ) async throws {
        let tracker = await monitor.trackOperation("update_template")
        defer { tracker.stop() }
        
        do {
            try validateTemplate(template)
            try await persistence.updateTemplate(template)
            logger.info("Updated template: \(template.name)")
        } catch {
            logger.error("Failed to update template: \(error.localizedDescription)")
            throw TemplateError.updateFailed(error: error)
        }
    }
    
    func deleteTemplate(
        withId id: UUID
    ) async throws {
        let tracker = await monitor.trackOperation("delete_template")
        defer { tracker.stop() }
        
        do {
            try await persistence.deleteTemplate(id: id)
            logger.info("Deleted template: \(id)")
        } catch {
            logger.error("Failed to delete template: \(error.localizedDescription)")
            throw TemplateError.deletionFailed(error: error)
        }
    }
    
    // MARK: - Template Application
    
    func applyTemplate(
        _ template: ReportTemplate,
        to report: AnalyticsReport
    ) async throws -> AnalyticsReport {
        let tracker = await monitor.trackOperation("apply_template")
        defer { tracker.stop() }
        
        do {
            // Apply layout
            var modifiedReport = report
            modifiedReport.layout = template.layout
            
            // Apply section templates
            modifiedReport.sections = try await applySectionTemplates(
                template.sectionTemplates,
                to: report
            )
            
            // Apply chart templates
            modifiedReport = try await applyChartTemplates(
                template.chartTemplates,
                to: modifiedReport
            )
            
            // Apply styling
            modifiedReport = try await applyStyle(
                template.style,
                to: modifiedReport
            )
            
            return modifiedReport
            
        } catch {
            logger.error("Failed to apply template: \(error.localizedDescription)")
            throw TemplateError.applicationFailed(error: error)
        }
    }
    
    // MARK: - Template Validation
    
    private func validateTemplate(_ template: ReportTemplate) throws {
        // Validate basic properties
        guard !template.name.isEmpty else {
            throw TemplateError.validation("Template name cannot be empty")
        }
        
        // Validate sections
        guard !template.sectionTemplates.isEmpty else {
            throw TemplateError.validation("Template must have at least one section")
        }
        
        // Validate layout
        try validateLayout(template.layout)
        
        // Validate chart templates
        try validateChartTemplates(template.chartTemplates)
    }
    
    // MARK: - Private Methods
    
    private func applySectionTemplates(
        _ templates: [SectionTemplate],
        to report: AnalyticsReport
    ) async throws -> [ReportSection] {
        var sections: [ReportSection] = []
        
        for template in templates {
            // Create section from template
            let section = try await createSection(
                from: template,
                using: report
            )
            sections.append(section)
        }
        
        return sections
    }
    
    private func createSection(
        from template: SectionTemplate,
        using report: AnalyticsReport
    ) async throws -> ReportSection {
        // Generate content based on template type
        let content = try await generateContent(
            for: template,
            using: report
        )
        
        // Create charts if specified
        let charts = try await generateCharts(
            for: template,
            using: report
        )
        
        return ReportSection(
            title: template.title,
            content: content,
            charts: charts,
            style: template.style
        )
    }
    
    private func generateContent(
        for template: SectionTemplate,
        using report: AnalyticsReport
    ) async throws -> String {
        switch template.type {
        case .overview:
            return try await generateOverview(using: report)
        case .performance:
            return try await generatePerformanceAnalysis(using: report)
        case .storage:
            return try await generateStorageAnalysis(using: report)
        case .cost:
            return try await generateCostAnalysis(using: report)
        case .custom(let generator):
            return try await generator(report)
        }
    }
    
    private func generateCharts(
        for template: SectionTemplate,
        using report: AnalyticsReport
    ) async throws -> [ReportChart] {
        var charts: [ReportChart] = []
        
        for chartTemplate in template.chartTemplates {
            // Get data for chart
            let data = try await extractChartData(
                for: chartTemplate,
                from: report
            )
            
            // Apply chart style
            let style = try await chartCustomization.applyTemplate(
                chartTemplate.template,
                to: data
            )
            
            // Generate chart
            let chart = try await chartCustomization.generateChart(
                data: data,
                style: style,
                options: chartTemplate.options
            )
            
            charts.append(ReportChart(
                view: AnyView(chart),
                options: chartTemplate.options
            ))
        }
        
        return charts
    }
    
    private func applyChartTemplates(
        _ templates: [ChartTemplate],
        to report: AnalyticsReport
    ) async throws -> AnalyticsReport {
        var modifiedReport = report
        
        for section in modifiedReport.sections {
            for chart in section.charts {
                // Find matching template
                if let template = templates.first(where: { $0.type == chart.type }) {
                    // Apply template to chart
                    let style = try await chartCustomization.applyTemplate(
                        template,
                        to: chart.data
                    )
                    
                    // Update chart with new style
                    chart.style = style
                }
            }
        }
        
        return modifiedReport
    }
    
    private func applyStyle(
        _ style: ReportStyle,
        to report: AnalyticsReport
    ) async throws -> AnalyticsReport {
        var modifiedReport = report
        
        // Apply fonts
        modifiedReport.style.fonts = style.fonts
        
        // Apply colors
        modifiedReport.style.colors = style.colors
        
        // Apply layout options
        modifiedReport.style.layout = style.layout
        
        return modifiedReport
    }
}

// MARK: - Supporting Types

struct ReportTemplate: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let type: ReportType
    let layout: ReportLayout
    let sectionTemplates: [SectionTemplate]
    let chartTemplates: [ChartTemplate]
    let style: ReportStyle
    let metadata: [String: String]
    let createdAt: Date
    let updatedAt: Date
    
    init(
        name: String,
        description: String,
        type: ReportType,
        layout: ReportLayout = .standard,
        sectionTemplates: [SectionTemplate] = [],
        chartTemplates: [ChartTemplate] = [],
        style: ReportStyle = ReportStyle(),
        metadata: [String: String] = [:]
    ) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.type = type
        self.layout = layout
        self.sectionTemplates = sectionTemplates
        self.chartTemplates = chartTemplates
        self.style = style
        self.metadata = metadata
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct SectionTemplate: Codable {
    let title: String
    let type: SectionType
    let chartTemplates: [ChartTemplate]
    let style: SectionStyle
    let order: Int
    
    enum SectionType {
        case overview
        case performance
        case storage
        case cost
        case custom((AnalyticsReport) async throws -> String)
    }
}

struct ReportLayout: Codable {
    let pageSize: PageSize
    let margins: EdgeInsets
    let columns: Int
    let spacing: CGFloat
    let headerHeight: CGFloat
    let footerHeight: CGFloat
    
    enum PageSize: String, Codable {
        case a4
        case letter
        case custom(CGSize)
    }
    
    static let standard = ReportLayout(
        pageSize: .a4,
        margins: EdgeInsets(top: 50, leading: 50, bottom: 50, trailing: 50),
        columns: 1,
        spacing: 20,
        headerHeight: 100,
        footerHeight: 50
    )
}

struct ReportStyle: Codable {
    var fonts: FontSet
    var colors: ColorSet
    var layout: LayoutOptions
    
    struct FontSet: Codable {
        var title: Font
        var heading: Font
        var body: Font
        var caption: Font
    }
    
    struct ColorSet: Codable {
        var primary: Color
        var secondary: Color
        var accent: Color
        var background: Color
        var text: Color
    }
    
    struct LayoutOptions: Codable {
        var alignment: TextAlignment
        var lineSpacing: CGFloat
        var paragraphSpacing: CGFloat
    }
}

struct SectionStyle: Codable {
    var padding: EdgeInsets
    var background: Color
    var borderColor: Color
    var borderWidth: CGFloat
    var cornerRadius: CGFloat
}

enum TemplateError: Error {
    case creationFailed(error: Error)
    case updateFailed(error: Error)
    case deletionFailed(error: Error)
    case applicationFailed(error: Error)
    case validation(String)
}

// MARK: - Template Extensions

extension ReportTemplate {
    static let executive = ReportTemplate(
        name: "Executive Summary",
        description: "High-level overview for executives",
        type: .executive,
        sectionTemplates: [
            SectionTemplate(
                title: "Overview",
                type: .overview,
                chartTemplates: [
                    ChartTemplate.modern
                ],
                style: SectionStyle(),
                order: 0
            ),
            SectionTemplate(
                title: "Key Metrics",
                type: .custom { report in
                    try await generateKeyMetrics(for: report)
                },
                chartTemplates: [],
                style: SectionStyle(),
                order: 1
            )
        ]
    )
    
    static let technical = ReportTemplate(
        name: "Technical Analysis",
        description: "Detailed technical metrics and analysis",
        type: .technical,
        sectionTemplates: [
            SectionTemplate(
                title: "Performance Analysis",
                type: .performance,
                chartTemplates: [
                    ChartTemplate.modern
                ],
                style: SectionStyle(),
                order: 0
            ),
            SectionTemplate(
                title: "Storage Analysis",
                type: .storage,
                chartTemplates: [
                    ChartTemplate.modern
                ],
                style: SectionStyle(),
                order: 1
            )
        ]
    )
    
    static let cost = ReportTemplate(
        name: "Cost Analysis",
        description: "Detailed cost breakdown and projections",
        type: .cost,
        sectionTemplates: [
            SectionTemplate(
                title: "Cost Overview",
                type: .cost,
                chartTemplates: [
                    ChartTemplate.modern
                ],
                style: SectionStyle(),
                order: 0
            ),
            SectionTemplate(
                title: "Cost Projections",
                type: .custom { report in
                    try await generateCostProjections(for: report)
                },
                chartTemplates: [],
                style: SectionStyle(),
                order: 1
            )
        ]
    )
}

// MARK: - Helper Functions

private func generateKeyMetrics(
    for report: AnalyticsReport
) async throws -> String {
    // Implementation would generate key metrics text
    return ""
}

private func generateCostProjections(
    for report: AnalyticsReport
) async throws -> String {
    // Implementation would generate cost projections text
    return ""
}
