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

// MARK: - ResticError
enum ResticError: LocalizedError, Sendable {
    case installationNotFound
    case invalidRepository(path: String)
    case repositoryInitializationFailed(path: String, reason: String)
    case repositoryAccessDenied(path: String)
    case snapshotCreationFailed(reason: String)
    case snapshotNotFound(id: String)
    case restoreFailed(reason: String)
    case invalidCommand(description: String)
    case commandExecutionFailed(command: String, error: String)
    case unexpectedOutput(description: String)
    case deletionFailed(path: String, underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .installationNotFound:
            "Restic installation not found. Please ensure Restic is installed and accessible."
        case .invalidRepository(let path):
            "Invalid repository at path: \(path)"
        case .repositoryInitializationFailed(let path, let reason):
            "Failed to initialize repository at \(path): \(reason)"
        case .repositoryAccessDenied(let path):
            "Access denied to repository at \(path)"
        case .snapshotCreationFailed(let reason):
            "Failed to create snapshot: \(reason)"
        case .snapshotNotFound(let id):
            "Snapshot not found with ID: \(id)"
        case .restoreFailed(let reason):
            "Failed to restore snapshot: \(reason)"
        case .invalidCommand(let description):
            "Invalid command: \(description)"
        case .commandExecutionFailed(let command, let error):
            "Command execution failed (\(command)): \(error)"
        case .unexpectedOutput(let description):
            "Unexpected output: \(description)"
        case .deletionFailed(let path, _):
            "Failed to delete repository at \(path)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .installationNotFound:
            "Install Restic using Homebrew: brew install restic"
        case .invalidRepository:
            "Check if the repository path exists and is accessible"
        case .repositoryAccessDenied:
            "Check file permissions and ensure you have access to the repository"
        case .snapshotCreationFailed:
            "Verify backup paths are accessible and try again"
        case .snapshotNotFound:
            "List available snapshots using 'snapshots' command"
        case .restoreFailed:
            "Verify target path is writable and has sufficient space"
        case .invalidCommand, .commandExecutionFailed, .unexpectedOutput, .repositoryInitializationFailed:
            "Check logs for detailed error information"
        case .deletionFailed:
            "Check file permissions and ensure you have access to the repository"
        }
    }
}

@MainActor
final class ResticService: ObservableObject, ResticServiceProtocol {
    @Published private(set) var isProcessing = false
    @Published private(set) var currentProgress: SnapshotProgress?
    
    private let progressSubject = PassthroughSubject<SnapshotProgress, Never>()
    private let restoreSubject = PassthroughSubject<RestoreProgress, Never>()
    private var progressContinuation: AsyncStream<SnapshotProgress>.Continuation?
    private var restoreContinuation: AsyncStream<RestoreProgress>.Continuation?
    
    private static var instance: ResticService?
    private let executor: ProcessExecutor
    private var displayViewModel: CommandDisplayViewModel?
    private let logger = Logger(label: "com.resticmac.service")
    
    static var shared: ResticService {
        guard let instance = instance else {
            fatalError("ResticService not initialised. Call setup() first.")
        }
        return instance
    }
    
    static func setup() {
        guard instance == nil else { return }
        instance = ResticService()
    }
    
    private init() {
        self.executor = ProcessExecutor()
        setupProgressStreams()
    }
    
    private func setupProgressStreams() {
        var progressContinuation: AsyncStream<SnapshotProgress>.Continuation?
        let progressStream = AsyncStream<SnapshotProgress> { continuation in
            progressContinuation = continuation
        }
        self.progressContinuation = progressContinuation
        
        var restoreContinuation: AsyncStream<RestoreProgress>.Continuation?
        let restoreStream = AsyncStream<RestoreProgress> { continuation in
            restoreContinuation = continuation
        }
        self.restoreContinuation = restoreContinuation
    }
    
    func snapshotProgress() -> AsyncStream<SnapshotProgress> {
        AsyncStream { continuation in
            progressSubject
                .receive(on: DispatchQueue.main)
                .sink { progress in
                    continuation.yield(progress)
                }
                .store(in: &Set<AnyCancellable>())
        }
    }
    
