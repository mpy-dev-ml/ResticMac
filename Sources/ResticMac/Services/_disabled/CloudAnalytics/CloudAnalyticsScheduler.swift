import Foundation
import OSLog
import BackgroundTasks

actor CloudAnalyticsScheduler {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsScheduler")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    private let notifications: CloudAnalyticsNotifications
    
    init(
        persistence: CloudAnalyticsPersistence,
        monitor: CloudAnalyticsMonitor,
        notifications: CloudAnalyticsNotifications
    ) {
        self.persistence = persistence
        self.monitor = monitor
        self.notifications = notifications
    }
    
    // MARK: - Schedule Management
    
    func createSchedule(
        _ schedule: AnalyticsSchedule,
        for repository: Repository
    ) async throws {
        let tracker = await monitor.trackOperation("create_schedule")
        defer { tracker.stop() }
        
        do {
            // Validate schedule
            try validateSchedule(schedule)
            
            // Save schedule
            try await persistence.saveSchedule(schedule, for: repository)
            
            // Schedule next run
            try await scheduleNextRun(schedule, for: repository)
            
            // Schedule notification
            try await scheduleNotification(for: schedule, repository: repository)
            
            logger.info("Created schedule for repository: \(repository.path.lastPathComponent)")
            
        } catch {
            logger.error("Failed to create schedule: \(error.localizedDescription)")
            throw SchedulerError.creationFailed(error: error)
        }
    }
    
    func updateSchedule(
        _ schedule: AnalyticsSchedule,
        for repository: Repository
    ) async throws {
        let tracker = await monitor.trackOperation("update_schedule")
        defer { tracker.stop() }
        
        do {
            // Validate schedule
            try validateSchedule(schedule)
            
            // Update schedule
            try await persistence.updateSchedule(schedule, for: repository)
            
            // Reschedule next run
            try await rescheduleRuns(for: repository)
            
            // Update notification
            try await updateNotification(for: schedule, repository: repository)
            
            logger.info("Updated schedule for repository: \(repository.path.lastPathComponent)")
            
        } catch {
            logger.error("Failed to update schedule: \(error.localizedDescription)")
            throw SchedulerError.updateFailed(error: error)
        }
    }
    
    func deleteSchedule(
        withId id: UUID,
        from repository: Repository
    ) async throws {
        let tracker = await monitor.trackOperation("delete_schedule")
        defer { tracker.stop() }
        
        do {
            // Cancel scheduled runs
            try await cancelScheduledRuns(for: repository)
            
            // Remove schedule
            try await persistence.deleteSchedule(id: id)
            
            // Cancel notification
            try await notifications.cancelNotification(withId: id)
            
            logger.info("Deleted schedule: \(id)")
            
        } catch {
            logger.error("Failed to delete schedule: \(error.localizedDescription)")
            throw SchedulerError.deletionFailed(error: error)
        }
    }
    
    // MARK: - Schedule Execution
    
    func executeSchedule(
        _ schedule: AnalyticsSchedule,
        for repository: Repository
    ) async throws {
        let tracker = await monitor.trackOperation("execute_schedule")
        defer { tracker.stop() }
        
        do {
            // Check conditions
            guard await shouldExecuteSchedule(schedule, for: repository) else {
                logger.info("Skipping schedule execution due to conditions")
                return
            }
            
            // Execute tasks
            try await executeTasks(schedule.tasks, for: repository)
            
            // Update last run time
            try await updateLastRunTime(schedule, for: repository)
            
            // Schedule next run
            try await scheduleNextRun(schedule, for: repository)
            
            logger.info("Successfully executed schedule for repository: \(repository.path.lastPathComponent)")
            
        } catch {
            logger.error("Failed to execute schedule: \(error.localizedDescription)")
            throw SchedulerError.executionFailed(error: error)
        }
    }
    
    // MARK: - Private Methods
    
    private func validateSchedule(_ schedule: AnalyticsSchedule) throws {
        // Validate basic properties
        guard !schedule.tasks.isEmpty else {
            throw SchedulerError.validation("Schedule must have at least one task")
        }
        
        // Validate frequency
        switch schedule.frequency {
        case .interval(let seconds):
            guard seconds >= 300 else { // Minimum 5 minutes
                throw SchedulerError.validation("Interval must be at least 300 seconds")
            }
            
        case .daily(let time):
            guard time >= 0 && time <= 86400 else {
                throw SchedulerError.validation("Daily time must be between 0 and 86400 seconds")
            }
            
        case .weekly(let day, let time):
            guard day >= 1 && day <= 7 else {
                throw SchedulerError.validation("Weekly day must be between 1 and 7")
            }
            guard time >= 0 && time <= 86400 else {
                throw SchedulerError.validation("Weekly time must be between 0 and 86400 seconds")
            }
            
        case .monthly(let day, let time):
            guard day >= 1 && day <= 31 else {
                throw SchedulerError.validation("Monthly day must be between 1 and 31")
            }
            guard time >= 0 && time <= 86400 else {
                throw SchedulerError.validation("Monthly time must be between 0 and 86400 seconds")
            }
        }
        
        // Validate conditions
        if let conditions = schedule.conditions {
            try validateConditions(conditions)
        }
    }
    
    private func validateConditions(_ conditions: ScheduleConditions) throws {
        if let storage = conditions.storage {
            guard storage.threshold > 0 else {
                throw SchedulerError.validation("Storage threshold must be positive")
            }
        }
        
        if let performance = conditions.performance {
            guard performance.cpuThreshold >= 0 && performance.cpuThreshold <= 100 else {
                throw SchedulerError.validation("CPU threshold must be between 0 and 100")
            }
            guard performance.memoryThreshold >= 0 && performance.memoryThreshold <= 100 else {
                throw SchedulerError.validation("Memory threshold must be between 0 and 100")
            }
        }
        
        if let cost = conditions.cost {
            guard cost.threshold > 0 else {
                throw SchedulerError.validation("Cost threshold must be positive")
            }
        }
    }
    
    private func scheduleNextRun(
        _ schedule: AnalyticsSchedule,
        for repository: Repository
    ) async throws {
        let nextRunDate = calculateNextRunDate(for: schedule)
        
        // Create background task request
        let request = BGProcessingTaskRequest(
            identifier: "com.resticmac.analytics.schedule"
        )
        request.earliestBeginDate = nextRunDate
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = schedule.requiresPower
        
        try BGTaskScheduler.shared.submit(request)
    }
    
    private func calculateNextRunDate(
        for schedule: AnalyticsSchedule
    ) -> Date {
        let calendar = Calendar.current
        let now = Date()
        
        switch schedule.frequency {
        case .interval(let seconds):
            return now.addingTimeInterval(TimeInterval(seconds))
            
        case .daily(let time):
            var components = calendar.dateComponents(
                [.year, .month, .day],
                from: now
            )
            components.second = time
            let date = calendar.date(from: components) ?? now
            return date > now ? date : calendar.date(
                byAdding: .day,
                value: 1,
                to: date
            ) ?? now
            
        case .weekly(let day, let time):
            var components = calendar.dateComponents(
                [.yearForWeekOfYear, .weekOfYear],
                from: now
            )
            components.weekday = day
            components.second = time
            let date = calendar.date(from: components) ?? now
            return date > now ? date : calendar.date(
                byAdding: .weekOfYear,
                value: 1,
                to: date
            ) ?? now
            
        case .monthly(let day, let time):
            var components = calendar.dateComponents(
                [.year, .month],
                from: now
            )
            components.day = day
            components.second = time
            let date = calendar.date(from: components) ?? now
            return date > now ? date : calendar.date(
                byAdding: .month,
                value: 1,
                to: date
            ) ?? now
        }
    }
    
    private func shouldExecuteSchedule(
        _ schedule: AnalyticsSchedule,
        for repository: Repository
    ) async -> Bool {
        // Check if conditions are met
        guard let conditions = schedule.conditions else { return true }
        
        // Check storage conditions
        if let storage = conditions.storage {
            let metrics = try? await persistence.getStorageMetrics(for: repository)
            guard let usage = metrics?.usage,
                  usage >= storage.threshold else {
                return false
            }
        }
        
        // Check performance conditions
        if let performance = conditions.performance {
            let metrics = try? await persistence.getPerformanceMetrics(for: repository)
            guard let cpu = metrics?.cpu,
                  cpu >= performance.cpuThreshold,
                  let memory = metrics?.memory,
                  memory >= performance.memoryThreshold else {
                return false
            }
        }
        
        // Check cost conditions
        if let cost = conditions.cost {
            let metrics = try? await persistence.getCostMetrics(for: repository)
            guard let total = metrics?.total,
                  total >= cost.threshold else {
                return false
            }
        }
        
        return true
    }
    
    private func executeTasks(
        _ tasks: [AnalyticsTask],
        for repository: Repository
    ) async throws {
        for task in tasks {
            switch task {
            case .generateReport(let type):
                try await executeReportTask(type, for: repository)
                
            case .exportData(let format):
                try await executeExportTask(format, for: repository)
                
            case .cleanup(let options):
                try await executeCleanupTask(options, for: repository)
                
            case .custom(let handler):
                try await handler(repository)
            }
        }
    }
    
    private func executeReportTask(
        _ type: ReportType,
        for repository: Repository
    ) async throws {
        // Implementation would generate and save report
    }
    
    private func executeExportTask(
        _ format: ExportFormat,
        for repository: Repository
    ) async throws {
        // Implementation would export data
    }
    
    private func executeCleanupTask(
        _ options: CleanupOptions,
        for repository: Repository
    ) async throws {
        // Implementation would perform cleanup
    }
}

