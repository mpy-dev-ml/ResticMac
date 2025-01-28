import Foundation
import Combine
import os
import SwiftShell

@globalActor
actor ResticServiceActor {
    static let shared = ResticServiceActor()
}

protocol ResticServiceProtocol: Sendable {
    func setCommandDisplay(_ display: CommandDisplayViewModel) async
    func verifyInstallation() async throws
    func initializeRepository(name: String, path: URL) async throws -> Repository
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult]
    func checkRepository(repository: Repository) async throws -> RepositoryStatus
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot
    func listSnapshots(repository: Repository) async throws -> [Snapshot]
    func restoreSnapshot(repository: Repository, snapshot: String, targetPath: URL) async throws
    func listSnapshotContents(repository: Repository, snapshot: String, path: String?) async throws -> [SnapshotEntry]
    func deleteRepository(at path: URL) async throws
    
    // New methods for progress monitoring
    func snapshotProgress() -> AsyncStream<SnapshotProgress, Never>
    func restoreProgress() -> AsyncStream<RestoreProgress, Never>
}

@ResticServiceActor
final class ResticService: ResticServiceProtocol, @unchecked Sendable {
    private static var _instance: ResticService?
    
    static var shared: ResticService {
        guard let instance = _instance else {
            fatalError("ResticService not initialized. Call setup() first.")
        }
        return instance
    }
    
    private let executor: ProcessExecutor
    private var displayViewModel: CommandDisplayViewModel?
    
    // Progress tracking
    private let progressStream: AsyncStream<SnapshotProgress, Never>
    private let progressContinuation: AsyncStream<SnapshotProgress, Never>.Continuation
    
    // Restore tracking
    private let restoreStream: AsyncStream<RestoreProgress, Never>
    private let restoreContinuation: AsyncStream<RestoreProgress, Never>.Continuation
    
    private init() {
        // Initialize with default values
        self.executor = ProcessExecutor() // This is now nonisolated
        
        // Set up progress monitoring
        var progressCont: AsyncStream<SnapshotProgress, Never>.Continuation!
        let pStream = AsyncStream<SnapshotProgress, Never>(bufferingPolicy: .unbounded) { continuation in
            progressCont = continuation
        }
        self.progressStream = pStream
        self.progressContinuation = progressCont
        
        // Set up restore monitoring
        var restoreCont: AsyncStream<RestoreProgress, Never>.Continuation!
        let rStream = AsyncStream<RestoreProgress, Never>(bufferingPolicy: .unbounded) { continuation in
            restoreCont = continuation
        }
        self.restoreStream = rStream
        self.restoreContinuation = restoreCont
    }
    
    private func emitProgress(_ progress: SnapshotProgress) {
        progressContinuation.yield(progress)
    }
    
    private func emitRestore(_ progress: RestoreProgress) {
        restoreContinuation.yield(progress)
    }
    
    static func setup() async throws {
        guard _instance == nil else { return }
        let service = ResticService()
        try await service.executor.initialize() // Properly handle async initialization
        _instance = service
    }
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {
        self.displayViewModel = display
    }
    
    func verifyInstallation() async throws {
        do {
            let result = try await executor.execute(
                "/usr/local/bin/restic",
                arguments: ["version"],
                environment: [:],
                timeout: 10
            )
            
            guard result.isSuccess else {
                throw ResticError.notInstalled
            }
        } catch {
            await AppLogger.shared.error("Failed to verify Restic installation: \(error.localizedDescription)")
            throw ResticError.notInstalled
        }
    }
    
    func initializeRepository(name: String, path: URL) async throws -> Repository {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ResticError.validationFailed(errors: ["Repository name cannot be empty"])
        }
        
        do {
            // Check if directory exists
            if !FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            }
            
            // Initialize repository with a temporary password
            let tempPassword = UUID().uuidString
            let command = ResticCommand(repository: path, password: tempPassword, operation: .initialize)
            _ = try await executeCommand(command)
            
            // Create repository and store password
            let repository = Repository(name: trimmedName, path: path)
            try repository.storePassword(tempPassword)
            
