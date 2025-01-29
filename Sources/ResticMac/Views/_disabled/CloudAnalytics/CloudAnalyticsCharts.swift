import SwiftUI
import Charts

// MARK: - Chart Components

struct StorageUsageChart: View {
    let data: [StorageRecord]
    let timeRange: TimeRange
    
    var body: some View {
        Chart {
            ForEach(data) { record in
                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Total", Double(record.metrics.totalBytes))
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Compressed", Double(record.metrics.compressedBytes))
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Deduplicated", Double(record.metrics.deduplicatedBytes))
                )
                .foregroundStyle(.orange)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: timeRange.strideInterval)) { value in
                AxisGridLine()
                AxisValueLabel(format: timeRange.dateFormat)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bytes = value.as(Double.self) {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                    }
                }
            }
        }
        .chartLegend(position: .bottom) {
            HStack {
                LegendItem(color: .blue, label: "Total")
                LegendItem(color: .green, label: "Compressed")
                LegendItem(color: .orange, label: "Deduplicated")
            }
        }
    }
}

struct TransferSpeedChart: View {
    let data: [TransferRecord]
    let timeRange: TimeRange
    
    var body: some View {
        Chart {
            ForEach(data) { record in
                BarMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Upload", Double(record.metrics.uploadedBytes))
                )
                .foregroundStyle(.blue)
                
                BarMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Download", Double(record.metrics.downloadedBytes))
                )
                .foregroundStyle(.green)
            }
            
            ForEach(data) { record in
                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Speed", record.metrics.averageTransferSpeed)
                )
                .foregroundStyle(.red)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: timeRange.strideInterval)) { value in
                AxisGridLine()
                AxisValueLabel(format: timeRange.dateFormat)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let speed = value.as(Double.self) {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .memory) + "/s")
                    }
                }
            }
        }
        .chartLegend(position: .bottom) {
            HStack {
                LegendItem(color: .blue, label: "Upload")
                LegendItem(color: .green, label: "Download")
                LegendItem(color: .red, label: "Speed")
            }
        }
    }
}

struct CostAnalysisChart: View {
    let data: [CostRecord]
    let timeRange: TimeRange
    
    var body: some View {
        Chart {
            ForEach(data) { record in
                BarMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Storage", record.metrics.storageUnitCost)
                )
                .foregroundStyle(.blue)
                
                BarMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Transfer", record.metrics.transferUnitCost)
                )
                .foregroundStyle(.green)
            }
            
            ForEach(data) { record in
                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Total", record.metrics.totalCost)
                )
                .foregroundStyle(.red)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: timeRange.strideInterval)) { value in
                AxisGridLine()
                AxisValueLabel(format: timeRange.dateFormat)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let cost = value.as(Double.self) {
                        Text(NumberFormatter.currency.string(from: NSNumber(value: cost)) ?? "")
                    }
                }
            }
        }
        .chartLegend(position: .bottom) {
            HStack {
                LegendItem(color: .blue, label: "Storage Cost")
                LegendItem(color: .green, label: "Transfer Cost")
                LegendItem(color: .red, label: "Total Cost")
            }
        }
    }
}

struct SnapshotDistributionChart: View {
    let data: [SnapshotRecord]
    let timeRange: TimeRange
    
    var body: some View {
        Chart {
            ForEach(data) { record in
                BarMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Count", record.metrics.totalSnapshots)
                )
                .foregroundStyle(.blue)
            }
            
            ForEach(data) { record in
                LineMark(
                    x: .value("Time", record.timestamp),
                    y: .value("Size", Double(record.metrics.averageSnapshotSize))
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: timeRange.strideInterval)) { value in
                AxisGridLine()
                AxisValueLabel(format: timeRange.dateFormat)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let size = value.as(Double.self) {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                }
            }
        }
        .chartLegend(position: .bottom) {
            HStack {
                LegendItem(color: .blue, label: "Snapshot Count")
                LegendItem(color: .green, label: "Average Size")
            }
        }
    }
}

struct TrendChart: View {
    let data: [Double]
    let timestamps: [Date]
    let analysis: TrendAnalysis
    let timeRange: TimeRange
    let valueFormatter: (Double) -> String
    
    var body: some View {
        Chart {
            ForEach(Array(zip(timestamps, data).enumerated()), id: \.offset) { index, point in
                LineMark(
                    x: .value("Time", point.0),
                    y: .value("Value", point.1)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)
            }
            
            if analysis.isReliable {
                let trendline = calculateTrendline(data: data, timestamps: timestamps)
                ForEach(Array(zip(timestamps, trendline).enumerated()), id: \.offset) { index, point in
                    LineMark(
                        x: .value("Time", point.0),
                        y: .value("Trend", point.1)
                    )
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(dash: [5, 5]))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: timeRange.strideInterval)) { value in
                AxisGridLine()
                AxisValueLabel(format: timeRange.dateFormat)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text(valueFormatter(val))
                    }
                }
            }
        }
        .chartLegend(position: .bottom) {
            HStack {
                LegendItem(color: .blue, label: "Actual")
                if analysis.isReliable {
                    LegendItem(color: .red, label: "Trend")
                }
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading) {
                Text("Trend: \(analysis.trend.description)")
                if let seasonality = analysis.seasonality {
                    Text("Pattern: \(seasonality.description)")
                }
                Text("Confidence: \(Int(analysis.confidence * 100))%")
            }
            .font(.caption)
            .padding(8)
            .background(.regularMaterial)
            .cornerRadius(8)
            .padding()
        }
    }
    
    private func calculateTrendline(data: [Double], timestamps: [Date]) -> [Double] {
        let timeIntervals = timestamps.map { $0.timeIntervalSince1970 }
        let n = Double(data.count)
        
        let sumX = timeIntervals.reduce(0, +)
        let sumY = data.reduce(0, +)
        let sumXY = zip(timeIntervals, data).map(*).reduce(0, +)
        let sumX2 = timeIntervals.map { $0 * $0 }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        let intercept = (sumY - slope * sumX) / n
        
        return timeIntervals.map { slope * $0 + intercept }
    }
}

// MARK: - Supporting Views

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
        }
    }
}

// MARK: - Extensions

extension TimeRange {
    var strideInterval: Calendar.Component {
        switch self {
        case .day: return .hour
        case .week: return .day
        case .month: return .weekOfMonth
        case .year: return .month
        }
    }
    
    var dateFormat: Date.FormatStyle {
        switch self {
        case .day:
            return .dateTime.hour()
        case .week:
            return .dateTime.weekday()
        case .month:
            return .dateTime.day()
        case .year:
            return .dateTime.month()
        }
    }
}

extension NumberFormatter {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

extension ByteCountFormatter {
    static func string(fromByteCount bytes: Int64, countStyle: ByteCountFormatter.CountStyle) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = countStyle
        return formatter.string(fromByteCount: bytes)
    }
}
