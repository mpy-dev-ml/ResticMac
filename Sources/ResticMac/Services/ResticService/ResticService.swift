import Foundation
import Combine
import os
import SwiftShell

// Replace global actor with traditional singleton
protocol ResticServiceProtocol {
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
    func snapshotProgress() -> AsyncStream<SnapshotProgress>
    func restoreProgress() -> AsyncStream<RestoreProgress>
}

@MainActor
final class ResticService: ObservableObject, ResticServiceProtocol {
    @Published private(set) var isProcessing = false
    @Published private(set) var currentProgress: SnapshotProgress?
    
    let snapshotProgressPublisher = PassthroughSubject<SnapshotProgress, Never>()
    
    private static var instance: ResticService?
    
    static var shared: ResticService {
        guard let instance = instance else {
            fatalError("ResticService not initialized. Call setup() first.")
        }
        return instance
    }
    
    private let executor: ProcessExecutor
    private var displayViewModel: CommandDisplayViewModel?
    
    // Progress tracking using combine publishers
    private let progressSubject = PassthroughSubject<SnapshotProgress, Never>()
    private let restoreSubject = PassthroughSubject<RestoreProgress, Never>()
    
    private init() {
        self.executor = ProcessExecutor()
    }
    
    private func emitProgress(_ progress: SnapshotProgress) {
        progressSubject.send(progress)
    }
    
    private func emitRestore(_ progress: RestoreProgress) {
        restoreSubject.send(progress)
    }
    
    static func setup() async throws {
        guard instance == nil else { return }
        let service = ResticService()
        try await service.executor.initialize()
        instance = service
    }
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {
        await withCheckedContinuation { continuation in
            executor.serialQueue.sync {
                self.displayViewModel = display
                continuation.resume()
            }
        }
    }
    
    func verifyInstallation() async throws {
        try await withCheckedThrowingContinuation { continuation in
            executor.serialQueue.sync {
                do {
                    let result = try executor.execute(
                        "/usr/local/bin/restic",
                        arguments: ["version"],
                        environment: [:],
                        timeout: 10
                    )
                    
                    guard result.isSuccess else {
                        throw ResticError.notInstalled
                    }
                    continuation.resume(returning: ())
                } catch {
                    AppLogger.shared.error("Failed to verify Restic installation: \(error.localizedDescription)")
                    continuation.resume(throwing: ResticError.notInstalled)
                }
            }
        }
    }
    
