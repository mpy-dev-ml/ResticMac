import Foundation
import PDFKit
import SwiftUI
import Charts
import OSLog

actor CloudAnalyticsPDFExporter {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsPDFExporter")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    
    init(persistence: CloudAnalyticsPersistence, monitor: CloudAnalyticsMonitor) {
        self.persistence = persistence
        self.monitor = monitor
    }
    
    // MARK: - PDF Export
    
    func exportReport(
        _ report: AnalyticsReport,
        to url: URL,
        options: PDFExportOptions = PDFExportOptions()
    ) async throws {
        let tracker = await monitor.trackOperation("export_pdf")
        defer { tracker.stop() }
        
        do {
            // Create PDF document
            let pdfDocument = PDFDocument()
            
            // Add cover page
            try await addCoverPage(to: pdfDocument, for: report)
            
            // Add table of contents
            try await addTableOfContents(to: pdfDocument, for: report)
            
            // Add report sections
            try await addReportSections(to: pdfDocument, for: report, options: options)
            
            // Add insights and recommendations
            try await addInsightsAndRecommendations(to: pdfDocument, for: report)
            
            // Add appendices
            if options.includeAppendices {
                try await addAppendices(to: pdfDocument, for: report)
            }
            
            // Save PDF
            try pdfDocument.write(to: url)
            
            logger.info("Exported PDF report to: \(url.path)")
            
        } catch {
            logger.error("PDF export failed: \(error.localizedDescription)")
            throw PDFExportError.exportFailed(error: error)
        }
    }
    
    // MARK: - Page Generation
    
    private func addCoverPage(
        to document: PDFDocument,
        for report: AnalyticsReport
    ) async throws {
        let page = PDFPage()
        let context = try getGraphicsContext(for: page)
        
        // Draw company logo
        if let logo = NSImage(named: "CompanyLogo") {
            drawImage(
                logo,
                in: CGRect(x: 50, y: 700, width: 200, height: 100),
                context: context
            )
        }
        
        // Draw title
        drawText(
            "Analytics Report",
            at: CGPoint(x: 50, y: 600),
            font: .systemFont(ofSize: 36, weight: .bold),
            context: context
        )
        
        // Draw report type
        drawText(
            report.type.rawValue.capitalized,
            at: CGPoint(x: 50, y: 550),
            font: .systemFont(ofSize: 24),
            context: context
        )
        
        // Draw repository info
        drawText(
            "Repository: \(report.repository.path.lastPathComponent)",
            at: CGPoint(x: 50, y: 500),
            font: .systemFont(ofSize: 18),
            context: context
        )
        
        // Draw date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        drawText(
            "Generated: \(dateFormatter.string(from: report.generatedAt))",
            at: CGPoint(x: 50, y: 450),
            font: .systemFont(ofSize: 18),
            context: context
        )
        
        document.insert(page, at: document.pageCount)
    }
    
    private func addTableOfContents(
        to document: PDFDocument,
        for report: AnalyticsReport
    ) async throws {
        let page = PDFPage()
        let context = try getGraphicsContext(for: page)
        
        // Draw title
        drawText(
            "Table of Contents",
            at: CGPoint(x: 50, y: 750),
            font: .systemFont(ofSize: 24, weight: .bold),
            context: context
        )
        
        // Draw sections
        var yPosition = 700.0
        for (index, section) in report.sections.enumerated() {
            drawText(
                "\(index + 1). \(section.title)",
                at: CGPoint(x: 50, y: yPosition),
                font: .systemFont(ofSize: 14),
                context: context
            )
            yPosition -= 30
        }
        
        // Draw insights and recommendations
        yPosition -= 30
        drawText(
            "\(report.sections.count + 1). Insights and Recommendations",
            at: CGPoint(x: 50, y: yPosition),
            font: .systemFont(ofSize: 14),
            context: context
        )
        
        document.insert(page, at: document.pageCount)
    }
    
    private func addReportSections(
        to document: PDFDocument,
        for report: AnalyticsReport,
        options: PDFExportOptions
    ) async throws {
        for section in report.sections {
            try await addSection(section, to: document, options: options)
        }
    }
    
    private func addSection(
        _ section: ReportSection,
        to document: PDFDocument,
        options: PDFExportOptions
    ) async throws {
        let page = PDFPage()
        let context = try getGraphicsContext(for: page)
        
        // Draw section title
        drawText(
            section.title,
            at: CGPoint(x: 50, y: 750),
            font: .systemFont(ofSize: 24, weight: .bold),
            context: context
        )
        
        // Draw content
        let contentRect = CGRect(x: 50, y: 200, width: 500, height: 500)
        drawText(
            section.content,
            in: contentRect,
            font: .systemFont(ofSize: 12),
            context: context
        )
        
        // Draw charts
        if options.includeCharts {
            try await addCharts(
                section.charts,
                to: document,
                startingAt: document.pageCount + 1
            )
        }
        
        document.insert(page, at: document.pageCount)
    }
    
    private func addCharts(
        _ charts: [ReportChart],
        to document: PDFDocument,
        startingAt pageIndex: Int
    ) async throws {
        for chart in charts {
            let page = PDFPage()
            let context = try getGraphicsContext(for: page)
            
            // Create chart view
            let chartView = try await createChartView(for: chart)
            
            // Convert chart to image
            let chartImage = try await renderChartAsImage(chartView)
            
            // Draw chart
            drawImage(
                chartImage,
                in: CGRect(x: 50, y: 200, width: 500, height: 300),
                context: context
            )
            
            // Draw chart title
            drawText(
                chart.options.title,
                at: CGPoint(x: 50, y: 550),
                font: .systemFont(ofSize: 18, weight: .semibold),
                context: context
            )
            
            document.insert(page, at: document.pageCount)
        }
    }
    
    private func addInsightsAndRecommendations(
        to document: PDFDocument,
        for report: AnalyticsReport
    ) async throws {
        let page = PDFPage()
        let context = try getGraphicsContext(for: page)
        
        // Draw title
        drawText(
            "Insights and Recommendations",
            at: CGPoint(x: 50, y: 750),
            font: .systemFont(ofSize: 24, weight: .bold),
            context: context
        )
        
        // Draw insights
        var yPosition = 700.0
        drawText(
            "Key Insights:",
            at: CGPoint(x: 50, y: yPosition),
            font: .systemFont(ofSize: 18, weight: .semibold),
            context: context
        )
        
        yPosition -= 30
        for insight in report.insights {
            drawText(
                "• \(insight.title): \(insight.description)",
                at: CGPoint(x: 70, y: yPosition),
                font: .systemFont(ofSize: 12),
                context: context
            )
            yPosition -= 20
        }
        
        // Draw recommendations
        yPosition -= 30
        drawText(
            "Recommendations:",
            at: CGPoint(x: 50, y: yPosition),
            font: .systemFont(ofSize: 18, weight: .semibold),
            context: context
        )
        
        yPosition -= 30
        for recommendation in report.recommendations {
            drawText(
                "• \(recommendation.title) (Priority: \(recommendation.priority.rawValue))",
                at: CGPoint(x: 70, y: yPosition),
                font: .systemFont(ofSize: 12),
                context: context
            )
            yPosition -= 20
            
            drawText(
                "  \(recommendation.description)",
                at: CGPoint(x: 90, y: yPosition),
                font: .systemFont(ofSize: 12),
                context: context
            )
            yPosition -= 30
        }
        
        document.insert(page, at: document.pageCount)
    }
    
    private func addAppendices(
        to document: PDFDocument,
        for report: AnalyticsReport
    ) async throws {
        let page = PDFPage()
        let context = try getGraphicsContext(for: page)
        
        // Draw title
        drawText(
            "Appendices",
            at: CGPoint(x: 50, y: 750),
            font: .systemFont(ofSize: 24, weight: .bold),
            context: context
        )
        
        // Add methodology
        drawText(
            "Methodology",
            at: CGPoint(x: 50, y: 700),
            font: .systemFont(ofSize: 18, weight: .semibold),
            context: context
        )
        
        let methodologyText = """
        This report was generated using advanced analytics and machine learning algorithms to process and analyse repository data.
        The analysis includes:
        • Storage metrics analysis
        • Performance monitoring
        • Cost tracking
        • Pattern detection
        • Trend analysis
        """
        
        drawText(
            methodologyText,
            in: CGRect(x: 50, y: 500, width: 500, height: 150),
            font: .systemFont(ofSize: 12),
            context: context
        )
        
        document.insert(page, at: document.pageCount)
    }
    
    // MARK: - Chart Generation
    
    private func createChartView(
        for chart: ReportChart
    ) async throws -> some View {
        switch chart.type {
        case .line:
            return createLineChart(with: chart.data, options: chart.options)
        case .bar:
            return createBarChart(with: chart.data, options: chart.options)
        case .pie:
            return createPieChart(with: chart.data, options: chart.options)
        case .area:
            return createAreaChart(with: chart.data, options: chart.options)
        case .scatter:
            return createScatterChart(with: chart.data, options: chart.options)
        }
    }
    
    private func createLineChart(
        with data: [String: Any],
        options: ReportChart.ChartOptions
    ) -> some View {
        Chart {
            ForEach(data.values as? [Double] ?? [], id: \.self) { value in
                LineMark(
                    x: .value("X", value),
                    y: .value("Y", value)
                )
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic)
        }
        .chartYAxis {
            AxisMarks(values: .automatic)
        }
        .frame(width: 500, height: 300)
    }
    
    // MARK: - Helper Methods
    
    private func getGraphicsContext(
        for page: PDFPage
    ) throws -> CGContext {
        guard let context = page.pageRef?.createContext() else {
            throw PDFExportError.contextCreationFailed
        }
        return context
    }
    
    private func drawText(
        _ text: String,
        at point: CGPoint,
        font: NSFont,
        context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let attributedString = NSAttributedString(
            string: text,
            attributes: attributes
        )
        
        attributedString.draw(at: point)
    }
    
    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        
        let attributedString = NSAttributedString(
            string: text,
            attributes: attributes
        )
        
        attributedString.draw(in: rect)
    }
    
    private func drawImage(
        _ image: NSImage,
        in rect: CGRect,
        context: CGContext
    ) {
        image.draw(in: rect)
    }
    
    private func renderChartAsImage(
        _ chart: some View
    ) async throws -> NSImage {
        let renderer = ImageRenderer(content: chart)
        
        guard let nsImage = renderer.nsImage else {
            throw PDFExportError.chartRenderingFailed
        }
        
        return nsImage
    }
}

// MARK: - Supporting Types

struct PDFExportOptions {
    var includeCharts: Bool = true
    var includeAppendices: Bool = true
    var chartStyle: ChartStyle = .automatic
    var colorScheme: ColorScheme = .automatic
    var pageSize: PDFSize = .a4
    var orientation: PDFOrientation = .portrait
    
    enum PDFSize {
        case a4
        case letter
        case custom(CGSize)
        
        var size: CGSize {
            switch self {
            case .a4:
                return CGSize(width: 595, height: 842) // Points (72 dpi)
            case .letter:
                return CGSize(width: 612, height: 792)
            case .custom(let size):
                return size
            }
        }
    }
    
    enum PDFOrientation {
        case portrait
        case landscape
    }
}

enum PDFExportError: Error {
    case exportFailed(error: Error)
    case contextCreationFailed
    case chartRenderingFailed
}

enum ChartStyle {
    case automatic
    case light
    case dark
    case custom(ColorPalette)
    
    struct ColorPalette {
        let primary: Color
        let secondary: Color
        let accent: Color
        let background: Color
    }
}
