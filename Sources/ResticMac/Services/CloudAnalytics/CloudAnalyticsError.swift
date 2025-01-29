import Foundation

enum CloudAnalyticsError: LocalizedError {
    // Data Collection Errors
    case repositoryUnavailable(path: String)
    case invalidMetrics(reason: String)
    case dataCollectionFailed(reason: String)
    case inconsistentData(details: String)
    
    // Storage Errors
    case persistenceFailed(reason: String)
    case dataCorruption(path: String)
    case storageQuotaExceeded(required: Int64, available: Int64)
    case cacheMiss(key: String)
    
    // Import/Export Errors
    case invalidFileFormat(details: String)
    case incompatibleVersion(found: String, required: String)
    case validationFailed(reason: String)
    case conversionFailed(from: String, to: String)
    
    // Analysis Errors
    case insufficientData(required: Int, found: Int)
    case invalidTimeRange(reason: String)
    case trendAnalysisFailed(reason: String)
    case outlierDetectionFailed(reason: String)
    
    // Recovery Actions
    case recoveryFailed(action: RecoveryAction, reason: String)
    case partialRecovery(succeeded: Int, failed: Int)
    case manualInterventionRequired(instructions: String)
    
    var errorDescription: String? {
        switch self {
        case .repositoryUnavailable(let path):
            return "Repository is unavailable at path: \(path)"
        case .invalidMetrics(let reason):
            return "Invalid metrics data: \(reason)"
        case .dataCollectionFailed(let reason):
            return "Failed to collect analytics data: \(reason)"
        case .inconsistentData(let details):
            return "Inconsistent data detected: \(details)"
        case .persistenceFailed(let reason):
            return "Failed to persist analytics data: \(reason)"
        case .dataCorruption(let path):
            return "Data corruption detected at: \(path)"
        case .storageQuotaExceeded(let required, let available):
            return "Storage quota exceeded. Required: \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), Available: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))"
        case .cacheMiss(let key):
            return "Cache miss for key: \(key)"
        case .invalidFileFormat(let details):
            return "Invalid file format: \(details)"
        case .incompatibleVersion(let found, let required):
            return "Incompatible version. Found: \(found), Required: \(required)"
        case .validationFailed(let reason):
            return "Data validation failed: \(reason)"
        case .conversionFailed(let from, let to):
            return "Data conversion failed from \(from) to \(to)"
        case .insufficientData(let required, let found):
            return "Insufficient data for analysis. Required: \(required), Found: \(found)"
        case .invalidTimeRange(let reason):
            return "Invalid time range: \(reason)"
        case .trendAnalysisFailed(let reason):
            return "Trend analysis failed: \(reason)"
        case .outlierDetectionFailed(let reason):
            return "Outlier detection failed: \(reason)"
        case .recoveryFailed(let action, let reason):
            return "Recovery failed for action '\(action.description)': \(reason)"
        case .partialRecovery(let succeeded, let failed):
            return "Partial recovery completed. Succeeded: \(succeeded), Failed: \(failed)"
        case .manualInterventionRequired(let instructions):
            return "Manual intervention required: \(instructions)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .repositoryUnavailable:
            return "Check if the repository path is correct and accessible. Ensure you have appropriate permissions."
        case .invalidMetrics:
            return "Try refreshing the analytics data. If the issue persists, consider resetting the metrics collection."
        case .dataCollectionFailed:
            return "Verify network connectivity and repository access. Try collecting data for a smaller time range."
        case .inconsistentData:
            return "Run data validation and repair. Consider importing from a backup if available."
        case .persistenceFailed:
            return "Check available disk space and file permissions. Try clearing the analytics cache."
        case .dataCorruption:
            return "Run data repair tools. If unsuccessful, restore from the last known good backup."
        case .storageQuotaExceeded:
            return "Free up space by removing old analytics data or increase the storage quota."
        case .cacheMiss:
            return "Rebuild the analytics cache. This may take a few minutes."
        case .invalidFileFormat:
            return "Ensure the file follows the required format. Check the documentation for format specifications."
        case .incompatibleVersion:
            return "Update the analytics data to the current version using the migration tool."
        case .validationFailed:
            return "Review the data against the validation rules. Correct any inconsistencies and try again."
        case .conversionFailed:
            return "Verify the source data format and try converting in smaller batches."
        case .insufficientData:
            return "Collect more data or try analysis with a larger time range."
        case .invalidTimeRange:
            return "Adjust the time range to ensure it contains valid data points."
        case .trendAnalysisFailed:
            return "Try analysis with different parameters or a larger dataset."
        case .outlierDetectionFailed:
            return "Adjust sensitivity parameters or manually review the data points."
        case .recoveryFailed:
            return "Review the recovery logs and try again with different recovery options."
        case .partialRecovery:
            return "Review failed items and retry recovery for those specific items."
        case .manualInterventionRequired:
            return "Follow the provided instructions carefully. Contact support if needed."
        }
    }
    
