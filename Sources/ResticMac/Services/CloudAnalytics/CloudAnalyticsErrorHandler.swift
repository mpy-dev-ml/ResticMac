import Foundation
import OSLog

actor CloudAnalyticsErrorHandler {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsErrorHandler")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    private let recovery: CloudAnalyticsRecovery
    
    private var errorHistory: [ErrorRecord] = []
    private let maxHistorySize = 1000
    private let retryLimit = 3
    
    init(
        persistence: CloudAnalyticsPersistence,
        monitor: CloudAnalyticsMonitor,
        recovery: CloudAnalyticsRecovery
    ) {
        self.persistence = persistence
        self.monitor = monitor
        self.recovery = recovery
    }
    
    // MARK: - Error Handling
    
    func handleError(
        _ error: Error,
        context: ErrorContext,
        severity: ErrorSeverity = .error,
        recovery: ErrorRecoveryStrategy? = nil
    ) async throws -> ErrorResolution {
        let tracker = await monitor.trackOperation("handle_error")
        defer { tracker.stop() }
        
        do {
            // Log error
            logError(error, context: context, severity: severity)
            
            // Record error
            let record = ErrorRecord(
                error: error,
                context: context,
                severity: severity,
                timestamp: Date()
            )
            try await recordError(record)
            
            // Check for error patterns
            let pattern = try await detectErrorPattern(for: context)
            
            // Apply recovery strategy
            let resolution = try await applyRecoveryStrategy(
                for: error,
                context: context,
                pattern: pattern,
                strategy: recovery
            )
            
            // Update metrics
            await updateErrorMetrics(resolution: resolution)
            
            return resolution
            
        } catch {
            logger.error("Error handling failed: \(error.localizedDescription)")
            throw ErrorHandlingError.handlingFailed(error: error)
        }
    }
    
    // MARK: - Error Pattern Detection
    
    private func detectErrorPattern(
        for context: ErrorContext
    ) async throws -> ErrorPattern? {
        // Get recent errors for context
        let recentErrors = errorHistory.filter {
            $0.context == context &&
            $0.timestamp > Date().addingTimeInterval(-3600) // Last hour
        }
        
        // Check frequency
        let frequency = Double(recentErrors.count) / 3600.0
        if frequency > 10.0 { // More than 10 errors per hour
            return ErrorPattern(
                type: .highFrequency,
                frequency: frequency,
                timeWindow: 3600
            )
        }
        
        // Check for cascading errors
        let sortedErrors = recentErrors.sorted { $0.timestamp < $1.timestamp }
        if let cascade = detectCascadingErrors(in: sortedErrors) {
            return ErrorPattern(
                type: .cascading,
                frequency: frequency,
                timeWindow: cascade.timeWindow
            )
        }
        
        // Check for cyclic errors
        if let cycle = detectCyclicErrors(in: sortedErrors) {
            return ErrorPattern(
                type: .cyclic,
                frequency: frequency,
                timeWindow: cycle.period
            )
        }
        
        return nil
    }
    
    private func detectCascadingErrors(
        in errors: [ErrorRecord]
    ) -> CascadePattern? {
        guard errors.count >= 3 else { return nil }
        
        var severityIncreasing = true
        for i in 1..<errors.count {
            if errors[i].severity.rawValue <= errors[i-1].severity.rawValue {
                severityIncreasing = false
                break
            }
        }
        
        if severityIncreasing {
            return CascadePattern(
                startTime: errors.first?.timestamp ?? Date(),
                endTime: errors.last?.timestamp ?? Date(),
                severityProgression: errors.map { $0.severity }
            )
        }
        
        return nil
    }
    
    private func detectCyclicErrors(
        in errors: [ErrorRecord]
    ) -> CyclePattern? {
        guard errors.count >= 4 else { return nil }
        
        // Look for repeating patterns in error types
        let errorTypes = errors.map { String(describing: type(of: $0.error)) }
        
        for period in 2...errorTypes.count/2 {
            var isCyclic = true
            let pattern = Array(errorTypes.prefix(period))
            
            for i in stride(from: period, to: errorTypes.count, by: period) {
                let slice = Array(errorTypes[i..<min(i + period, errorTypes.count)])
                if slice != pattern.prefix(slice.count) {
                    isCyclic = false
                    break
                }
            }
            
            if isCyclic {
                return CyclePattern(
                    period: Double(period),
                    pattern: pattern
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Recovery Strategies
    
    private func applyRecoveryStrategy(
        for error: Error,
        context: ErrorContext,
        pattern: ErrorPattern?,
        strategy: ErrorRecoveryStrategy?
    ) async throws -> ErrorResolution {
        // Use provided strategy or determine based on error and pattern
        let recoveryStrategy = strategy ?? determineRecoveryStrategy(
            for: error,
            context: context,
            pattern: pattern
        )
        
        switch recoveryStrategy {
        case .retry(let delay):
            return try await handleRetry(
                error: error,
                context: context,
                delay: delay
            )
            
        case .rollback(let checkpoint):
            return try await handleRollback(
                to: checkpoint,
                context: context
            )
            
        case .fallback(let alternative):
            return try await handleFallback(
                to: alternative,
                context: context
            )
            
        case .escalate:
            return try await handleEscalation(
                error: error,
                context: context
            )
            
        case .ignore:
            return ErrorResolution(
                status: .ignored,
                context: context,
                timestamp: Date()
            )
        }
    }
    
    private func determineRecoveryStrategy(
        for error: Error,
        context: ErrorContext,
        pattern: ErrorPattern?
    ) -> ErrorRecoveryStrategy {
        if let pattern = pattern {
            switch pattern.type {
            case .highFrequency:
                return .escalate
            case .cascading:
                return .rollback(checkpoint: nil)
            case .cyclic:
                return .fallback(alternative: nil)
            }
        }
        
        // Default strategies based on error type
        switch error {
        case is NetworkError:
            return .retry(delay: 5.0)
        case is PersistenceError:
            return .rollback(checkpoint: nil)
        case is ValidationError:
            return .fallback(alternative: nil)
        default:
            return .escalate
        }
    }
    
    private func handleRetry(
        error: Error,
        context: ErrorContext,
        delay: TimeInterval
    ) async throws -> ErrorResolution {
        let retryCount = errorHistory.filter {
            $0.context == context &&
            $0.timestamp > Date().addingTimeInterval(-300) // Last 5 minutes
        }.count
        
        guard retryCount < retryLimit else {
            return ErrorResolution(
                status: .failed,
                context: context,
                timestamp: Date(),
                message: "Retry limit exceeded"
            )
        }
        
        // Wait for specified delay
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        // Attempt recovery
        do {
            try await recovery.recoverFromError(error, context: context)
            return ErrorResolution(
                status: .resolved,
                context: context,
                timestamp: Date()
            )
        } catch {
            return ErrorResolution(
                status: .failed,
                context: context,
                timestamp: Date(),
                message: "Retry failed: \(error.localizedDescription)"
            )
        }
    }
    
    private func handleRollback(
        to checkpoint: Checkpoint?,
        context: ErrorContext
    ) async throws -> ErrorResolution {
        do {
            try await recovery.rollbackToCheckpoint(checkpoint)
            return ErrorResolution(
                status: .resolved,
                context: context,
                timestamp: Date()
            )
        } catch {
            return ErrorResolution(
                status: .failed,
                context: context,
                timestamp: Date(),
                message: "Rollback failed: \(error.localizedDescription)"
            )
        }
    }
    
    private func handleFallback(
        to alternative: Any?,
        context: ErrorContext
    ) async throws -> ErrorResolution {
        do {
            try await recovery.switchToFallback(alternative)
            return ErrorResolution(
                status: .resolved,
                context: context,
                timestamp: Date()
            )
        } catch {
            return ErrorResolution(
                status: .failed,
                context: context,
                timestamp: Date(),
                message: "Fallback failed: \(error.localizedDescription)"
            )
        }
    }
    
    private func handleEscalation(
        error: Error,
        context: ErrorContext
    ) async throws -> ErrorResolution {
        // Log critical error
        logger.critical("Error escalated: \(error.localizedDescription)")
        
        // Notify monitoring system
        await monitor.reportCriticalError(error, context: context)
        
        return ErrorResolution(
            status: .escalated,
            context: context,
            timestamp: Date()
        )
    }
    
    // MARK: - Error Recording
    
    private func recordError(_ record: ErrorRecord) async throws {
        errorHistory.append(record)
        
        // Trim history if needed
        if errorHistory.count > maxHistorySize {
            errorHistory = Array(errorHistory.suffix(maxHistorySize))
        }
        
        // Persist error record
        try await persistence.saveErrorRecord(record)
    }
    
    // MARK: - Metrics
    
    private func updateErrorMetrics(resolution: ErrorResolution) async {
        await monitor.updateErrorMetrics(resolution: resolution)
    }
    
    // MARK: - Logging
    
    private func logError(
        _ error: Error,
        context: ErrorContext,
        severity: ErrorSeverity
    ) {
        switch severity {
        case .critical:
            logger.critical("\(context.rawValue): \(error.localizedDescription)")
        case .error:
            logger.error("\(context.rawValue): \(error.localizedDescription)")
        case .warning:
            logger.warning("\(context.rawValue): \(error.localizedDescription)")
        case .info:
            logger.info("\(context.rawValue): \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types

struct ErrorRecord: Codable {
    let error: Error
    let context: ErrorContext
    let severity: ErrorSeverity
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case error
        case context
        case severity
        case timestamp
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(describing: error), forKey: .error)
        try container.encode(context, forKey: .context)
        try container.encode(severity, forKey: .severity)
        try container.encode(timestamp, forKey: .timestamp)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let errorString = try container.decode(String.self, forKey: .error)
        error = NSError(domain: "ErrorRecord", code: -1, userInfo: [NSLocalizedDescriptionKey: errorString])
        context = try container.decode(ErrorContext.self, forKey: .context)
        severity = try container.decode(ErrorSeverity.self, forKey: .severity)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
    
    init(error: Error, context: ErrorContext, severity: ErrorSeverity, timestamp: Date) {
        self.error = error
        self.context = context
        self.severity = severity
        self.timestamp = timestamp
    }
}

enum ErrorContext: String, Codable {
    case storage
    case transfer
    case cost
    case validation
    case compression
    case migration
    case export
}

enum ErrorSeverity: Int, Codable {
    case info = 0
    case warning = 1
    case error = 2
    case critical = 3
}

enum ErrorRecoveryStrategy {
    case retry(delay: TimeInterval)
    case rollback(checkpoint: Checkpoint?)
    case fallback(alternative: Any?)
    case escalate
    case ignore
}

struct ErrorResolution: Codable {
    let status: ResolutionStatus
    let context: ErrorContext
    let timestamp: Date
    let message: String?
    
    enum ResolutionStatus: String, Codable {
        case resolved
        case failed
        case escalated
        case ignored
    }
}

struct ErrorPattern {
    let type: PatternType
    let frequency: Double
    let timeWindow: TimeInterval
    
    enum PatternType {
        case highFrequency
        case cascading
        case cyclic
    }
}

struct CascadePattern {
    let startTime: Date
    let endTime: Date
    let severityProgression: [ErrorSeverity]
    
    var timeWindow: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

struct CyclePattern {
    let period: Double
    let pattern: [String]
}

enum ErrorHandlingError: Error {
    case handlingFailed(error: Error)
    case invalidRecoveryStrategy
    case recoveryFailed
    case patternDetectionFailed
}
