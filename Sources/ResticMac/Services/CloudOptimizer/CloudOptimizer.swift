import Foundation
import Network
import os.log

actor CloudOptimizer {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudOptimizer")
    private var connectionMonitor: NWPathMonitor?
    private var optimizationSettings: [CloudProvider: ProviderSettings] = [:]
    private var activeTransfers: [String: TransferState] = [:]
    
    struct ProviderSettings {
        var maxConcurrentOperations: Int
        var chunkSize: Int64
        var retryAttempts: Int
        var retryDelay: TimeInterval
        var compressionLevel: Int
        var bandwidthLimit: Int64?  // bytes per second
        var timeoutInterval: TimeInterval
        
        static func defaultSettings(for provider: CloudProvider) -> ProviderSettings {
            switch provider {
            case .s3:
                return ProviderSettings(
                    maxConcurrentOperations: 4,
                    chunkSize: 20 * 1024 * 1024,  // 20MB
                    retryAttempts: 3,
                    retryDelay: 2.0,
                    compressionLevel: 6,
                    bandwidthLimit: nil,
                    timeoutInterval: 30.0
                )
            case .b2:
                return ProviderSettings(
                    maxConcurrentOperations: 3,
                    chunkSize: 100 * 1024 * 1024,  // 100MB (B2 prefers larger chunks)
                    retryAttempts: 5,
                    retryDelay: 1.0,
                    compressionLevel: 6,
                    bandwidthLimit: nil,
                    timeoutInterval: 60.0
                )
            case .azure:
                return ProviderSettings(
                    maxConcurrentOperations: 4,
                    chunkSize: 16 * 1024 * 1024,  // 16MB
                    retryAttempts: 3,
                    retryDelay: 2.0,
                    compressionLevel: 6,
                    bandwidthLimit: nil,
                    timeoutInterval: 30.0
                )
            case .gcs:
                return ProviderSettings(
                    maxConcurrentOperations: 4,
                    chunkSize: 16 * 1024 * 1024,  // 16MB
                    retryAttempts: 3,
                    retryDelay: 2.0,
                    compressionLevel: 6,
                    bandwidthLimit: nil,
                    timeoutInterval: 30.0
                )
            case .sftp:
                return ProviderSettings(
                    maxConcurrentOperations: 2,
                    chunkSize: 8 * 1024 * 1024,  // 8MB (SFTP is typically slower)
                    retryAttempts: 5,
                    retryDelay: 3.0,
                    compressionLevel: 6,
                    bandwidthLimit: nil,
                    timeoutInterval: 60.0
                )
            case .rest:
                return ProviderSettings(
                    maxConcurrentOperations: 2,
                    chunkSize: 8 * 1024 * 1024,  // 8MB
                    retryAttempts: 3,
                    retryDelay: 2.0,
                    compressionLevel: 6,
                    bandwidthLimit: nil,
                    timeoutInterval: 30.0
                )
            }
        }
    }
    
    struct TransferState {
        let id: String
        let provider: CloudProvider
        var bytesTransferred: Int64
        var totalBytes: Int64
        var startTime: Date
        var lastUpdateTime: Date
        var retryCount: Int
        var status: TransferStatus
        
        enum TransferStatus {
            case inProgress
            case paused
            case completed
            case failed(Error)
        }
        
        var transferRate: Double {
            let elapsed = lastUpdateTime.timeIntervalSince(startTime)
            guard elapsed > 0 else { return 0 }
            return Double(bytesTransferred) / elapsed
        }
        
        var estimatedTimeRemaining: TimeInterval? {
            guard transferRate > 0 else { return nil }
            let remainingBytes = totalBytes - bytesTransferred
            return Double(remainingBytes) / transferRate
        }
    }
    
    init() {
        setupConnectionMonitoring()
        setupDefaultSettings()
    }
    
    private func setupConnectionMonitoring() {
        connectionMonitor = NWPathMonitor()
        connectionMonitor?.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.handleConnectionUpdate(path)
            }
        }
        connectionMonitor?.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    private func setupDefaultSettings() {
        for provider in CloudProvider.allCases {
            optimizationSettings[provider] = .defaultSettings(for: provider)
        }
    }
    
    private func handleConnectionUpdate(_ path: NWPath) {
        let isExpensive = path.isExpensive
        let isConstrained = path.isConstrained
        
        // Adjust settings based on network conditions
        for provider in CloudProvider.allCases {
            var settings = optimizationSettings[provider] ?? .defaultSettings(for: provider)
            
            if isExpensive || isConstrained {
                // Reduce resource usage on constrained networks
                settings.maxConcurrentOperations = max(1, settings.maxConcurrentOperations / 2)
                settings.chunkSize = max(1024 * 1024, settings.chunkSize / 2)  // Minimum 1MB
                settings.compressionLevel = 9  // Max compression
                settings.bandwidthLimit = 1024 * 1024  // 1MB/s limit
            } else {
                // Reset to default settings
                settings = .defaultSettings(for: provider)
            }
            
            optimizationSettings[provider] = settings
        }
    }
    
    func getOptimizedCommand(_ command: ResticCommand, for provider: CloudProvider) -> ResticCommand {
        guard let settings = optimizationSettings[provider] else {
            return command
        }
        
        var arguments = command.arguments
        var environment = command.environment ?? [:]
        
        // Add optimization flags
        if settings.compressionLevel > 0 {
            arguments.append("--compression=\(settings.compressionLevel)")
        }
        
        if let limit = settings.bandwidthLimit {
            arguments.append("--limit-upload=\(limit)")
        }
        
        // Add environment variables
        environment["RESTIC_CACHE_DIR"] = FileManager.default.temporaryDirectory.appendingPathComponent("restic-cache").path
        environment["RESTIC_PACK_SIZE"] = String(settings.chunkSize)
        environment["RESTIC_TIMEOUT"] = String(Int(settings.timeoutInterval))
        
        return ResticCommand(
            repository: command.repository,
            arguments: arguments,
            environment: environment
        )
    }
    
    func startTransfer(id: String, provider: CloudProvider, totalBytes: Int64) {
        let transfer = TransferState(
            id: id,
            provider: provider,
            bytesTransferred: 0,
            totalBytes: totalBytes,
            startTime: Date(),
            lastUpdateTime: Date(),
            retryCount: 0,
            status: .inProgress
        )
        activeTransfers[id] = transfer
    }
    
    func updateTransfer(id: String, bytesTransferred: Int64) {
        guard var transfer = activeTransfers[id] else { return }
        transfer.bytesTransferred = bytesTransferred
        transfer.lastUpdateTime = Date()
        activeTransfers[id] = transfer
    }
    
    func completeTransfer(id: String) {
        guard var transfer = activeTransfers[id] else { return }
        transfer.status = .completed
        activeTransfers[id] = transfer
        
        logger.info("Transfer completed: \(transfer.id, privacy: .public)")
    }
    
    func failTransfer(id: String, error: Error) {
        guard var transfer = activeTransfers[id] else { return }
        transfer.status = .failed(error)
        activeTransfers[id] = transfer
        
        logger.error("Transfer failed: \(transfer.id, privacy: .public), error: \(error.localizedDescription)")
    }
    
    func shouldRetry(id: String) -> Bool {
        guard let transfer = activeTransfers[id],
              let settings = optimizationSettings[transfer.provider] else {
            return false
        }
        
        return transfer.retryCount < settings.retryAttempts
    }
    
    func getRetryDelay(id: String) -> TimeInterval {
        guard let transfer = activeTransfers[id],
              let settings = optimizationSettings[transfer.provider] else {
            return 1.0
        }
        
        // Exponential backoff
        return settings.retryDelay * pow(2.0, Double(transfer.retryCount))
    }
    
    func getActiveTransfers() -> [TransferState] {
        Array(activeTransfers.values)
    }
    
    func getTransferProgress(id: String) -> Double? {
        guard let transfer = activeTransfers[id] else { return nil }
        return Double(transfer.bytesTransferred) / Double(transfer.totalBytes)
    }
    
    deinit {
        connectionMonitor?.cancel()
    }
}

// MARK: - ResticService Extensions

extension ResticService {
    func optimizedCommand(_ command: ResticCommand, repository: Repository) async throws -> ResticCommand {
        guard let provider = repository.cloudProvider else {
            return command
        }
        
        let optimizer = CloudOptimizer()
        return optimizer.getOptimizedCommand(command, for: provider)
    }
    
    func trackCloudTransfer(id: String, repository: Repository, size: Int64) async {
        guard let provider = repository.cloudProvider else { return }
        
        let optimizer = CloudOptimizer()
        await optimizer.startTransfer(id: id, provider: provider, totalBytes: size)
    }
    
    func updateCloudTransfer(id: String, bytesTransferred: Int64) async {
        let optimizer = CloudOptimizer()
        await optimizer.updateTransfer(id: id, bytesTransferred: bytesTransferred)
    }
    
    func completeCloudTransfer(id: String) async {
        let optimizer = CloudOptimizer()
        await optimizer.completeTransfer(id: id)
    }
    
    func failCloudTransfer(id: String, error: Error) async {
        let optimizer = CloudOptimizer()
        await optimizer.failTransfer(id: id, error: error)
    }
}
