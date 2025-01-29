import Foundation

enum CloudError: LocalizedError {
    // Authentication Errors
    case invalidCredentials(provider: CloudProvider)
    case expiredCredentials(provider: CloudProvider)
    case insufficientPermissions(provider: CloudProvider, resource: String)
    case mfaRequired(provider: CloudProvider)
    
    // Connection Errors
    case networkTimeout(provider: CloudProvider)
    case connectionLost(provider: CloudProvider)
    case rateLimitExceeded(provider: CloudProvider, resetTime: Date?)
    case endpointUnavailable(provider: CloudProvider, endpoint: String)
    
    // Resource Errors
    case bucketNotFound(provider: CloudProvider, bucket: String)
    case resourceNotFound(provider: CloudProvider, path: String)
    case insufficientStorage(provider: CloudProvider, available: Int64, required: Int64)
    case resourceLocked(provider: CloudProvider, path: String)
    
    // Configuration Errors
    case invalidConfiguration(provider: CloudProvider, reason: String)
    case missingConfiguration(provider: CloudProvider, field: String)
    case unsupportedRegion(provider: CloudProvider, region: String)
    case incompatibleAPIVersion(provider: CloudProvider, current: String, required: String)
    
    // Operation Errors
    case operationTimeout(provider: CloudProvider, operation: String)
    case operationCancelled(provider: CloudProvider, operation: String)
    case concurrencyLimitExceeded(provider: CloudProvider)
    case checksumMismatch(provider: CloudProvider, path: String)
    
    var errorDescription: String? {
        switch self {
        // Authentication Errors
        case .invalidCredentials(let provider):
            return "Invalid credentials for \(provider.displayName)"
        case .expiredCredentials(let provider):
            return "Expired credentials for \(provider.displayName)"
        case .insufficientPermissions(let provider, let resource):
            return "Insufficient permissions to access \(resource) on \(provider.displayName)"
        case .mfaRequired(let provider):
            return "Multi-factor authentication required for \(provider.displayName)"
            
        // Connection Errors
        case .networkTimeout(let provider):
            return "Network timeout whilst connecting to \(provider.displayName)"
        case .connectionLost(let provider):
            return "Lost connection to \(provider.displayName)"
        case .rateLimitExceeded(let provider, let resetTime):
            if let reset = resetTime {
                return "Rate limit exceeded for \(provider.displayName). Reset at \(reset.formatted())"
            }
            return "Rate limit exceeded for \(provider.displayName)"
        case .endpointUnavailable(let provider, let endpoint):
            return "\(provider.displayName) endpoint unavailable: \(endpoint)"
            
        // Resource Errors
        case .bucketNotFound(let provider, let bucket):
            return "Bucket '\(bucket)' not found on \(provider.displayName)"
        case .resourceNotFound(let provider, let path):
            return "Resource '\(path)' not found on \(provider.displayName)"
        case .insufficientStorage(let provider, let available, let required):
            let formatter = ByteCountFormatter()
            return "Insufficient storage on \(provider.displayName). Available: \(formatter.string(fromByteCount: available)), Required: \(formatter.string(fromByteCount: required))"
        case .resourceLocked(let provider, let path):
            return "Resource '\(path)' is locked on \(provider.displayName)"
            
        // Configuration Errors
        case .invalidConfiguration(let provider, let reason):
            return "Invalid configuration for \(provider.displayName): \(reason)"
        case .missingConfiguration(let provider, let field):
            return "Missing configuration for \(provider.displayName): \(field)"
        case .unsupportedRegion(let provider, let region):
            return "Unsupported region '\(region)' for \(provider.displayName)"
        case .incompatibleAPIVersion(let provider, let current, let required):
            return "Incompatible API version for \(provider.displayName). Current: \(current), Required: \(required)"
            
        // Operation Errors
        case .operationTimeout(let provider, let operation):
            return "\(operation) operation timed out on \(provider.displayName)"
        case .operationCancelled(let provider, let operation):
            return "\(operation) operation cancelled on \(provider.displayName)"
        case .concurrencyLimitExceeded(let provider):
            return "Too many concurrent operations on \(provider.displayName)"
        case .checksumMismatch(let provider, let path):
            return "Checksum mismatch for '\(path)' on \(provider.displayName)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        // Authentication Errors
        case .invalidCredentials:
            return "Check your credentials and try again"
        case .expiredCredentials:
            return "Please refresh your credentials and try again"
        case .insufficientPermissions:
            return "Contact your administrator to request necessary permissions"
        case .mfaRequired:
            return "Complete multi-factor authentication to proceed"
            
        // Connection Errors
        case .networkTimeout:
            return "Check your internet connection and try again"
        case .connectionLost:
            return "Check your internet connection and retry the operation"
        case .rateLimitExceeded(_, let resetTime):
            if let reset = resetTime {
                return "Please wait until \(reset.formatted()) before retrying"
            }
            return "Please wait before retrying"
        case .endpointUnavailable:
            return "Check the service status and try again later"
            
        // Resource Errors
        case .bucketNotFound:
            return "Verify the bucket name and your access permissions"
        case .resourceNotFound:
            return "Verify the resource path and your access permissions"
        case .insufficientStorage:
            return "Free up space or choose a different storage location"
        case .resourceLocked:
            return "Wait for the resource to be unlocked and try again"
            
        // Configuration Errors
        case .invalidConfiguration:
            return "Review and correct your configuration settings"
        case .missingConfiguration:
            return "Provide all required configuration settings"
        case .unsupportedRegion:
            return "Choose a supported region for this service"
        case .incompatibleAPIVersion:
            return "Update your client or use a compatible API version"
            
        // Operation Errors
        case .operationTimeout:
            return "Try again with a longer timeout or smaller operation"
        case .operationCancelled:
            return "Restart the operation if needed"
        case .concurrencyLimitExceeded:
            return "Reduce the number of concurrent operations"
        case .checksumMismatch:
            return "Retry the operation to ensure data integrity"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .networkTimeout,
             .connectionLost,
             .rateLimitExceeded,
             .endpointUnavailable,
             .operationTimeout,
             .checksumMismatch:
            return true
        default:
            return false
        }
    }
    
