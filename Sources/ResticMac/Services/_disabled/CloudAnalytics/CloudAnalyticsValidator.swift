import Foundation
import OSLog

actor CloudAnalyticsValidator {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsValidator")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    
    init(persistence: CloudAnalyticsPersistence, monitor: CloudAnalyticsMonitor) {
        self.persistence = persistence
        self.monitor = monitor
    }
    
    // MARK: - Data Validation
    
    func validateAnalytics(
        for repository: Repository,
        timeRange: DateInterval? = nil
    ) async throws -> ValidationReport {
        let tracker = await monitor.trackOperation("validate_analytics")
        defer { tracker.stop() }
        
        do {
            // Gather metrics for validation
            let metrics = try await gatherMetrics(for: repository, timeRange: timeRange)
            
            // Run validation checks
            let storageValidation = try await validateStorageMetrics(metrics.storageHistory)
            let transferValidation = try await validateTransferMetrics(metrics.transferHistory)
            let costValidation = try await validateCostMetrics(metrics.costHistory)
            
            // Generate report
            let report = ValidationReport(
                repository: repository,
                timeRange: timeRange,
                storageValidation: storageValidation,
                transferValidation: transferValidation,
                costValidation: costValidation,
                timestamp: Date()
            )
            
            // Log validation results
            logger.info("Completed analytics validation for repository: \(repository.id)")
            return report
            
        } catch {
            logger.error("Analytics validation failed: \(error.localizedDescription)")
            throw ValidationError.validationFailed(error: error)
        }
    }
    
    // MARK: - Storage Validation
    
    private func validateStorageMetrics(
        _ metrics: [TimeSeriesPoint<StorageMetrics>]
    ) async throws -> ValidationResult {
        var issues: [ValidationIssue] = []
        
        // Check for data gaps
        let gaps = findTimeSeriesGaps(in: metrics)
        if !gaps.isEmpty {
            issues.append(ValidationIssue(
                type: .dataGap,
                description: "Found \(gaps.count) gaps in storage metrics",
                severity: .warning,
                details: gaps.map { "Gap from \($0.start) to \($0.end)" }
            ))
        }
        
        // Validate metric values
        for point in metrics {
            // Check for negative values
            if point.value.totalBytes < 0 ||
               point.value.compressedBytes < 0 ||
               point.value.deduplicatedBytes < 0 {
                issues.append(ValidationIssue(
                    type: .invalidValue,
                    description: "Negative storage values found",
                    severity: .error,
                    details: ["Timestamp: \(point.timestamp)"]
                ))
            }
            
            // Check compression ratio
            let compressionRatio = Double(point.value.compressedBytes) / Double(point.value.totalBytes)
            if compressionRatio > 1.0 {
                issues.append(ValidationIssue(
                    type: .anomaly,
                    description: "Invalid compression ratio",
                    severity: .warning,
                    details: ["Ratio: \(compressionRatio)", "Timestamp: \(point.timestamp)"]
                ))
            }
            
            // Check deduplication ratio
            let deduplicationRatio = Double(point.value.deduplicatedBytes) / Double(point.value.totalBytes)
            if deduplicationRatio > 1.0 {
                issues.append(ValidationIssue(
                    type: .anomaly,
                    description: "Invalid deduplication ratio",
                    severity: .warning,
                    details: ["Ratio: \(deduplicationRatio)", "Timestamp: \(point.timestamp)"]
                ))
            }
        }
        
        // Check for anomalies
        let anomalies = detectAnomalies(in: metrics) { $0.value.totalBytes }
        if !anomalies.isEmpty {
            issues.append(ValidationIssue(
                type: .anomaly,
                description: "Storage anomalies detected",
                severity: .warning,
                details: anomalies.map { "Anomaly at \($0.timestamp)" }
            ))
        }
        
        return ValidationResult(
            metricType: "Storage",
            totalPoints: metrics.count,
            issues: issues
        )
    }
    
    // MARK: - Transfer Validation
    
    private func validateTransferMetrics(
        _ metrics: [TimeSeriesPoint<TransferMetrics>]
    ) async throws -> ValidationResult {
        var issues: [ValidationIssue] = []
        
        // Check for data gaps
        let gaps = findTimeSeriesGaps(in: metrics)
        if !gaps.isEmpty {
            issues.append(ValidationIssue(
                type: .dataGap,
                description: "Found \(gaps.count) gaps in transfer metrics",
                severity: .warning,
                details: gaps.map { "Gap from \($0.start) to \($0.end)" }
            ))
        }
        
        // Validate metric values
        for point in metrics {
            // Check for negative values
            if point.value.uploadedBytes < 0 ||
               point.value.downloadedBytes < 0 ||
               point.value.averageTransferSpeed < 0 {
                issues.append(ValidationIssue(
                    type: .invalidValue,
                    description: "Negative transfer values found",
                    severity: .error,
                    details: ["Timestamp: \(point.timestamp)"]
                ))
            }
            
            // Check success rate
            if point.value.successRate < 0 || point.value.successRate > 1.0 {
                issues.append(ValidationIssue(
                    type: .invalidValue,
                    description: "Invalid success rate",
                    severity: .error,
                    details: ["Rate: \(point.value.successRate)", "Timestamp: \(point.timestamp)"]
                ))
            }
            
            // Check transfer speed anomalies
            if point.value.averageTransferSpeed > 1_000_000_000 { // 1 GB/s threshold
                issues.append(ValidationIssue(
                    type: .anomaly,
                    description: "Unusually high transfer speed",
                    severity: .warning,
                    details: ["Speed: \(point.value.averageTransferSpeed)", "Timestamp: \(point.timestamp)"]
                ))
            }
        }
        
        // Check for anomalies
        let anomalies = detectAnomalies(in: metrics) { $0.value.averageTransferSpeed }
        if !anomalies.isEmpty {
            issues.append(ValidationIssue(
                type: .anomaly,
                description: "Transfer speed anomalies detected",
                severity: .warning,
                details: anomalies.map { "Anomaly at \($0.timestamp)" }
            ))
        }
        
        return ValidationResult(
            metricType: "Transfer",
            totalPoints: metrics.count,
            issues: issues
        )
    }
    
    // MARK: - Cost Validation
    
    private func validateCostMetrics(
        _ metrics: [TimeSeriesPoint<CostMetrics>]
    ) async throws -> ValidationResult {
        var issues: [ValidationIssue] = []
        
        // Check for data gaps
        let gaps = findTimeSeriesGaps(in: metrics)
        if !gaps.isEmpty {
            issues.append(ValidationIssue(
                type: .dataGap,
                description: "Found \(gaps.count) gaps in cost metrics",
                severity: .warning,
                details: gaps.map { "Gap from \($0.start) to \($0.end)" }
            ))
        }
        
        // Validate metric values
        for point in metrics {
            // Check for negative values
            if point.value.storageUnitCost < 0 ||
               point.value.transferUnitCost < 0 ||
               point.value.totalCost < 0 {
                issues.append(ValidationIssue(
                    type: .invalidValue,
                    description: "Negative cost values found",
                    severity: .error,
                    details: ["Timestamp: \(point.timestamp)"]
                ))
            }
            
            // Check cost consistency
            let calculatedTotal = (point.value.storageUnitCost + point.value.transferUnitCost)
            let difference = abs(calculatedTotal - point.value.totalCost)
            if difference > 0.01 { // Allow for small floating point differences
                issues.append(ValidationIssue(
                    type: .inconsistency,
                    description: "Cost calculation mismatch",
                    severity: .warning,
                    details: [
                        "Calculated: \(calculatedTotal)",
                        "Recorded: \(point.value.totalCost)",
                        "Timestamp: \(point.timestamp)"
                    ]
                ))
            }
        }
        
        // Check for anomalies
        let anomalies = detectAnomalies(in: metrics) { $0.value.totalCost }
        if !anomalies.isEmpty {
            issues.append(ValidationIssue(
                type: .anomaly,
                description: "Cost anomalies detected",
                severity: .warning,
                details: anomalies.map { "Anomaly at \($0.timestamp)" }
            ))
        }
        
        return ValidationResult(
            metricType: "Cost",
            totalPoints: metrics.count,
            issues: issues
        )
    }
    
    // MARK: - Anomaly Detection
    
    private func detectAnomalies<T>(
        in points: [TimeSeriesPoint<T>],
        valueExtractor: (TimeSeriesPoint<T>) -> Double
    ) -> [TimeSeriesPoint<T>] {
        guard points.count > 4 else { return [] }
        
        let values = points.map(valueExtractor)
        let mean = values.reduce(0, +) / Double(values.count)
        let stdDev = sqrt(values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count))
        let threshold = 3.0 * stdDev // 3-sigma rule
        
        return points.filter { point in
            let value = valueExtractor(point)
            return abs(value - mean) > threshold
        }
    }
    
    // MARK: - Gap Detection
    
    private func findTimeSeriesGaps<T>(
        in points: [TimeSeriesPoint<T>]
    ) -> [DateInterval] {
        guard points.count > 1 else { return [] }
        
        let sortedPoints = points.sorted { $0.timestamp < $1.timestamp }
        var gaps: [DateInterval] = []
        
        for i in 0..<(sortedPoints.count - 1) {
            let current = sortedPoints[i].timestamp
            let next = sortedPoints[i + 1].timestamp
            let gap = next.timeIntervalSince(current)
            
            // Consider gaps larger than 1 hour
            if gap > 3600 {
                gaps.append(DateInterval(start: current, end: next))
            }
        }
        
        return gaps
    }
    
    // MARK: - Helper Methods
    
    private func gatherMetrics(
        for repository: Repository,
        timeRange: DateInterval?
    ) async throws -> AnalyticsMetrics {
        let storageHistory = try await persistence.getStorageMetricsHistory(for: repository)
        let transferHistory = try await persistence.getTransferMetricsHistory(for: repository)
        let costHistory = try await persistence.getCostMetricsHistory(for: repository)
        
        // Filter by time range if specified
        let filteredStorage = timeRange.map { range in
            storageHistory.filter { range.contains($0.timestamp) }
        } ?? storageHistory
        
        let filteredTransfer = timeRange.map { range in
            transferHistory.filter { range.contains($0.timestamp) }
        } ?? transferHistory
        
        let filteredCost = timeRange.map { range in
            costHistory.filter { range.contains($0.timestamp) }
        } ?? costHistory
        
        return AnalyticsMetrics(
            storageHistory: filteredStorage,
            transferHistory: filteredTransfer,
            costHistory: filteredCost
        )
    }
}

// MARK: - Supporting Types

struct ValidationReport: Codable {
    let repository: Repository
    let timeRange: DateInterval?
    let storageValidation: ValidationResult
    let transferValidation: ValidationResult
    let costValidation: ValidationResult
    let timestamp: Date
    
    var hasErrors: Bool {
        storageValidation.hasErrors ||
        transferValidation.hasErrors ||
        costValidation.hasErrors
    }
    
    var hasWarnings: Bool {
        storageValidation.hasWarnings ||
        transferValidation.hasWarnings ||
        costValidation.hasWarnings
    }
}

struct ValidationResult: Codable {
    let metricType: String
    let totalPoints: Int
    let issues: [ValidationIssue]
    
    var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }
    
    var hasWarnings: Bool {
        issues.contains { $0.severity == .warning }
    }
}

struct ValidationIssue: Codable {
    let type: IssueType
    let description: String
    let severity: IssueSeverity
    let details: [String]
}

enum IssueType: String, Codable {
    case dataGap
    case invalidValue
    case anomaly
    case inconsistency
}

enum IssueSeverity: String, Codable {
    case error
    case warning
}

enum ValidationError: Error {
    case validationFailed(error: Error)
    case invalidTimeRange
    case insufficientData
}