    var recoveryOptions: [RecoveryOption] {
        switch self {
        case .repositoryUnavailable:
            return [
                .retryConnection,
                .checkPermissions,
                .selectAlternateRepository
            ]
        case .invalidMetrics:
            return [
                .validateData,
                .resetMetrics,
                .importFromBackup
            ]
        case .dataCollectionFailed:
            return [
                .retryCollection,
                .reduceSampleSize,
                .useOfflineData
            ]
        case .inconsistentData:
            return [
                .repairData,
                .restoreFromBackup,
                .resetAndRecollect
            ]
        case .persistenceFailed:
            return [
                .clearCache,
                .checkStorage,
                .compactDatabase
            ]
        case .dataCorruption:
            return [
                .runRepair,
                .restoreFromBackup,
                .resetData
            ]
        default:
            return [.contactSupport]
        }
    }
}

enum RecoveryAction: CustomStringConvertible {
    case retryOperation
    case validateData
    case repairData
    case clearCache
    case restoreBackup
    case migrateData
    case resetMetrics
    
    var description: String {
        switch self {
        case .retryOperation: return "Retry Operation"
        case .validateData: return "Validate Data"
        case .repairData: return "Repair Data"
        case .clearCache: return "Clear Cache"
        case .restoreBackup: return "Restore Backup"
        case .migrateData: return "Migrate Data"
        case .resetMetrics: return "Reset Metrics"
        }
    }
}

struct RecoveryOption: Identifiable {
    let id = UUID()
    let title: String
    let action: () async throws -> Void
    let requirements: [String]
    let estimatedTime: TimeInterval
    let isDestructive: Bool
    
    static let retryConnection = RecoveryOption(
        title: "Retry Connection",
        action: { /* Implementation */ },
        requirements: ["Network access", "Valid credentials"],
        estimatedTime: 30,
        isDestructive: false
    )
    
    static let checkPermissions = RecoveryOption(
        title: "Check Permissions",
        action: { /* Implementation */ },
        requirements: ["Administrator access"],
        estimatedTime: 60,
        isDestructive: false
    )
    
    static let selectAlternateRepository = RecoveryOption(
        title: "Select Alternate Repository",
        action: { /* Implementation */ },
        requirements: ["Available repository"],
        estimatedTime: 120,
        isDestructive: false
    )
    
    static let validateData = RecoveryOption(
        title: "Validate Data",
        action: { /* Implementation */ },
        requirements: ["Read access"],
        estimatedTime: 300,
        isDestructive: false
    )
    
    static let resetMetrics = RecoveryOption(
        title: "Reset Metrics",
        action: { /* Implementation */ },
        requirements: ["Write access"],
        estimatedTime: 60,
        isDestructive: true
    )
    
    static let importFromBackup = RecoveryOption(
        title: "Import from Backup",
        action: { /* Implementation */ },
        requirements: ["Backup file", "Write access"],
        estimatedTime: 600,
        isDestructive: false
    )
    
    static let retryCollection = RecoveryOption(
        title: "Retry Collection",
        action: { /* Implementation */ },
        requirements: ["Network access"],
        estimatedTime: 180,
        isDestructive: false
    )
    
    static let reduceSampleSize = RecoveryOption(
        title: "Reduce Sample Size",
        action: { /* Implementation */ },
        requirements: ["None"],
        estimatedTime: 30,
        isDestructive: false
    )
    
    static let useOfflineData = RecoveryOption(
        title: "Use Offline Data",
        action: { /* Implementation */ },
        requirements: ["Cached data"],
        estimatedTime: 30,
        isDestructive: false
    )
    
    static let repairData = RecoveryOption(
        title: "Repair Data",
        action: { /* Implementation */ },
        requirements: ["Write access"],
        estimatedTime: 900,
        isDestructive: false
    )
    
    static let restoreFromBackup = RecoveryOption(
        title: "Restore from Backup",
        action: { /* Implementation */ },
        requirements: ["Backup file", "Write access"],
        estimatedTime: 600,
        isDestructive: true
    )
    
    static let resetAndRecollect = RecoveryOption(
        title: "Reset and Recollect",
        action: { /* Implementation */ },
        requirements: ["Network access", "Write access"],
        estimatedTime: 1800,
        isDestructive: true
    )
    
    static let clearCache = RecoveryOption(
        title: "Clear Cache",
        action: { /* Implementation */ },
        requirements: ["Write access"],
        estimatedTime: 30,
        isDestructive: true
    )
    
    static let checkStorage = RecoveryOption(
        title: "Check Storage",
        action: { /* Implementation */ },
        requirements: ["Read access"],
        estimatedTime: 60,
        isDestructive: false
    )
    
    static let compactDatabase = RecoveryOption(
        title: "Compact Database",
        action: { /* Implementation */ },
        requirements: ["Write access"],
        estimatedTime: 300,
        isDestructive: false
    )
    
    static let runRepair = RecoveryOption(
        title: "Run Repair",
        action: { /* Implementation */ },
        requirements: ["Write access"],
        estimatedTime: 600,
        isDestructive: false
    )
    
    static let resetData = RecoveryOption(
        title: "Reset Data",
        action: { /* Implementation */ },
        requirements: ["Write access"],
        estimatedTime: 60,
        isDestructive: true
    )
    
    static let contactSupport = RecoveryOption(
        title: "Contact Support",
        action: { /* Implementation */ },
        requirements: ["Active support subscription"],
        estimatedTime: 3600,
        isDestructive: false
    )
}