    func initializeRepository(name: String, path: URL) async throws -> Repository {
        try await withCheckedThrowingContinuation { continuation in
            executor.serialQueue.sync {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else {
                    continuation.resume(throwing: ResticError.validationFailed(errors: ["Repository name cannot be empty"]))
                    return
                }
                
                do {
                    // Check if directory exists
                    if !FileManager.default.fileExists(atPath: path.path) {
                        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                    }
                    
                    // Initialize repository with a temporary password
                    let tempPassword = UUID().uuidString
                    let command = ResticCommand(repository: path, password: tempPassword, operation: .initialize)
                    _ = try executor.execute(
                        command.executable,
                        arguments: command.arguments,
                        environment: command.environment as [String: String]
                    )
                    
                    // Create repository and store password
                    let repository = Repository(name: trimmedName, path: path)
                    try repository.storePassword(tempPassword)
                    
                    continuation.resume(returning: repository)
                } catch {
                    continuation.resume(throwing: ResticError.initializationFailed(underlying: error))
                }
            }
        }
    }
    
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult] {
        try await withCheckedThrowingContinuation { continuation in
            executor.serialQueue.sync {
                AppLogger.shared.info("Scanning for repositories in \(directory.path)")
                displayViewModel?.appendCommand("Scanning for repositories...")
                
                var results: [RepositoryScanResult] = []
                
                // Check if the directory itself is a repository
                if let result = try? scanSingleDirectory(directory) {
                    results.append(result)
                    AppLogger.shared.info("Found repository at \(directory.path)")
                }
                
                // Get contents of directory
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    AppLogger.shared.warning("Failed to enumerate directory \(directory.path)")
                    continuation.resume(returning: results)
                    return
                }
                
                for case let fileURL as URL in enumerator {
                    guard try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                        continue
                    }
                    
                    if let result = try? scanSingleDirectory(fileURL) {
                        results.append(result)
                        AppLogger.shared.info("Found repository at \(fileURL.path)")
                    }
                }
                
                continuation.resume(returning: results)
            }
        }
    }
    
    private func scanSingleDirectory(_ url: URL) throws -> RepositoryScanResult {
        do {
            let command = ResticCommand(
                repository: url,
                password: "",
                operation: .snapshots
            )
            
            let output = try executor.execute(
                command.executable,
                arguments: command.arguments,
                environment: command.environment as [String: String]
            )
            let snapshots = try parseSnapshotsOutput(output)
            
            return RepositoryScanResult(
                path: url,
                isValid: true,
                snapshots: snapshots
            )
        } catch {
            AppLogger.shared.error("Failed to scan repository at \(url.path): \(error.localizedDescription)")
            return RepositoryScanResult(path: url, isValid: false)
        }
    }
    
    func checkRepository(repository: Repository) async throws -> RepositoryStatus {
        try await withCheckedThrowingContinuation { continuation in
            executor.serialQueue.sync {
                let command = ResticCommand(
                    repository: repository.path,
                    password: try repository.retrievePassword(),
                    operation: .check
                )
                _ = try executor.execute(
                    command.executable,
                    arguments: command.arguments,
                    environment: command.environment as [String: String]
                )
                continuation.resume(returning: RepositoryStatus(state: .ok, errors: []))
            }
        }
    }
    
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot {
        try await withCheckedThrowingContinuation { continuation in
            executor.serialQueue.sync {
                let command = ResticCommand(
                    repository: repository.path,
                    password: try repository.retrievePassword(),
                    operation: .backup(paths: paths)
                )
                
                let result = try executor.execute(
                    command.executable,
                    arguments: command.arguments,
                    environment: command.environment as [String: String]
                ) { output in
                    if let progress = SnapshotProgress(output: output) {
                        emitProgress(progress)
                    }
                }
                
                // Parse snapshot ID from output
                guard let snapshotId = parseSnapshotId(from: result.output) else {
                    continuation.resume(throwing: ResticError.snapshotCreationFailed)
                    return
                }
                
                continuation.resume(returning: Snapshot(
                    id: snapshotId,
                    time: Date(),
                    paths: paths.map(\.path),
                    hostname: ProcessInfo.processInfo.hostName,
                    username: NSUserName(),
                    excludes: [],
                    tags: []
                ))
            }
        }
    }
    
    func listSnapshots(repository: Repository) async throws -> [Snapshot] {
        try await withCheckedThrowingContinuation { continuation in
            executor.serialQueue.sync {
                let command = ResticCommand(
                    repository: repository.path,
                    password: try repository.retrievePassword(),
                    operation: .snapshots
                )
                let output = try executor.execute(
                    command.executable,
                    arguments: command.arguments,
                    environment: command.environment as [String: String]
                )
                continuation.resume(returning: try parseSnapshotsOutput(output))
            }
        }
    }
    
    func restoreSnapshot(repository: Repository, snapshot: String, targetPath: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            executor.serialQueue.sync {
                let command = ResticCommand(
                    repository: repository.path,
                    password: try repository.retrievePassword(),
                    operation: .restore(snapshot: snapshot, target: targetPath)
                )
                
                try executor.execute(
                    command.executable,
                    arguments: command.arguments,
                    environment: command.environment as [String: String]
                ) { output in
                    if let progress = RestoreProgress(output: output) {
                        emitRestore(progress)
                    }
                }
                continuation.resume()
            }
        }
    }
    
    func listSnapshotContents(repository: Repository, snapshot: String, path: String?) async throws -> [SnapshotEntry] {
        try await withCheckedThrowingContinuation { continuation in
            executor.serialQueue.sync {
                let command = ResticCommand(
                    repository: repository.path,
                    password: try repository.retrievePassword(),
                    operation: .ls(snapshot: snapshot, path: path)
                )
                let output = try executor.execute(
                    command.executable,
                    arguments: command.arguments,
                    environment: command.environment as [String: String]
                )
                continuation.resume(returning: try JSONDecoder().decode([SnapshotEntry].self, from: output.data(using: .utf8) ?? Data()))
            }
        }
    }
    
    func deleteRepository(at path: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            executor.serialQueue.sync {
                AppLogger.shared.debug("Attempting to delete repository at \(path.path)")
                
                do {
                    // First, try to unlock the repository to ensure it exists and is accessible
                    let command = ResticCommand(
                        repository: path,
                        password: "", // Empty password for unlock
                        operation: .unlock
                    )
                    
                    _ = try executor.execute(
                        command.executable,
                        arguments: command.arguments,
                        environment: command.environment as [String: String]
                    )
                    
                    // Then remove the repository directory
                    try FileManager.default.removeItem(at: path)
                    AppLogger.shared.debug("Successfully deleted repository at \(path.path)")
                    continuation.resume()
                } catch {
                    AppLogger.shared.error("Failed to delete repository: \(error.localizedDescription)")
                    continuation.resume(throwing: ResticError.deletionFailed(path: path, underlying: error))
                }
            }
        }
    }
    
    nonisolated func snapshotProgress() -> AsyncStream<SnapshotProgress> {
        AsyncStream { continuation in
            Task { @MainActor in
                let subscription = progressSubject.sink { progress in
                    continuation.yield(progress)
                }
                continuation.onTermination = { _ in
                    subscription.cancel()
                }
            }
        }
    }
    
    nonisolated func restoreProgress() -> AsyncStream<RestoreProgress> {
        AsyncStream { continuation in
            Task { @MainActor in
                let subscription = restoreSubject.sink { progress in
                    continuation.yield(progress)
                }
                continuation.onTermination = { _ in
                    subscription.cancel()
                }
            }
        }
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

struct SnapshotProgress: Codable {
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

struct RestoreProgress: Codable {
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