// MARK: - Supporting Types

struct AnalyticsSchedule: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let frequency: ScheduleFrequency
    let tasks: [AnalyticsTask]
    let conditions: ScheduleConditions?
    let requiresPower: Bool
    let createdAt: Date
    let updatedAt: Date
    
    init(
        name: String,
        description: String,
        frequency: ScheduleFrequency,
        tasks: [AnalyticsTask],
        conditions: ScheduleConditions? = nil,
        requiresPower: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.frequency = frequency
        self.tasks = tasks
        self.conditions = conditions
        self.requiresPower = requiresPower
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

enum ScheduleFrequency: Codable {
    case interval(Int) // Seconds
    case daily(Int) // Seconds from midnight
    case weekly(Int, Int) // Day (1-7), Seconds from midnight
    case monthly(Int, Int) // Day (1-31), Seconds from midnight
}

enum AnalyticsTask: Codable {
    case generateReport(ReportType)
    case exportData(ExportFormat)
    case cleanup(CleanupOptions)
    case custom((Repository) async throws -> Void)
}

struct ScheduleConditions: Codable {
    var storage: StorageCondition?
    var performance: PerformanceCondition?
    var cost: CostCondition?
    
    struct StorageCondition: Codable {
        let threshold: Double // Percentage
    }
    
    struct PerformanceCondition: Codable {
        let cpuThreshold: Double // Percentage
        let memoryThreshold: Double // Percentage
    }
    
    struct CostCondition: Codable {
        let threshold: Double // Amount
    }
}

struct CleanupOptions: Codable {
    var olderThan: TimeInterval
    var types: Set<DataType>
    
    enum DataType: String, Codable {
        case reports
        case metrics
        case exports
        case logs
    }
}

enum SchedulerError: Error {
    case creationFailed(error: Error)
    case updateFailed(error: Error)
    case deletionFailed(error: Error)
    case executionFailed(error: Error)
    case validation(String)
}