            return repository
        } catch {
            throw ResticError.initializationFailed(underlying: error)
        }
    }
    
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult] {
        await AppLogger.shared.info("Scanning for repositories in \(directory.path)")
        await displayViewModel?.appendCommand("Scanning for repositories...")
        
        var results: [RepositoryScanResult] = []
        
        // Check if the directory itself is a repository
        if let result = try? await scanSingleDirectory(directory) {
            results.append(result)
            await AppLogger.shared.info("Found repository at \(directory.path)")
        }
        
        // Get contents of directory
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            await AppLogger.shared.warning("Failed to enumerate directory \(directory.path)")
            return results
        }
        
        for case let fileURL as URL in enumerator {
            guard try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                continue
            }
            
            if let result = try? await scanSingleDirectory(fileURL) {
                results.append(result)
                await AppLogger.shared.info("Found repository at \(fileURL.path)")
            }
        }
        
        return results
    }
    
    private func scanSingleDirectory(_ url: URL) async throws -> RepositoryScanResult {
        do {
            let command = ResticCommand(
                repository: url,
                password: "",
                operation: .snapshots
            )
            
            let output = try await executeCommand(command)
            let snapshots = try parseSnapshotsOutput(output)
            
            return RepositoryScanResult(
                path: url,
                isValid: true,
                snapshots: snapshots
            )
        } catch {
            await AppLogger.shared.error("Failed to scan repository at \(url.path): \(error.localizedDescription)")
            return RepositoryScanResult(path: url, isValid: false)
        }
    }
    
    func checkRepository(repository: Repository) async throws -> RepositoryStatus {
        let command = ResticCommand(
            repository: repository.path,
            password: try repository.retrievePassword(),
            operation: .check
        )
        _ = try await executeCommand(command)
        return RepositoryStatus(state: .ok, errors: [])
    }
    
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot {
        let command = ResticCommand(
            repository: repository.path,
            password: try repository.retrievePassword(),
            operation: .backup(paths: paths)
        )
        
        let result = try await withTaskCancellationHandler {
            // Update progress during backup
            let result = try await executor.execute(
                command.executable,
                arguments: command.arguments,
                environment: command.environment as [String: String]
            ) { output in
                if let progress = SnapshotProgress(output: output) {
                    emitProgress(progress)
                }
            }
            return result
        } onCancel: { [self] in
            // Handle cancellation cleanup
            emitProgress(SnapshotProgress(totalFiles: 0, processedFiles: 0, totalBytes: 0, processedBytes: 0, currentFile: nil))
            progressContinuation.finish()
        }
        
        // Parse snapshot ID from output
        guard let snapshotId = parseSnapshotId(from: result.output) else {
            throw ResticError.snapshotCreationFailed
        }
        
        return Snapshot(
            id: snapshotId,
            time: Date(),
            paths: paths.map(\.path),
            hostname: ProcessInfo.processInfo.hostName,
            username: NSUserName(),
            excludes: [],
            tags: []
        )
    }
    
    func listSnapshots(repository: Repository) async throws -> [Snapshot] {
        let command = ResticCommand(
            repository: repository.path,
            password: try repository.retrievePassword(),
            operation: .snapshots
        )
        let output = try await executeCommand(command)
        return try parseSnapshotsOutput(output)
    }
    
    func restoreSnapshot(repository: Repository, snapshot: String, targetPath: URL) async throws {
        let command = ResticCommand(
            repository: repository.path,
            password: try repository.retrievePassword(),
            operation: .restore(snapshot: snapshot, target: targetPath)
        )
        
        try await withTaskCancellationHandler {
            try await executor.execute(
                command.executable,
                arguments: command.arguments,
                environment: command.environment as [String: String]
            ) { output in
                if let progress = RestoreProgress(output: output) {
                    emitRestore(progress)
                }
            }
        } onCancel: { [self] in
            emitRestore(RestoreProgress(totalFiles: 0, processedFiles: 0, totalBytes: 0, processedBytes: 0, currentFile: nil))
            restoreContinuation.finish()
        }
    }
    
    func listSnapshotContents(repository: Repository, snapshot: String, path: String?) async throws -> [SnapshotEntry] {
        let command = ResticCommand(
            repository: repository.path,
            password: try repository.retrievePassword(),
            operation: .ls(snapshot: snapshot, path: path)
        )
        let output = try await executeCommand(command)
        return try JSONDecoder().decode([SnapshotEntry].self, from: output.data(using: .utf8) ?? Data())
    }
    
    func deleteRepository(at path: URL) async throws {
        await AppLogger.shared.debug("Attempting to delete repository at \(path.path)")
        
        do {
            // First, try to unlock the repository to ensure it exists and is accessible
            let command = ResticCommand(
                repository: path,
                password: "", // Empty password for unlock
                operation: .unlock
            )
            
            let _ = try await executeCommand(command)
            
            // Then remove the repository directory
            try FileManager.default.removeItem(at: path)
            await AppLogger.shared.debug("Successfully deleted repository at \(path.path)")
        } catch {
            await AppLogger.shared.error("Failed to delete repository: \(error.localizedDescription)")
            throw ResticError.deletionFailed(path: path, underlying: error)
        }
    }
    
    nonisolated func snapshotProgress() -> AsyncStream<SnapshotProgress, Never> {
        progressStream
    }
    
    nonisolated func restoreProgress() -> AsyncStream<RestoreProgress, Never> {
        restoreStream
    }
    
    private func executeCommand(_ command: ResticCommand) async throws -> String {
        await AppLogger.shared.debug("Executing command: \(command.executable) \(command.arguments.joined(separator: " "))")
        let result = try await executor.execute(
            command.executable,
            arguments: command.arguments,
            environment: command.environment as [String: String]
        )
        
        if !result.isSuccess {
            throw ResticError.commandFailed(underlying: NSError(
                domain: "ResticError",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.error] as [String: Any]
            ))
        }
        
        return result.output
    }
    
    private func parseSnapshotsOutput(_ output: String) throws -> [Snapshot] {
        // Implementation here
        []
    }
    
    private func parseSnapshotId(from output: String) -> String? {
        // Implementation details
        nil
    }
    
    deinit {
        AppLogger.shared.debug("ResticService deinitialised")
    }
}

struct SnapshotEntry: Identifiable, Codable {
    let id: String
    let type: EntryType
    let path: String
    let size: Int64?
    
    enum EntryType: String, Codable {
        case file
        case directory
    }
}

struct SnapshotProgress: Sendable {
    let totalFiles: Int
    let processedFiles: Int
    let totalBytes: Int64
    let processedBytes: Int64
    let currentFile: String?
    
    init(output: String) {
        // Parse progress from output
        self.totalFiles = 0
        self.processedFiles = 0
        self.totalBytes = 0
        self.processedBytes = 0
        self.currentFile = nil
    }
}

struct RestoreProgress: Sendable {
    let totalFiles: Int
    let processedFiles: Int
    let totalBytes: Int64
    let processedBytes: Int64
    let currentFile: String?
    
    init(output: String) {
        // Parse progress from output
        self.totalFiles = 0
        self.processedFiles = 0
        self.totalBytes = 0
        self.processedBytes = 0
        self.currentFile = nil
    }
}
