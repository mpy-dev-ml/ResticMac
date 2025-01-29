import Foundation

actor CloudAnalyticsValidation {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsValidation")
    
    // MARK: - Storage Metrics Validation
    
    func validateStorageMetrics(_ metrics: StorageMetrics) throws {
        // Basic range checks
        guard metrics.totalBytes >= 0 else {
            throw ValidationError.invalidValue("Total bytes cannot be negative")
        }
        
        guard metrics.compressedBytes >= 0 else {
            throw ValidationError.invalidValue("Compressed bytes cannot be negative")
        }
        
        guard metrics.deduplicatedBytes >= 0 else {
            throw ValidationError.invalidValue("Deduplicated bytes cannot be negative")
        }
        
        // Logical relationships
        guard metrics.compressedBytes <= metrics.totalBytes else {
            throw ValidationError.inconsistentData("Compressed bytes cannot exceed total bytes")
        }
        
        guard metrics.deduplicatedBytes <= metrics.compressedBytes else {
            throw ValidationError.inconsistentData("Deduplicated bytes cannot exceed compressed bytes")
        }
        
        // Sanity checks
        if metrics.totalBytes > 0 {
            let compressionRatio = Double(metrics.compressedBytes) / Double(metrics.totalBytes)
            guard compressionRatio >= 0.1 else {
                throw ValidationError.suspiciousValue("Unusually high compression ratio")
            }
        }
    }
    
    // MARK: - Transfer Metrics Validation
    
    func validateTransferMetrics(_ metrics: TransferMetrics) throws {
        // Basic range checks
        guard metrics.uploadedBytes >= 0 else {
            throw ValidationError.invalidValue("Uploaded bytes cannot be negative")
        }
        
        guard metrics.downloadedBytes >= 0 else {
            throw ValidationError.invalidValue("Downloaded bytes cannot be negative")
        }
        
        guard metrics.averageTransferSpeed >= 0 else {
            throw ValidationError.invalidValue("Transfer speed cannot be negative")
        }
        
        guard (0.0...1.0).contains(metrics.successRate) else {
            throw ValidationError.invalidValue("Success rate must be between 0 and 1")
        }
        
        // Sanity checks
        if metrics.averageTransferSpeed > 1_000_000_000 { // 1 GB/s
            throw ValidationError.suspiciousValue("Unusually high transfer speed")
        }
        
        if metrics.uploadedBytes > 1_000_000_000_000 { // 1 TB
            throw ValidationError.suspiciousValue("Unusually large upload size")
        }
    }
    
    // MARK: - Cost Metrics Validation
    
    func validateCostMetrics(_ metrics: CostMetrics) throws {
        // Basic range checks
        guard metrics.storageUnitCost >= 0 else {
            throw ValidationError.invalidValue("Storage unit cost cannot be negative")
        }
        
        guard metrics.transferUnitCost >= 0 else {
            throw ValidationError.invalidValue("Transfer unit cost cannot be negative")
        }
        
        guard metrics.totalCost >= 0 else {
            throw ValidationError.invalidValue("Total cost cannot be negative")
        }
        
        // Sanity checks
        if metrics.storageUnitCost > 1.0 { // $1 per GB is very high
            throw ValidationError.suspiciousValue("Unusually high storage unit cost")
        }
        
        if metrics.transferUnitCost > 0.5 { // $0.50 per GB is very high
            throw ValidationError.suspiciousValue("Unusually high transfer unit cost")
        }
    }
    
    // MARK: - Snapshot Metrics Validation
    
    func validateSnapshotMetrics(_ metrics: SnapshotMetrics) throws {
        // Basic range checks
        guard metrics.totalSnapshots >= 0 else {
            throw ValidationError.invalidValue("Total snapshots cannot be negative")
        }
        
        guard metrics.averageSnapshotSize >= 0 else {
            throw ValidationError.invalidValue("Average snapshot size cannot be negative")
        }
        
        guard metrics.retentionDays > 0 else {
            throw ValidationError.invalidValue("Retention days must be positive")
        }
        
        // Sanity checks
        if metrics.totalSnapshots > 10000 {
            throw ValidationError.suspiciousValue("Unusually high number of snapshots")
        }
        
        if metrics.retentionDays > 3650 { // 10 years
            throw ValidationError.suspiciousValue("Unusually long retention period")
        }
    }
    
    // MARK: - Time Series Validation
    
    func validateTimeSeriesData<T>(_ data: [TimeSeriesPoint<T>]) throws {
        guard !data.isEmpty else {
            throw ValidationError.emptyData("Time series cannot be empty")
        }
        
        // Check for chronological order
        var lastTimestamp = data[0].timestamp
        for point in data.dropFirst() {
            guard point.timestamp > lastTimestamp else {
                throw ValidationError.invalidTimeSequence("Data points must be in chronological order")
            }
            lastTimestamp = point.timestamp
        }
        
        // Check for gaps
        let timeGaps = zip(data, data.dropFirst()).map { 
            $1.timestamp.timeIntervalSince($0.timestamp)
        }
        
        let maxGap = timeGaps.max() ?? 0
        if maxGap > 86400 * 7 { // 7 days
            throw ValidationError.suspiciousValue("Unusually large gap in time series data")
        }
        
        // Check for duplicates
        let timestamps = data.map { $0.timestamp }
        if Set(timestamps).count != timestamps.count {
            throw ValidationError.duplicateData("Duplicate timestamps detected")
        }
    }
    
    // MARK: - Trend Analysis Validation
    
    func validateTrendAnalysis(_ trend: TrendAnalysis) throws {
        // Basic range checks
        guard trend.confidence >= 0 && trend.confidence <= 1 else {
            throw ValidationError.invalidValue("Confidence must be between 0 and 1")
        }
        
        guard trend.sampleSize > 0 else {
            throw ValidationError.invalidValue("Sample size must be positive")
        }
        
        // Statistical validity
        if trend.confidence > 0.9 && trend.sampleSize < 3 {
            throw ValidationError.invalidValue("High confidence requires more samples")
        }
        
        if trend.outlierCount > trend.sampleSize / 2 {
            throw ValidationError.suspiciousValue("Too many outliers detected")
        }
    }
    
    // MARK: - Data Sanitization
    
    func sanitizeMetrics<T: MetricsProtocol>(_ metrics: T) throws -> T {
        var sanitized = metrics
        
        // Round numerical values to reasonable precision
        if let storage = metrics as? StorageMetrics {
            sanitized = StorageMetrics(
                totalBytes: storage.totalBytes,
                compressedBytes: storage.compressedBytes,
                deduplicatedBytes: storage.deduplicatedBytes
            ) as! T
        }
        
        if let transfer = metrics as? TransferMetrics {
            sanitized = TransferMetrics(
                uploadedBytes: transfer.uploadedBytes,
                downloadedBytes: transfer.downloadedBytes,
                averageTransferSpeed: round(transfer.averageTransferSpeed * 100) / 100,
                successRate: round(transfer.successRate * 1000) / 1000
            ) as! T
        }
        
        if let cost = metrics as? CostMetrics {
            sanitized = CostMetrics(
                storageUnitCost: round(cost.storageUnitCost * 10000) / 10000,
                transferUnitCost: round(cost.transferUnitCost * 10000) / 10000,
                totalCost: round(cost.totalCost * 100) / 100
            ) as! T
        }
        
        return sanitized
    }
    
    // MARK: - Data Repair
    
    func repairTimeSeriesGaps<T: MetricsProtocol>(_ data: [TimeSeriesPoint<T>]) throws -> [TimeSeriesPoint<T>] {
        guard data.count >= 2 else { return data }
        
        var repaired = [data[0]]
        let maxGap = TimeInterval(86400) // 1 day
        
        for i in 1..<data.count {
            let gap = data[i].timestamp.timeIntervalSince(data[i-1].timestamp)
            
            if gap > maxGap {
                // Interpolate missing points
                let pointsNeeded = Int(gap / maxGap)
                let timeStep = gap / Double(pointsNeeded + 1)
                
                for j in 1...pointsNeeded {
                    let timestamp = data[i-1].timestamp.addingTimeInterval(timeStep * Double(j))
                    let interpolatedValue = try interpolateMetrics(
                        from: data[i-1].value,
                        to: data[i].value,
                        progress: Double(j) / Double(pointsNeeded + 1)
                    )
                    repaired.append(TimeSeriesPoint(timestamp: timestamp, value: interpolatedValue))
                }
            }
            
            repaired.append(data[i])
        }
        
        return repaired
    }
    
    private func interpolateMetrics<T: MetricsProtocol>(_ from: T, _ to: T, progress: Double) throws -> T {
        // Implement linear interpolation based on metric type
        // This is a placeholder - implement specific interpolation logic for each metric type
        return from
    }
}

// MARK: - Supporting Types

enum ValidationError: LocalizedError {
    case invalidValue(_ message: String)
    case inconsistentData(_ message: String)
    case suspiciousValue(_ message: String)
    case emptyData(_ message: String)
    case invalidTimeSequence(_ message: String)
    case duplicateData(_ message: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidValue(let message): return "Invalid value: \(message)"
        case .inconsistentData(let message): return "Inconsistent data: \(message)"
        case .suspiciousValue(let message): return "Suspicious value detected: \(message)"
        case .emptyData(let message): return "Empty data: \(message)"
        case .invalidTimeSequence(let message): return "Invalid time sequence: \(message)"
        case .duplicateData(let message): return "Duplicate data: \(message)"
        }
    }
}

struct TimeSeriesPoint<T> {
    let timestamp: Date
    let value: T
}

protocol MetricsProtocol {
    // Define common metrics functionality
    // This is a placeholder - implement specific requirements
}