    func restoreProgress() -> AsyncStream<RestoreProgress> {
        AsyncStream { continuation in
            restoreSubject
                .receive(on: DispatchQueue.main)
                .sink { progress in
                    continuation.yield(progress)
                }
                .store(in: &Set<AnyCancellable>())
        }
    }
    
    private func emitProgress(_ progress: SnapshotProgress) {
        Task { @MainActor in
            currentProgress = progress
            progressSubject.send(progress)
            progressContinuation?.yield(progress)
        }
    }
    
    private func emitRestoreProgress(_ progress: RestoreProgress) {
        Task { @MainActor in
            restoreSubject.send(progress)
            restoreContinuation?.yield(progress)
        }
    }
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) {
        self.displayViewModel = display
    }

    func verifyInstallation() async throws {
        do {
            let versionCommand = ResticCommand(arguments: ["version"])
            _ = try await executeCommand(versionCommand)
        } catch {
            AppLogger.shared.error("Restic installation verification failed: \(error.localizedDescription, privacy: .public)")
            throw ResticError.installationNotFound
        }
    }
    
    func initializeRepository(name: String, path: URL) async throws -> Repository {
        do {
            let initCommand = ResticCommand(
                repository: path.path,
                arguments: ["init"]
            )
            
            try await executeCommand(initCommand)
            
            AppLogger.shared.info("Successfully initialized repository at \(path.path, privacy: .public)")
            return Repository(name: name, path: path)
        } catch {
            let resticError = handleCommandError(error, command: "init")
            throw ResticError.repositoryInitializationFailed(
                path: path.path,
                reason: resticError.localizedDescription
            )
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
            
            let output = try await executeCommand(command)
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
                _ = try executeCommand(command)
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
                
                let result = try await executeCommand(command) { output in
                    if let progress = SnapshotProgress(output: output) {
                        emitProgress(progress)
                    }
                }
                
                // Parse snapshot ID from output
                guard let snapshotId = parseSnapshotId(from: result) else {
                    continuation.resume(throwing: ResticError.snapshotCreationFailed(reason: "Failed to parse snapshot ID"))
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
                let output = try await executeCommand(command)
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
                
                try await executeCommand(command) { output in
                    if let progress = RestoreProgress(output: output) {
                        emitRestoreProgress(progress)
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
                let output = try await executeCommand(command)
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
                    
                    _ = try executeCommand(command)
                    
                    // Then remove the repository directory
                    try FileManager.default.removeItem(at: path)
                    AppLogger.shared.debug("Successfully deleted repository at \(path.path)")
                    continuation.resume()
                } catch {
                    AppLogger.shared.error("Failed to delete repository: \(error.localizedDescription)")
                    continuation.resume(throwing: ResticError.deletionFailed(path: path.path, underlying: error))
                }
            }
        }
    }
    
    private func executeCommand(_ command: ResticCommand) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        displayViewModel?.appendCommand(command.description)
        
        do {
            let output = try await executor.execute(command)
            displayViewModel?.appendOutput(output)
            return output
        } catch {
            let resticError = handleCommandError(error, command: command.description)
            displayViewModel?.appendError(resticError.localizedDescription)
            throw resticError
        }
    }
    
    private func executeCommand(_ command: ResticCommand, progressHandler: @escaping (String) -> Void) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        displayViewModel?.appendCommand(command.description)
        
        do {
            let output = try await executor.execute(command) { output in
                progressHandler(output)
            }
            displayViewModel?.appendOutput(output)
            return output
        } catch {
            let resticError = handleCommandError(error, command: command.description)
            displayViewModel?.appendError(resticError.localizedDescription)
            throw resticError
        }
    }
    
    private func handleCommandError(_ error: Error, command: String) -> ResticError {
        AppLogger.shared.error("Command execution failed: \(error.localizedDescription, privacy: .public)")
        
        if let resticError = error as? ResticError {
            return resticError
        }
        
        return .commandExecutionFailed(command: command, error: error.localizedDescription)
    }
    
    private func validateRepository(_ path: URL) throws {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ResticError.invalidRepository(path: path.path)
        }
        
        guard FileManager.default.isReadableFile(atPath: path.path) else {
            throw ResticError.repositoryAccessDenied(path: path.path)
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