    var shouldNotifyUser: Bool {
        switch self {
        case .invalidCredentials,
             .expiredCredentials,
             .insufficientPermissions,
             .mfaRequired,
             .insufficientStorage,
             .invalidConfiguration,
             .missingConfiguration:
            return true
        default:
            return false
        }
    }
    
    var suggestedRetryDelay: TimeInterval {
        switch self {
        case .networkTimeout:
            return 5.0
        case .connectionLost:
            return 10.0
        case .rateLimitExceeded(_, let resetTime):
            if let reset = resetTime {
                return max(1.0, reset.timeIntervalSinceNow)
            }
            return 60.0
        case .endpointUnavailable:
            return 30.0
        case .operationTimeout:
            return 15.0
        case .checksumMismatch:
            return 1.0
        default:
            return 0.0
        }
    }
}

// MARK: - Error Handling Extensions

extension CloudError {
    static func from(_ error: Error, provider: CloudProvider) -> CloudError {
        // Convert provider-specific errors to CloudError
        switch provider {
        case .s3:
            return handleAWSError(error, provider: provider)
        case .b2:
            return handleB2Error(error, provider: provider)
        case .azure:
            return handleAzureError(error, provider: provider)
        case .gcs:
            return handleGCSError(error, provider: provider)
        case .sftp:
            return handleSFTPError(error, provider: provider)
        case .rest:
            return handleRESTError(error, provider: provider)
        }
    }
    
    private static func handleAWSError(_ error: Error, provider: CloudProvider) -> CloudError {
        // Example AWS error handling
        let nsError = error as NSError
        switch nsError.domain {
        case "com.amazonaws.AWSServiceError":
            switch nsError.code {
            case 401:
                return .invalidCredentials(provider: provider)
            case 403:
                return .insufficientPermissions(provider: provider, resource: nsError.userInfo["resource"] as? String ?? "unknown")
            case 404:
                if let bucket = nsError.userInfo["bucket"] as? String {
                    return .bucketNotFound(provider: provider, bucket: bucket)
                }
                return .resourceNotFound(provider: provider, path: nsError.userInfo["path"] as? String ?? "unknown")
            case 429:
                if let resetTime = nsError.userInfo["resetTime"] as? Date {
                    return .rateLimitExceeded(provider: provider, resetTime: resetTime)
                }
                return .rateLimitExceeded(provider: provider, resetTime: nil)
            default:
                return .invalidConfiguration(provider: provider, reason: error.localizedDescription)
            }
        default:
            return .invalidConfiguration(provider: provider, reason: error.localizedDescription)
        }
    }
    
    private static func handleB2Error(_ error: Error, provider: CloudProvider) -> CloudError {
        // Implement B2-specific error handling
        return .invalidConfiguration(provider: provider, reason: error.localizedDescription)
    }
    
    private static func handleAzureError(_ error: Error, provider: CloudProvider) -> CloudError {
        // Implement Azure-specific error handling
        return .invalidConfiguration(provider: provider, reason: error.localizedDescription)
    }
    
    private static func handleGCSError(_ error: Error, provider: CloudProvider) -> CloudError {
        // Implement GCS-specific error handling
        return .invalidConfiguration(provider: provider, reason: error.localizedDescription)
    }
    
    private static func handleSFTPError(_ error: Error, provider: CloudProvider) -> CloudError {
        // Implement SFTP-specific error handling
        return .invalidConfiguration(provider: provider, reason: error.localizedDescription)
    }
    
    private static func handleRESTError(_ error: Error, provider: CloudProvider) -> CloudError {
        // Implement REST-specific error handling
        return .invalidConfiguration(provider: provider, reason: error.localizedDescription)
    }
}

// MARK: - ResticService Extensions

extension ResticService {
    func handleCloudError(_ error: Error, repository: Repository) async throws {
        guard let provider = repository.cloudProvider else {
            throw error
        }
        
        let cloudError = CloudError.from(error, provider: provider)
        
        // Log the error
        logger.error("Cloud error: \(cloudError.localizedDescription)")
        
        // Handle retryable errors
        if cloudError.isRetryable {
            let delay = cloudError.suggestedRetryDelay
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            // Notify about retry
            NotificationCenter.default.post(
                name: .cloudOperationRetrying,
                object: nil,
                userInfo: [
                    "provider": provider,
                    "error": cloudError,
                    "delay": delay
                ]
            )
        }
        
        // Notify user if needed
        if cloudError.shouldNotifyUser {
            NotificationCenter.default.post(
                name: .cloudErrorOccurred,
                object: nil,
                userInfo: [
                    "provider": provider,
                    "error": cloudError
                ]
            )
        }
        
        throw cloudError
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let cloudErrorOccurred = Notification.Name("CloudErrorOccurred")
    static let cloudOperationRetrying = Notification.Name("CloudOperationRetrying")
}
