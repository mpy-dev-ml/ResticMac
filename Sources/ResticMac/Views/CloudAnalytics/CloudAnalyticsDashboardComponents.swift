import SwiftUI
import Charts

// MARK: - Performance Chart

struct PerformanceChart: View {
    let metrics: [PerformanceMetric]
    let timeRange: TimeRange
    
    var body: some View {
        Chart(metrics) { metric in
            LineMark(
                x: .value("Time", metric.timestamp),
                y: .value("Value", metric.value)
            )
            .foregroundStyle(by: .value("Metric", metric.name))
            .symbol(by: .value("Metric", metric.name))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: timeRange.strideInterval)) { value in
                AxisGridLine()
                AxisValueLabel(format: timeRange.dateFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartLegend(position: .bottom)
        .frame(height: 200)
    }
}

// MARK: - Health Status Card

struct HealthStatusCard: View {
    let status: SystemHealth
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("System Health", systemImage: healthIcon)
                    .font(.headline)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            
            HStack {
                statusIndicator
                Text(status.status.rawValue.capitalized)
                    .foregroundColor(statusColor)
            }
            
            Text(status.details)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if status.status != .healthy {
                Button("View Details") {
                    // Show detailed health report
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private var healthIcon: String {
        switch status.status {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .unhealthy: return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status.status {
        case .healthy: return .green
        case .degraded: return .yellow
        case .unhealthy: return .red
        }
    }
    
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Resource Monitor

struct ResourceMonitor: View {
    let usage: ResourceUsage
    let history: [ResourceMetric]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resource Usage")
                .font(.headline)
            
            ResourceGauge(
                title: "CPU",
                value: usage.cpuUsage,
                unit: "%",
                threshold: 80
            )
            
            ResourceGauge(
                title: "Memory",
                value: Double(usage.memoryUsage) / 1_000_000_000,
                unit: "GB",
                threshold: 4
            )
            
            ResourceGauge(
                title: "Disk",
                value: Double(usage.diskUsage) / 1_000_000_000,
                unit: "GB",
                threshold: 100
            )
            
            Chart(history) { metric in
                LineMark(
                    x: .value("Time", metric.timestamp),
                    y: .value("Usage", metric.value)
                )
                .foregroundStyle(by: .value("Resource", metric.name))
            }
            .frame(height: 100)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct ResourceGauge: View {
    let title: String
    let value: Double
    let unit: String
    let threshold: Double
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline)
            
            Gauge(value: value, in: 0...threshold) {
                EmptyView()
            } currentValueLabel: {
                Text("\(value, specifier: "%.1f") \(unit)")
                    .font(.caption)
            }
            .gaugeStyle(.accessoryLinear)
            .tint(gaugeColor)
        }
    }
    
    private var gaugeColor: Color {
        let percentage = value / threshold
        switch percentage {
        case ..<0.7: return .green
        case ..<0.9: return .yellow
        default: return .red
        }
    }
}

// MARK: - Alert List

struct AlertList: View {
    let alerts: [Alert]
    let onDismiss: (Alert) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Alerts")
                .font(.headline)
            
            if alerts.isEmpty {
                Text("No active alerts")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(alerts, id: \.id) { alert in
                    AlertRow(alert: alert, onDismiss: onDismiss)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct AlertRow: View {
    let alert: Alert
    let onDismiss: (Alert) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: alertIcon)
                .foregroundColor(alertColor)
            
            VStack(alignment: .leading) {
                Text(alertTitle)
                    .font(.subheadline)
                    .foregroundColor(alertColor)
                
                if case let .performanceWarning(message) = alert {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: { onDismiss(alert) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
    
    private var alertIcon: String {
        switch alert {
        case .performanceWarning: return "speedometer"
        case .errorRateWarning: return "exclamationmark.triangle"
        case .resourceWarning: return "cpu"
        }
    }
    
    private var alertColor: Color {
        switch alert {
        case .performanceWarning: return .yellow
        case .errorRateWarning: return .red
        case .resourceWarning: return .orange
        }
    }
    
    private var alertTitle: String {
        switch alert {
        case .performanceWarning: return "Performance Warning"
        case .errorRateWarning: return "Error Rate Warning"
        case .resourceWarning: return "Resource Warning"
        }
    }
}

// MARK: - Supporting Types

struct PerformanceMetric: Identifiable {
    let id = UUID()
    let name: String
    let timestamp: Date
    let value: Double
}

struct ResourceMetric: Identifiable {
    let id = UUID()
    let name: String
    let timestamp: Date
    let value: Double
}

enum TimeRange {
    case hour
    case day
    case week
    case month
    
    var strideInterval: Calendar.Component {
        switch self {
        case .hour: return .minute
        case .day: return .hour
        case .week: return .day
        case .month: return .weekOfMonth
        }
    }
    
    var dateFormat: Date.FormatStyle {
        switch self {
        case .hour: return .dateTime.hour().minute()
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday()
        case .month: return .dateTime.month().day()
        }
    }
}

extension Alert: Identifiable {
    var id: String {
        switch self {
        case .performanceWarning(let message): return "performance_\(message)"
        case .errorRateWarning(let message): return "error_\(message)"
        case .resourceWarning(let message): return "resource_\(message)"
        }
    }
}
