import Foundation
import OSLog

actor CloudAnalyticsRecovery {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsRecovery")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    private let recoveryDirectory: URL
    private let maxCheckpoints: Int = 5
    
    init(persistence: CloudAnalyticsPersistence, monitor: CloudAnalyticsMonitor) {
        self.persistence = persistence
        self.monitor = monitor
        
        // Set up recovery directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.recoveryDirectory = appSupport.appendingPathComponent("ResticMac/Recovery/Analytics", isDirectory: true)
        
        // Ensure recovery directory exists
        try? FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Checkpointing
    
    func createCheckpoint(for repository: Repository) async throws {
        let checkpoint = AnalyticsCheckpoint(
            timestamp: Date(),
            repositoryId: repository.id,
            metrics: try await persistence.exportMetrics(for: repository),
            systemState: try await monitor.exportMetrics()
        )
        
        // Save checkpoint
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)
        
        let checkpointFile = recoveryDirectory.appendingPathComponent(
            "checkpoint_\(repository.id)_\(checkpoint.timestamp.ISO8601Format()).json"
        )
        try data.write(to: checkpointFile)
        
        // Maintain checkpoint limit
        try await pruneCheckpoints(for: repository)
        
        logger.info("Created analytics checkpoint for repository: \(repository.id)")
    }
    
    private func pruneCheckpoints(for repository: Repository) async throws {
        let fileManager = FileManager.default
        let checkpointPattern = "checkpoint_\(repository.id)_"
        
        let checkpoints = try fileManager.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.lastPathComponent.starts(with: checkpointPattern) }
            .sorted { file1, file2 in
                let date1 = try file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 > date2
            }
        
        // Remove excess checkpoints
        if checkpoints.count > maxCheckpoints {
            for checkpoint in checkpoints[maxCheckpoints...] {
                try fileManager.removeItem(at: checkpoint)
            }
        }
    }
    
    // MARK: - Recovery
    
    func recoverFromCrash(for repository: Repository) async throws -> RecoveryResult {
        logger.info("Starting crash recovery for repository: \(repository.id)")
        
        // Find latest checkpoint
        let checkpoint = try await findLatestCheckpoint(for: repository)
        guard let checkpoint = checkpoint else {
            logger.warning("No checkpoint found for repository: \(repository.id)")
            return .noCheckpointFound
        }
        
        // Verify checkpoint integrity
        guard try await verifyCheckpoint(checkpoint) else {
            logger.error("Checkpoint verification failed for repository: \(repository.id)")
            return .checkpointCorrupted
        }
        
        // Restore metrics
        try await persistence.importMetrics(checkpoint.metrics, for: repository)
        
        // Verify restored data
        let verificationResult = try await verifyRestoredData(checkpoint, for: repository)
        if !verificationResult.success {
            logger.error("Data verification failed: \(verificationResult.details)")
            return .dataVerificationFailed(verificationResult.details)
        }
        
        logger.info("Successfully recovered analytics data for repository: \(repository.id)")
        return .success(checkpoint.timestamp)
    }
    
    private func findLatestCheckpoint(for repository: Repository) async throws -> AnalyticsCheckpoint? {
        let checkpointPattern = "checkpoint_\(repository.id)_"
        
        let checkpoints = try FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.lastPathComponent.starts(with: checkpointPattern) }
            .sorted { file1, file2 in
                let date1 = try file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 > date2
            }
        
        guard let latestCheckpoint = checkpoints.first else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: latestCheckpoint)
        return try decoder.decode(AnalyticsCheckpoint.self, from: data)
    }
    
    private func verifyCheckpoint(_ checkpoint: AnalyticsCheckpoint) async throws -> Bool {
        // Verify checkpoint structure
        guard checkpoint.timestamp <= Date(),
              !checkpoint.repositoryId.isEmpty,
              !checkpoint.metrics.isEmpty else {
            return false
        }
        
        // Verify metrics integrity
        do {
            let decoder = JSONDecoder()
            let _ = try decoder.decode(AnalyticsMetrics.self, from: checkpoint.metrics)
        } catch {
            logger.error("Metrics integrity check failed: \(error.localizedDescription)")
            return false
        }
        
        return true
    }
    
    private func verifyRestoredData(_ checkpoint: AnalyticsCheckpoint, for repository: Repository) async throws -> (success: Bool, details: String) {
        // Verify storage metrics
        let storageMetrics = try await persistence.getStorageMetrics(for: repository)
        guard storageMetrics.totalBytes >= 0,
              storageMetrics.compressedBytes >= 0,
              storageMetrics.deduplicatedBytes >= 0 else {
            return (false, "Invalid storage metrics values")
        }
        
        // Verify transfer metrics
        let transferMetrics = try await persistence.getTransferMetrics(for: repository)
        guard transferMetrics.uploadedBytes >= 0,
              transferMetrics.downloadedBytes >= 0,
              transferMetrics.averageTransferSpeed >= 0 else {
            return (false, "Invalid transfer metrics values")
        }
        
        // Verify cost metrics
        let costMetrics = try await persistence.getCostMetrics(for: repository)
        guard costMetrics.storageUnitCost >= 0,
              costMetrics.transferUnitCost >= 0,
              costMetrics.totalCost >= 0 else {
            return (false, "Invalid cost metrics values")
        }
        
        return (true, "All metrics verified successfully")
    }
    
    // MARK: - Automatic Recovery
    
    func enableAutomaticRecovery() async {
        // Set up crash detection
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleAppTermination()
            }
        }
        
        // Monitor system health
        Task {
            await monitorSystemHealth()
        }
    }
    
    private func handleAppTermination() async {
        logger.info("Handling application termination")
        
        do {
            // Create final checkpoints for all repositories
            let repositories = try await persistence.getAllRepositories()
            for repository in repositories {
                try await createCheckpoint(for: repository)
            }
        } catch {
            logger.error("Failed to create termination checkpoints: \(error.localizedDescription)")
        }
    }
    
    private func monitorSystemHealth() async {
        while true {
            do {
                let health = await monitor.checkSystemHealth()
                
                if health.status == .unhealthy {
                    logger.warning("Unhealthy system state detected, creating emergency checkpoints")
                    
                    // Create emergency checkpoints
                    let repositories = try await persistence.getAllRepositories()
                    for repository in repositories {
                        try await createCheckpoint(for: repository)
                    }
                }
                
                try await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5 seconds
            } catch {
                logger.error("Health monitoring error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Supporting Types

struct AnalyticsCheckpoint: Codable {
    let timestamp: Date
    let repositoryId: String
    let metrics: Data
    let systemState: Data
}

enum RecoveryResult {
    case success(Date)
    case noCheckpointFound
    case checkpointCorrupted
    case dataVerificationFailed(String)
}

struct AnalyticsMetrics: Codable {
    let storageMetrics: StorageMetrics
    let transferMetrics: TransferMetrics
    let costMetrics: CostMetrics
}
