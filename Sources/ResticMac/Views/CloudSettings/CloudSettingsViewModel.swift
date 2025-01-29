import Foundation
import SwiftUI
import LocalAuthentication

@MainActor
class CloudSettingsViewModel: ObservableObject {
    private let repository: Repository
    private let cloudOptimizer: CloudOptimizer
    private let byteFormatter = ByteCountFormatter()
    
    // Provider Settings
    @Published var currentProvider: CloudProvider?
    @Published var selectedProvider: CloudProvider?
    @Published var formattedEndpoint = ""
    
    // Connection Settings
    @Published var useCompression = true
    @Published var compressionLevel = CompressionLevel.default
    @Published var maxConcurrentOperations = 4
    @Published var useRateLimiting = false
    @Published var uploadRateLimit: Double = 10.0
    @Published var downloadRateLimit: Double = 10.0
    
    // Security Settings
    @Published var useKeychain = true
    @Published var requireAuthentication = false
    @Published var authMethod = AuthenticationMethod.touchID
    @Published var encryptTransfers = true
    
    // Advanced Settings
    @Published var autoRetry = true
    @Published var maxRetries = 3
    @Published var showNotifications = true
    @Published var allowBackgroundTransfers = true
    
    // Error Handling
    @Published var showError = false
    @Published var errorMessage: String?
    
    init(repository: Repository) {
        self.repository = repository
        self.cloudOptimizer = CloudOptimizer()
        self.byteFormatter.countStyle = .file
        
        Task {
            await loadSettings()
        }
    }
    
    func loadSettings() async {
        do {
            // Load provider configuration
            if let provider = repository.cloudProvider {
                currentProvider = provider
                formattedEndpoint = repository.cloudEndpoint ?? "Default Endpoint"
            }
            
            // Load connection settings
            let settings = try await cloudOptimizer.getSettings()
            useCompression = settings.useCompression
            compressionLevel = CompressionLevel(rawValue: settings.compressionLevel) ?? .default
            maxConcurrentOperations = settings.maxConcurrentOperations
            useRateLimiting = settings.useRateLimiting
            uploadRateLimit = settings.uploadRateLimit
            downloadRateLimit = settings.downloadRateLimit
            
            // Load security settings
            useKeychain = settings.useKeychain
            requireAuthentication = settings.requireAuthentication
            authMethod = AuthenticationMethod(rawValue: settings.authMethod) ?? .touchID
            encryptTransfers = settings.encryptTransfers
            
            // Load advanced settings
            autoRetry = settings.autoRetry
            maxRetries = settings.maxRetries
            showNotifications = settings.showNotifications
            allowBackgroundTransfers = settings.allowBackgroundTransfers
            
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
    
    func saveSettings() async {
        do {
            let settings = CloudSettings(
                useCompression: useCompression,
                compressionLevel: compressionLevel.rawValue,
                maxConcurrentOperations: maxConcurrentOperations,
                useRateLimiting: useRateLimiting,
                uploadRateLimit: uploadRateLimit,
                downloadRateLimit: downloadRateLimit,
                useKeychain: useKeychain,
                requireAuthentication: requireAuthentication,
                authMethod: authMethod.rawValue,
                encryptTransfers: encryptTransfers,
                autoRetry: autoRetry,
                maxRetries: maxRetries,
                showNotifications: showNotifications,
                allowBackgroundTransfers: allowBackgroundTransfers
            )
            
            try await cloudOptimizer.saveSettings(settings)
            
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
    
    func testConnection(
        endpoint: String,
        accessKey: String,
        secretKey: String,
        region: String,
        bucket: String
    ) async {
        do {
            guard let provider = selectedProvider ?? currentProvider else {
                throw CloudError.invalidConfiguration(provider: .s3, reason: "No provider selected")
            }
            
            let credentials = CloudCredentials(
                endpoint: endpoint,
                accessKey: accessKey,
                secretKey: secretKey,
                region: region,
                bucket: bucket
            )
            
            try await cloudOptimizer.testConnection(provider: provider, credentials: credentials)
            
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
    
    func saveProviderConfiguration(
        endpoint: String,
        accessKey: String,
        secretKey: String,
        region: String,
        bucket: String
    ) async {
        do {
            guard let provider = selectedProvider ?? currentProvider else {
                throw CloudError.invalidConfiguration(provider: .s3, reason: "No provider selected")
            }
            
            let credentials = CloudCredentials(
                endpoint: endpoint,
                accessKey: accessKey,
                secretKey: secretKey,
                region: region,
                bucket: bucket
            )
            
            try await cloudOptimizer.saveCredentials(provider: provider, credentials: credentials)
            currentProvider = provider
            formattedEndpoint = endpoint
            
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
    
    func removeProvider() async {
        do {
            try await cloudOptimizer.removeCredentials(provider: currentProvider ?? .s3)
            currentProvider = nil
            formattedEndpoint = ""
            
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
    
    func clearCache() async {
        do {
            try await cloudOptimizer.clearCache()
            
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }
    }
    
    var formattedCacheSize: String {
        // Implementation would get actual cache size
        return byteFormatter.string(fromByteCount: 1024 * 1024 * 100) // Placeholder 100MB
    }
}

// MARK: - Supporting Types

struct CloudSettings {
    let useCompression: Bool
    let compressionLevel: Int
    let maxConcurrentOperations: Int
    let useRateLimiting: Bool
    let uploadRateLimit: Double
    let downloadRateLimit: Double
    let useKeychain: Bool
    let requireAuthentication: Bool
    let authMethod: String
    let encryptTransfers: Bool
    let autoRetry: Bool
    let maxRetries: Int
    let showNotifications: Bool
    let allowBackgroundTransfers: Bool
}

struct CloudCredentials {
    let endpoint: String
    let accessKey: String
    let secretKey: String
    let region: String
    let bucket: String
}

// MARK: - CloudProvider Extensions

extension CloudProvider {
    var iconName: String {
        switch self {
        case .s3: return "cloud.fill"
        case .b2: return "externaldrive.fill.badge.plus"
        case .azure: return "cloud.fill"
        case .gcs: return "cloud.fill"
        case .sftp: return "network"
        case .rest: return "network"
        }
    }
    
    var color: Color {
        switch self {
        case .s3: return .orange
        case .b2: return .red
        case .azure: return .blue
        case .gcs: return .green
        case .sftp: return .purple
        case .rest: return .gray
        }
    }
    
    var description: String {
        switch self {
        case .s3: return "Amazon S3 compatible storage"
        case .b2: return "Backblaze B2 Cloud Storage"
        case .azure: return "Microsoft Azure Blob Storage"
        case .gcs: return "Google Cloud Storage"
        case .sftp: return "SFTP/SSH File Transfer"
        case .rest: return "REST Server"
        }
    }
}
