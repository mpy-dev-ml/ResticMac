import Foundation
import UserNotifications
import SwiftUI
import OSLog

actor CloudAnalyticsNotifications {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsNotifications")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    private let center = UNUserNotificationCenter.current()
    
    init(persistence: CloudAnalyticsPersistence, monitor: CloudAnalyticsMonitor) {
        self.persistence = persistence
        self.monitor = monitor
    }
    
    // MARK: - Notification Management
    
    func setupNotifications() async throws {
        let tracker = await monitor.trackOperation("setup_notifications")
        defer { tracker.stop() }
        
        do {
            // Request authorization
            try await requestAuthorization()
            
            // Register notification categories
            registerNotificationCategories()
            
            // Setup default preferences
            try await setupDefaultPreferences()
            
            logger.info("Notifications setup completed")
            
        } catch {
            logger.error("Failed to setup notifications: \(error.localizedDescription)")
            throw NotificationError.setupFailed(error: error)
        }
    }
    
    func updatePreferences(
        _ preferences: NotificationPreferences,
        for repository: Repository
    ) async throws {
        let tracker = await monitor.trackOperation("update_preferences")
        defer { tracker.stop() }
        
        do {
            // Validate preferences
            try validatePreferences(preferences)
            
            // Save preferences
            try await persistence.saveNotificationPreferences(
                preferences,
                for: repository
            )
            
            // Update scheduled notifications
            try await updateScheduledNotifications(
                for: repository,
                with: preferences
            )
            
            logger.info("Updated notification preferences for repository: \(repository.path.lastPathComponent)")
            
        } catch {
            logger.error("Failed to update preferences: \(error.localizedDescription)")
            throw NotificationError.updateFailed(error: error)
        }
    }
    
    // MARK: - Notification Scheduling
    
    func scheduleNotification(
        _ notification: AnalyticsNotification,
        for repository: Repository
    ) async throws {
        let tracker = await monitor.trackOperation("schedule_notification")
        defer { tracker.stop() }
        
        do {
            // Get preferences
            let preferences = try await persistence.getNotificationPreferences(for: repository)
            
            // Check if notification is enabled
            guard isNotificationEnabled(notification, in: preferences) else {
                logger.info("Notification type disabled: \(notification.type)")
                return
            }
            
            // Create notification content
            let content = try createNotificationContent(
                from: notification,
                preferences: preferences
            )
            
            // Create trigger
            let trigger = createNotificationTrigger(
                from: notification,
                preferences: preferences
            )
            
            // Schedule notification
            let request = UNNotificationRequest(
                identifier: notification.id.uuidString,
                content: content,
                trigger: trigger
            )
            
            try await center.add(request)
            
            logger.info("Scheduled notification: \(notification.id)")
            
        } catch {
            logger.error("Failed to schedule notification: \(error.localizedDescription)")
            throw NotificationError.schedulingFailed(error: error)
        }
    }
    
    func cancelNotification(withId id: UUID) async throws {
        let tracker = await monitor.trackOperation("cancel_notification")
        defer { tracker.stop() }
        
        center.removePendingNotificationRequests(
            withIdentifiers: [id.uuidString]
        )
        
        logger.info("Cancelled notification: \(id)")
    }
    
    // MARK: - Notification Handling
    
    func handleNotificationResponse(
        _ response: UNNotificationResponse
    ) async throws {
        let tracker = await monitor.trackOperation("handle_notification")
        defer { tracker.stop() }
        
        do {
            // Extract notification data
            guard let notification = try extractNotification(from: response) else {
                throw NotificationError.invalidNotification
            }
            
            // Handle action
            switch response.actionIdentifier {
            case UNNotificationDefaultActionIdentifier:
                try await handleDefaultAction(for: notification)
                
            case NotificationAction.view.rawValue:
                try await handleViewAction(for: notification)
                
            case NotificationAction.snooze.rawValue:
                try await handleSnoozeAction(for: notification)
                
            case NotificationAction.dismiss.rawValue:
                try await handleDismissAction(for: notification)
                
            default:
                logger.warning("Unknown action identifier: \(response.actionIdentifier)")
            }
            
            logger.info("Handled notification response: \(notification.id)")
            
        } catch {
            logger.error("Failed to handle notification: \(error.localizedDescription)")
            throw NotificationError.handlingFailed(error: error)
        }
    }
    
    // MARK: - Private Methods
    
    private func requestAuthorization() async throws {
        let options: UNAuthorizationOptions = [
            .alert,
            .sound,
            .badge,
            .provisional
        ]
        
        let granted = try await center.requestAuthorization(options: options)
        
        if granted {
            logger.info("Notification authorization granted")
        } else {
            logger.warning("Notification authorization denied")
        }
    }
    
    private func registerNotificationCategories() {
        // Create alert category
        let alertCategory = UNNotificationCategory(
            identifier: NotificationCategory.alert.rawValue,
            actions: [
                UNNotificationAction(
                    identifier: NotificationAction.view.rawValue,
                    title: "View",
                    options: .foreground
                ),
                UNNotificationAction(
                    identifier: NotificationAction.snooze.rawValue,
                    title: "Snooze",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        // Create report category
        let reportCategory = UNNotificationCategory(
            identifier: NotificationCategory.report.rawValue,
            actions: [
                UNNotificationAction(
                    identifier: NotificationAction.view.rawValue,
                    title: "View Report",
                    options: .foreground
                ),
                UNNotificationAction(
                    identifier: NotificationAction.dismiss.rawValue,
                    title: "Dismiss",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        // Register categories
        center.setNotificationCategories([
            alertCategory,
            reportCategory
        ])
    }
    
    private func setupDefaultPreferences() async throws {
        let defaults = NotificationPreferences(
            enabled: true,
            alerts: AlertPreferences(
                storageThreshold: true,
                performanceIssues: true,
                costSpikes: true,
                errorPatterns: true
            ),
            reports: ReportPreferences(
                daily: false,
                weekly: true,
                monthly: true,
                quarterly: false
            ),
            delivery: DeliveryPreferences(
                email: true,
                push: true,
                quiet: false,
                quietHours: QuietHours(
                    start: Calendar.current.date(
                        from: DateComponents(hour: 22)
                    ) ?? Date(),
                    end: Calendar.current.date(
                        from: DateComponents(hour: 8)
                    ) ?? Date()
                )
            )
        )
        
        try await persistence.saveDefaultNotificationPreferences(defaults)
    }
    
    private func validatePreferences(_ preferences: NotificationPreferences) throws {
        // Validate quiet hours
        if let quietHours = preferences.delivery.quietHours {
            guard quietHours.start < quietHours.end else {
                throw NotificationError.validation("Quiet hours start must be before end")
            }
        }
        
        // Validate thresholds
        if let alerts = preferences.alerts {
            if alerts.storageThreshold {
                guard alerts.storageThresholdValue > 0 else {
                    throw NotificationError.validation("Storage threshold must be positive")
                }
            }
            
            if alerts.costSpikes {
                guard alerts.costSpikeThreshold > 0 else {
                    throw NotificationError.validation("Cost spike threshold must be positive")
                }
            }
        }
    }
    
    private func createNotificationContent(
        from notification: AnalyticsNotification,
        preferences: NotificationPreferences
    ) throws -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        
        // Set basic properties
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        
        // Set category
        content.categoryIdentifier = notification.category.rawValue
        
        // Add user info
        content.userInfo = [
            "id": notification.id.uuidString,
            "type": notification.type.rawValue,
            "repository": notification.repository.path.lastPathComponent
        ]
        
        // Set thread identifier for grouping
        content.threadIdentifier = notification.repository.path.lastPathComponent
        
        // Set interruption level
        if preferences.delivery.quiet {
            content.interruptionLevel = .passive
        } else {
            content.interruptionLevel = .active
        }
        
        return content
    }
    
    private func createNotificationTrigger(
        from notification: AnalyticsNotification,
        preferences: NotificationPreferences
    ) -> UNNotificationTrigger {
        switch notification.trigger {
        case .immediate:
            return UNTimeIntervalNotificationTrigger(
                timeInterval: 1,
                repeats: false
            )
            
        case .scheduled(let date):
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: date
            )
            return UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
            
        case .recurring(let interval):
            return UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: true
            )
        }
    }
    
    private func isNotificationEnabled(
        _ notification: AnalyticsNotification,
        in preferences: NotificationPreferences
    ) -> Bool {
        guard preferences.enabled else { return false }
        
        switch notification.type {
        case .storageAlert:
            return preferences.alerts?.storageThreshold ?? false
        case .performanceAlert:
            return preferences.alerts?.performanceIssues ?? false
        case .costAlert:
            return preferences.alerts?.costSpikes ?? false
        case .errorAlert:
            return preferences.alerts?.errorPatterns ?? false
        case .dailyReport:
            return preferences.reports?.daily ?? false
        case .weeklyReport:
            return preferences.reports?.weekly ?? false
        case .monthlyReport:
            return preferences.reports?.monthly ?? false
        case .quarterlyReport:
            return preferences.reports?.quarterly ?? false
        }
    }
    
    private func extractNotification(
        from response: UNNotificationResponse
    ) throws -> AnalyticsNotification? {
        guard let id = UUID(uuidString: response.notification.request.identifier) else {
            return nil
        }
        
        // Implementation would reconstruct notification from persistence
        return nil
    }
    
    private func handleDefaultAction(
        for notification: AnalyticsNotification
    ) async throws {
        // Implementation would handle default action
    }
    
    private func handleViewAction(
        for notification: AnalyticsNotification
    ) async throws {
        // Implementation would handle view action
    }
    
    private func handleSnoozeAction(
        for notification: AnalyticsNotification
    ) async throws {
        // Implementation would handle snooze action
    }
    
    private func handleDismissAction(
        for notification: AnalyticsNotification
    ) async throws {
        // Implementation would handle dismiss action
    }
}

// MARK: - Supporting Types

struct NotificationPreferences: Codable {
    var enabled: Bool
    var alerts: AlertPreferences?
    var reports: ReportPreferences?
    var delivery: DeliveryPreferences
    
    struct AlertPreferences: Codable {
        var storageThreshold: Bool
        var storageThresholdValue: Double?
        var performanceIssues: Bool
        var costSpikes: Bool
        var costSpikeThreshold: Double?
        var errorPatterns: Bool
    }
    
    struct ReportPreferences: Codable {
        var daily: Bool
        var weekly: Bool
        var monthly: Bool
        var quarterly: Bool
    }
    
    struct DeliveryPreferences: Codable {
        var email: Bool
        var push: Bool
        var quiet: Bool
        var quietHours: QuietHours?
    }
}

struct QuietHours: Codable {
    let start: Date
    let end: Date
}

struct AnalyticsNotification: Identifiable {
    let id: UUID
    let type: NotificationType
    let category: NotificationCategory
    let title: String
    let body: String
    let repository: Repository
    let trigger: NotificationTrigger
    let metadata: [String: Any]
    let createdAt: Date
}

enum NotificationType: String {
    case storageAlert
    case performanceAlert
    case costAlert
    case errorAlert
    case dailyReport
    case weeklyReport
    case monthlyReport
    case quarterlyReport
}

enum NotificationCategory: String {
    case alert
    case report
}

enum NotificationAction: String {
    case view
    case snooze
    case dismiss
}

enum NotificationTrigger {
    case immediate
    case scheduled(Date)
    case recurring(TimeInterval)
}

enum NotificationError: Error {
    case setupFailed(error: Error)
    case updateFailed(error: Error)
    case schedulingFailed(error: Error)
    case handlingFailed(error: Error)
    case invalidNotification
    case validation(String)
}
