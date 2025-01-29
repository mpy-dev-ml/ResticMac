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
    func forgetSnapshot(repository: Repository, snapshot: String) async throws
    func pruneRepository(repository: Repository) async throws
    func getRepositoryStats(_ repository: Repository) async throws -> RepositoryStats
    func checkRepositoryHealth(_ repository: Repository) async throws -> RepositoryHealth
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
    case deletionFailed(path: String, underlying: any Error)
    case invalidConfiguration(reason: String)
    case schedulingFailed(error: String)
    
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
        case .invalidConfiguration(let reason):
            "Invalid configuration: \(reason)"
        case .schedulingFailed(let error):
            "Failed to schedule backup: \(error)"
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
        case .invalidConfiguration:
            "Review configuration and try again"
        case .schedulingFailed:
            "Check system logs for scheduling errors"
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
        do {
            let command = ResticCommand(
                repository: repository.path,
                arguments: ["check", "--json"]
            )
            
            let output = try await executeCommand(command)
            
            // Parse check output
            struct CheckResult: Codable {
                let errors: [String]?
                let status: String
            }
            
            if let data = output.data(using: .utf8),
               let result = try? JSONDecoder().decode(CheckResult.self, from: data) {
                let state: RepositoryState = result.status == "ok" ? .ok : .error
                return RepositoryStatus(state: state, errors: result.errors ?? [])
            }
            
            throw ResticError.unexpectedOutput(description: "Invalid check output format")
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "check", error: error.localizedDescription)
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
    
    func listSnapshotContents(repository: Repository, snapshot: String, path: String? = nil) async throws -> [SnapshotEntry] {
        do {
            var arguments = ["ls", snapshot, "--json"]
            if let path = path {
                arguments.append(path)
            }
            
            let command = ResticCommand(
                repository: repository.path,
                arguments: arguments
            )
            
            let output = try await executeCommand(command)
            
            guard let data = output.data(using: .utf8) else {
                throw ResticError.unexpectedOutput(description: "Invalid UTF-8 in ls output")
            }
            
            return try JSONDecoder().decode([SnapshotEntry].self, from: data)
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "ls", error: error.localizedDescription)
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
    
    func forgetSnapshot(repository: Repository, snapshot: String) async throws {
        do {
            let command = ResticCommand(
                repository: repository.path,
                arguments: ["forget", snapshot, "--prune"]
            )
            
            _ = try await executeCommand(command)
            logger.info("Successfully removed snapshot \(snapshot, privacy: .public)")
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "forget", error: error.localizedDescription)
        }
    }
    
    func pruneRepository(repository: Repository) async throws {
        do {
            let command = ResticCommand(
                repository: repository.path,
                arguments: ["prune"]
            )
            
            _ = try await executeCommand(command) { output in
                // Example progress: "pruning 5/10 packs"
                if let match = output.firstMatch(of: /pruning\s+(\d+)\/(\d+)\s+packs/) {
                    if let current = Int(match.1), let total = Int(match.2) {
                        let progress = Double(current) / Double(total)
                        emitProgress(SnapshotProgress(
                            type: .pruning,
                            current: current,
                            total: total,
                            percentage: progress
                        ))
                    }
                }
            }
            
            logger.info("Successfully pruned repository at \(repository.path.path, privacy: .public)")
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "prune", error: error.localizedDescription)
        }
    }
    
    private func parseSnapshotsOutput(_ output: String) throws -> [Snapshot] {
        guard let data = output.data(using: .utf8) else {
            throw ResticError.unexpectedOutput(description: "Invalid UTF-8 in snapshots output")
        }
        
        do {
            let snapshots = try JSONDecoder().decode([Snapshot].self, from: data)
            return snapshots.sorted { $0.time > $1.time }
        } catch {
            logger.error("Failed to parse snapshots: \(error.localizedDescription, privacy: .public)")
            throw ResticError.unexpectedOutput(description: "Failed to parse snapshots JSON")
        }
    }
    
    private func parseSnapshotId(from output: String) -> String? {
        // Example output: "snapshot 1a2b3c4d saved"
        let pattern = /snapshot\s+([a-f0-9]+)\s+saved/
        if let match = output.firstMatch(of: pattern) {
            return String(match.1)
        }
        return nil
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

    deinit {
        AppLogger.shared.debug("ResticService deinitialised")
    }
}

extension ResticService {
    struct RepositoryStats: Codable {
        let totalSize: UInt64
        let totalFiles: UInt64
        let uniqueSize: UInt64
        let uniqueFiles: UInt64
        let snapshotCount: Int
        let compressionRatio: Double
        
        enum CodingKeys: String, CodingKey {
            case totalSize = "total_size"
            case totalFiles = "total_files"
            case uniqueSize = "unique_size"
            case uniqueFiles = "unique_files"
            case snapshotCount = "snapshot_count"
            case compressionRatio = "compression_ratio"
        }
    }
    
    struct RepositoryHealth {
        let status: HealthStatus
        let issues: [HealthIssue]
        let lastCheck: Date
        
        enum HealthStatus {
            case healthy
            case warning
            case error
            
            var description: String {
                switch self {
                case .healthy: "Repository is healthy"
                case .warning: "Repository has warnings"
                case .error: "Repository has errors"
                }
            }
        }
        
        struct HealthIssue: Identifiable {
            let id = UUID()
            let type: IssueType
            let message: String
            let severity: IssueSeverity
            
            enum IssueType {
                case integrity
                case lock
                case index
                case pack
                case other
            }
            
            enum IssueSeverity {
                case warning
                case error
            }
        }
    }
    
    func getRepositoryStats(_ repository: Repository) async throws -> RepositoryStats {
        do {
            let command = ResticCommand(
                repository: repository.path,
                arguments: ["stats", "--json"]
            )
            
            let output = try await executeCommand(command)
            
            guard let data = output.data(using: .utf8) else {
                throw ResticError.unexpectedOutput(description: "Invalid UTF-8 in stats output")
            }
            
            return try JSONDecoder().decode(RepositoryStats.self, from: data)
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "stats", error: error.localizedDescription)
        }
    }
    
    func checkRepositoryHealth(_ repository: Repository) async throws -> RepositoryHealth {
        do {
            // First, check if repository is locked
            if try await isRepositoryLocked(repository) {
                return RepositoryHealth(
                    status: .error,
                    issues: [
                        RepositoryHealth.HealthIssue(
                            type: .lock,
                            message: "Repository is locked. Another operation might be in progress.",
                            severity: .error
                        )
                    ],
                    lastCheck: Date()
                )
            }
            
            // Run comprehensive check
            let command = ResticCommand(
                repository: repository.path,
                arguments: ["check", "--read-data", "--json"]
            )
            
            let output = try await executeCommand(command)
            
            // Parse check output
            struct CheckResult: Codable {
                let errors: [String]?
                let status: String
                let packs: PackStatus?
                
                struct PackStatus: Codable {
                    let checked: Int
                    let total: Int
                    let errors: [String]?
                }
            }
            
            guard let data = output.data(using: .utf8),
                  let result = try? JSONDecoder().decode(CheckResult.self, from: data) else {
                throw ResticError.unexpectedOutput(description: "Invalid check output format")
            }
            
            var issues: [RepositoryHealth.HealthIssue] = []
            var status: RepositoryHealth.HealthStatus = .healthy
            
            // Process pack errors
            if let packErrors = result.packs?.errors, !packErrors.isEmpty {
                issues.append(contentsOf: packErrors.map {
                    RepositoryHealth.HealthIssue(
                        type: .pack,
                        message: $0,
                        severity: .error
                    )
                })
                status = .error
            }
            
            // Process general errors
            if let errors = result.errors, !errors.isEmpty {
                issues.append(contentsOf: errors.map {
                    RepositoryHealth.HealthIssue(
                        type: .integrity,
                        message: $0,
                        severity: .error
                    )
                })
                status = .error
            }
            
            // Check index status
            if try await checkIndexStatus(repository) {
                issues.append(
                    RepositoryHealth.HealthIssue(
                        type: .index,
                        message: "Repository index needs rebuilding",
                        severity: .warning
                    )
                )
                status = status == .error ? .error : .warning
            }
            
            return RepositoryHealth(
                status: status,
                issues: issues,
                lastCheck: Date()
            )
            
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "check", error: error.localizedDescription)
        }
    }
    
    private func isRepositoryLocked(_ repository: Repository) async throws -> Bool {
        do {
            let command = ResticCommand(
                repository: repository.path,
                arguments: ["list", "locks", "--json"]
            )
            
            let output = try await executeCommand(command)
            
            guard let data = output.data(using: .utf8) else {
                throw ResticError.unexpectedOutput(description: "Invalid UTF-8 in locks output")
            }
            
            struct Lock: Codable {
                let id: String
                let time: String
                let pid: Int
            }
            
            let locks = try JSONDecoder().decode([Lock].self, from: data)
            return !locks.isEmpty
            
        } catch {
            // If we can't check locks, assume not locked
            logger.warning("Failed to check repository locks: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    private func checkIndexStatus(_ repository: Repository) async throws -> Bool {
        do {
            // Run index rebuild check
            let command = ResticCommand(
                repository: repository.path,
                arguments: ["rebuild-index", "--dry-run"]
            )
            
            _ = try await executeCommand(command)
            return false // If no error, index is fine
        } catch {
            return true // If error, index needs rebuilding
        }
    }
}

extension ResticService {
    struct SnapshotDiff: Codable {
        let added: [DiffEntry]
        let removed: [DiffEntry]
        let modified: [DiffEntry]
        
        struct DiffEntry: Codable, Identifiable {
            let id = UUID()
            let path: String
            let type: EntryType
            let size: UInt64?
            let permissions: String?
            let modTime: Date?
            
            enum CodingKeys: String, CodingKey {
                case path, type, size, permissions
                case modTime = "mtime"
            }
        }
        
        var hasChanges: Bool {
            !added.isEmpty || !removed.isEmpty || !modified.isEmpty
        }
        
        var totalChanges: Int {
            added.count + removed.count + modified.count
        }
    }
    
    func compareSnapshots(repository: Repository, snapshot1: String, snapshot2: String) async throws -> SnapshotDiff {
        do {
            let command = ResticCommand(
                repository: repository.path,
                arguments: ["diff", snapshot1, snapshot2, "--json"]
            )
            
            let output = try await executeCommand(command)
            
            guard let data = output.data(using: .utf8) else {
                throw ResticError.unexpectedOutput(description: "Invalid UTF-8 in diff output")
            }
            
            return try JSONDecoder().decode(SnapshotDiff.self, from: data)
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "diff", error: error.localizedDescription)
        }
    }
    
    func findChangedFiles(repository: Repository, pattern: String, snapshot: String? = nil) async throws -> [SnapshotEntry] {
        do {
            var arguments = ["find", "--json"]
            
            if let snapshot = snapshot {
                arguments.append("--snapshot")
                arguments.append(snapshot)
            }
            
            // Add pattern
            arguments.append(pattern)
            
            let command = ResticCommand(
                repository: repository.path,
                arguments: arguments
            )
            
            let output = try await executeCommand(command)
            
            guard let data = output.data(using: .utf8) else {
                throw ResticError.unexpectedOutput(description: "Invalid UTF-8 in find output")
            }
            
            return try JSONDecoder().decode([SnapshotEntry].self, from: data)
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "find", error: error.localizedDescription)
        }
    }
    
    func getSnapshotSummary(repository: Repository, snapshot: String) async throws -> SnapshotSummary {
        do {
            let command = ResticCommand(
                repository: repository.path,
                arguments: ["snapshots", snapshot, "--json"]
            )
            
            let output = try await executeCommand(command)
            let snapshots = try parseSnapshotsOutput(output)
            
            guard let targetSnapshot = snapshots.first else {
                throw ResticError.snapshotNotFound(id: snapshot)
            }
            
            // Get statistics for this snapshot
            let statsCommand = ResticCommand(
                repository: repository.path,
                arguments: ["stats", "--json", snapshot]
            )
            
            let statsOutput = try await executeCommand(statsCommand)
            
            guard let statsData = statsOutput.data(using: .utf8) else {
                throw ResticError.unexpectedOutput(description: "Invalid UTF-8 in stats output")
            }
            
            let stats = try JSONDecoder().decode(RepositoryStats.self, from: statsData)
            
            return SnapshotSummary(
                snapshot: targetSnapshot,
                stats: stats,
                lastModified: try await getLastModifiedFile(repository: repository, snapshot: snapshot)
            )
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "summary", error: error.localizedDescription)
        }
    }
    
    private func getLastModifiedFile(repository: Repository, snapshot: String) async throws -> SnapshotEntry? {
        let command = ResticCommand(
            repository: repository.path,
            arguments: ["ls", "--json", "--sort-by-time", snapshot]
        )
        
        let output = try await executeCommand(command)
        
        guard let data = output.data(using: .utf8) else {
            throw ResticError.unexpectedOutput(description: "Invalid UTF-8 in ls output")
        }
        
        let entries = try JSONDecoder().decode([SnapshotEntry].self, from: data)
        return entries.first
    }
}

extension ResticService {
    struct SnapshotSummary {
        let snapshot: Snapshot
        let stats: RepositoryStats
        let lastModified: SnapshotEntry?
        
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: Int64(stats.totalSize), countStyle: .file)
        }
        
        var compressionRatio: String {
            String(format: "%.1f%%", stats.compressionRatio * 100)
        }
    }
}

extension ResticError {
    static func snapshotNotFound(id: String) -> ResticError {
        .custom(message: "Snapshot not found: \(id)", suggestion: "Verify the snapshot ID and try again")
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
    
    init(type: SnapshotProgressType, current: Int, total: Int, percentage: Double) {
        self.totalFiles = total
        self.processedFiles = current
        self.totalBytes = 0
        self.processedBytes = 0
        self.currentFile = nil
    }
    
    enum SnapshotProgressType {
        case pruning
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

extension ResticService {
    struct BackupConfig: Codable {
        let paths: [URL]
        let excludePatterns: [ExcludePattern]
        let schedule: BackupSchedule?
        let tags: [String]
        let compressionLevel: CompressionLevel
        
        enum CompressionLevel: Int, Codable {
            case none = 0
            case fast = 1
            case default_ = 6
            case max = 9
            
            var argument: String {
                "--compression=\(rawValue)"
            }
        }
    }
    
    struct ExcludePattern: Codable, Identifiable {
        let id = UUID()
        let pattern: String
        let type: PatternType
        
        enum PatternType: String, Codable {
            case glob
            case regex
            case iregex // Case-insensitive regex
            
            var flag: String {
                switch self {
                case .glob: return "--exclude"
                case .regex: return "--exclude-file-re"
                case .iregex: return "--exclude-file-ire"
                }
            }
        }
        
        func toArgument() -> [String] {
            [type.flag, pattern]
        }
    }
    
    struct BackupSchedule: Codable {
        let frequency: Frequency
        let startTime: Date
        let retryInterval: TimeInterval
        let maxRetries: Int
        let conditions: [Condition]
        
        enum Frequency: Codable {
            case hourly(minute: Int)
            case daily(hour: Int, minute: Int)
            case weekly(weekday: Int, hour: Int, minute: Int)
            case monthly(day: Int, hour: Int, minute: Int)
            
            func nextRunDate(after date: Date = Date()) -> Date {
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                
                switch self {
                case .hourly(let minute):
                    components.minute = minute
                    if let result = calendar.date(from: components),
                       result > date {
                        return result
                    }
                    return calendar.date(byAdding: .hour, value: 1, to: result ?? date) ?? date
                    
                case .daily(let hour, let minute):
                    components.hour = hour
                    components.minute = minute
                    if let result = calendar.date(from: components),
                       result > date {
                        return result
                    }
                    return calendar.date(byAdding: .day, value: 1, to: result ?? date) ?? date
                    
                case .weekly(let weekday, let hour, let minute):
                    components.hour = hour
                    components.minute = minute
                    if let result = calendar.date(from: components),
                       let nextWeekday = calendar.nextDate(after: result,
                                                         matching: .init(weekday: weekday),
                                                         matchingPolicy: .nextTime) {
                        return nextWeekday
                    }
                    return date
                    
                case .monthly(let day, let hour, let minute):
                    components.day = day
                    components.hour = hour
                    components.minute = minute
                    if let result = calendar.date(from: components),
                       result > date {
                        return result
                    }
                    return calendar.date(byAdding: .month, value: 1, to: result ?? date) ?? date
                }
            }
        }
        
        enum Condition: Codable {
            case onPower
            case onWifi
            case minBatteryLevel(Int)
            case maxCPUUsage(Double)
            case maxDiskUsage(Double)
            
            func isSatisfied() -> Bool {
                switch self {
                case .onPower:
                    return ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 13, minorVersion: 0, patchVersion: 0))
                        ? PowerSourceMonitor.shared.isConnectedToPower
                        : true
                case .onWifi:
                    return NetworkMonitor.shared.isConnectedViaWiFi
                case .minBatteryLevel(let level):
                    return PowerSourceMonitor.shared.batteryLevel >= level
                case .maxCPUUsage(let threshold):
                    return SystemMonitor.shared.cpuUsage <= threshold
                case .maxDiskUsage(let threshold):
                    return SystemMonitor.shared.diskUsage <= threshold
                }
            }
        }
    }
    
    func createBackup(config: BackupConfig) async throws -> String {
        do {
            var arguments = ["backup", "--json"]
            
            // Add compression if specified
            if config.compressionLevel != .none {
                arguments.append(config.compressionLevel.argument)
            }
            
            // Add tags if specified
            if !config.tags.isEmpty {
                arguments.append(contentsOf: ["--tag", config.tags.joined(separator: ",")])
            }
            
            // Add exclude patterns
            for pattern in config.excludePatterns {
                arguments.append(contentsOf: pattern.toArgument())
            }
            
            // Add paths to backup
            arguments.append(contentsOf: config.paths.map(\.path))
            
            let command = ResticCommand(
                repository: repository.path,
                arguments: arguments
            )
            
            let output = try await executeCommand(command) { progressOutput in
                if let progress = SnapshotProgress(output: progressOutput) {
                    emitProgress(progress)
                }
            }
            
            // Parse snapshot ID from output
            guard let snapshotId = parseSnapshotId(from: output) else {
                throw ResticError.snapshotCreationFailed(reason: "Failed to parse snapshot ID")
            }
            
            logger.info("Successfully created backup snapshot: \(snapshotId, privacy: .public)")
            return snapshotId
            
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "backup", error: error.localizedDescription)
        }
    }
    
    func scheduleBackup(config: BackupConfig) async throws {
        guard let schedule = config.schedule else {
            throw ResticError.invalidConfiguration(reason: "No schedule provided")
        }
        
        // Register backup task
        let request = BGProcessingTaskRequest(identifier: "com.resticmac.backup")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = schedule.conditions.contains(.onPower)
        
        // Calculate next run date
        let nextRun = schedule.frequency.nextRunDate()
        request.earliestBeginDate = nextRun
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled next backup for: \(nextRun, privacy: .public)")
        } catch {
            throw ResticError.schedulingFailed(error: error.localizedDescription)
        }
    }
    
    func cancelScheduledBackups() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.resticmac.backup")
        logger.info("Cancelled all scheduled backups")
    }
}

// MARK: - System Monitoring

private class PowerSourceMonitor {
    static let shared = PowerSourceMonitor()
    
    var isConnectedToPower: Bool {
        // Implementation using IOKit
        true // Placeholder
    }
    
    var batteryLevel: Int {
        // Implementation using IOKit
        100 // Placeholder
    }
}

private class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    var isConnectedViaWiFi: Bool {
        // Implementation using Network framework
        true // Placeholder
    }
}

private class SystemMonitor {
    static let shared = SystemMonitor()
    
    var cpuUsage: Double {
        // Implementation using host_statistics
        0.0 // Placeholder
    }
    
    var diskUsage: Double {
        // Implementation using statfs
        0.0 // Placeholder
    }
}

struct SnapshotFilter {
    let host: String?
    let tags: [String]?
    let path: String?
    let timeRange: DateInterval?
    let groupBy: GroupBy?
    
    enum GroupBy: String {
        case host
        case tags
        case paths
    }
    
    func toArguments() -> [String] {
        var args: [String] = []
        if let host = host {
            args.append(contentsOf: ["--host", host])
        }
        if let tags = tags, !tags.isEmpty {
            args.append(contentsOf: ["--tag", tags.joined(separator: ",")])
        }
        if let path = path {
            args.append(contentsOf: ["--path", path])
        }
        if let timeRange = timeRange {
            let formatter = ISO8601DateFormatter()
            args.append(contentsOf: [
                "--time-after", formatter.string(from: timeRange.start),
                "--time-before", formatter.string(from: timeRange.end)
            ])
        }
        if let groupBy = groupBy {
            args.append(contentsOf: ["--group-by", groupBy.rawValue])
        }
        return args
    }
}

struct SnapshotGroup {
    let key: String
    let snapshots: [Snapshot]
    let totalSize: UInt64
}

func listSnapshots(repository: Repository, filter: SnapshotFilter? = nil) async throws -> [Snapshot] {
    do {
        var arguments = ["snapshots", "--json"]
        if let filter = filter {
            arguments.append(contentsOf: filter.toArguments())
        }
        
        let command = ResticCommand(
            repository: repository.path,
            arguments: arguments
        )
        
        let output = try await executeCommand(command)
        return try parseSnapshotsOutput(output)
    } catch {
        if let resticError = error as? ResticError {
            throw resticError
        }
        throw ResticError.commandExecutionFailed(command: "snapshots", error: error.localizedDescription)
    }
}

func groupSnapshots(repository: Repository, by grouping: SnapshotFilter.GroupBy) async throws -> [SnapshotGroup] {
    do {
        let snapshots = try await listSnapshots(repository: repository, filter: SnapshotFilter(groupBy: grouping))
        
        // Group snapshots based on the grouping criteria
        var groups: [String: [Snapshot]] = [:]
        for snapshot in snapshots {
            let key: String
            switch grouping {
            case .host:
                key = snapshot.hostname
            case .tags:
                key = snapshot.tags?.joined(separator: ",") ?? "untagged"
            case .paths:
                key = snapshot.paths.joined(separator: ",")
            }
            groups[key, default: []].append(snapshot)
        }
        
        // Calculate sizes for each group
        return try await groups.map { key, snapshots in
            let totalSize = try await calculateGroupSize(repository: repository, snapshots: snapshots)
            return SnapshotGroup(key: key, snapshots: snapshots, totalSize: totalSize)
        }
    } catch {
        if let resticError = error as? ResticError {
            throw resticError
        }
        throw ResticError.commandExecutionFailed(command: "group-snapshots", error: error.localizedDescription)
    }
}

private func calculateGroupSize(repository: Repository, snapshots: [Snapshot]) async throws -> UInt64 {
    // Use stats command to get size for specific snapshots
    let snapshotIds = snapshots.map { $0.id }
    let command = ResticCommand(
        repository: repository.path,
        arguments: ["stats", "--json"] + snapshotIds
    )
    
    let output = try await executeCommand(command)
    
    guard let data = output.data(using: .utf8) else {
        throw ResticError.unexpectedOutput(description: "Invalid UTF-8 in stats output")
    }
    
    struct StatsResult: Codable {
        let totalSize: UInt64
        
        enum CodingKeys: String, CodingKey {
            case totalSize = "total_size"
        }
    }
    
    let stats = try JSONDecoder().decode(StatsResult.self, from: data)
    return stats.totalSize
}

// MARK: - Maintenance Operations

struct MaintenancePolicy {
    let keepLast: Int?
    let keepHourly: Int?
    let keepDaily: Int?
    let keepWeekly: Int?
    let keepMonthly: Int?
    let keepYearly: Int?
    let keepTags: [String]?
    
    func toArguments() -> [String] {
        var args: [String] = []
        if let keepLast = keepLast {
            args.append(contentsOf: ["--keep-last", String(keepLast)])
        }
        if let keepHourly = keepHourly {
            args.append(contentsOf: ["--keep-hourly", String(keepHourly)])
        }
        if let keepDaily = keepDaily {
            args.append(contentsOf: ["--keep-daily", String(keepDaily)])
        }
        if let keepWeekly = keepWeekly {
            args.append(contentsOf: ["--keep-weekly", String(keepWeekly)])
        }
        if let keepMonthly = keepMonthly {
            args.append(contentsOf: ["--keep-monthly", String(keepMonthly)])
        }
        if let keepYearly = keepYearly {
            args.append(contentsOf: ["--keep-yearly", String(keepYearly)])
        }
        if let keepTags = keepTags {
            args.append(contentsOf: ["--keep-tag"] + keepTags)
        }
        return args
    }
}

func applyMaintenancePolicy(repository: Repository, policy: MaintenancePolicy) async throws -> [String] {
    do {
        let command = ResticCommand(
            repository: repository.path,
            arguments: ["forget", "--json", "--prune"] + policy.toArguments()
        )
        
        let output = try await executeCommand(command) { progressOutput in
            // Example progress: "pruning 5/10 packs"
            if let match = progressOutput.firstMatch(of: /pruning\s+(\d+)\/(\d+)\s+packs/) {
                if let current = Int(match.1), let total = Int(match.2) {
                    let progress = Double(current) / Double(total)
                    emitProgress(SnapshotProgress(
                        type: .pruning,
                        current: current,
                        total: total,
                        percentage: progress
                    ))
                }
            }
        }
        
        // Parse removed snapshot IDs
        struct ForgetResult: Codable {
            let remove: [String]?
        }
        
        guard let data = output.data(using: .utf8),
              let result = try? JSONDecoder().decode(ForgetResult.self, from: data) else {
            throw ResticError.unexpectedOutput(description: "Invalid forget output format")
        }
        
        return result.remove ?? []
        
    } catch {
        if let resticError = error as? ResticError {
            throw resticError
        }
        throw ResticError.commandExecutionFailed(command: "forget", error: error.localizedDescription)
    }
}

// MARK: - Cloud Storage Support

extension ResticService {
    enum CloudProvider: String, CaseIterable, Codable {
        case s3 = "s3"
        case b2 = "b2"
        case azure = "azure"
        case gcs = "gs"
        case sftp = "sftp"
        case rest = "rest"
        
        var displayName: String {
            switch self {
            case .s3: "Amazon S3"
            case .b2: "Backblaze B2"
            case .azure: "Azure Blob Storage"
            case .gcs: "Google Cloud Storage"
            case .sftp: "SFTP"
            case .rest: "REST Server"
            }
        }
        
        var scheme: String {
            switch self {
            case .s3: "s3"
            case .b2: "b2"
            case .azure: "azure"
            case .gcs: "gs"
            case .sftp: "sftp"
            case .rest: "rest"
            }
        }
    }
    
    struct CloudCredentials: Codable {
        let provider: CloudProvider
        let credentials: [String: String]
        let endpoint: String?
        let region: String?
        
        func toEnvironment() -> [String: String] {
            var env: [String: String] = [:]
            
            switch provider {
            case .s3:
                env["AWS_ACCESS_KEY_ID"] = credentials["accessKeyId"]
                env["AWS_SECRET_ACCESS_KEY"] = credentials["secretAccessKey"]
                if let region = region {
                    env["AWS_DEFAULT_REGION"] = region
                }
                if let endpoint = endpoint {
                    env["AWS_ENDPOINT"] = endpoint
                }
                
            case .b2:
                env["B2_ACCOUNT_ID"] = credentials["accountId"]
                env["B2_ACCOUNT_KEY"] = credentials["accountKey"]
                if let endpoint = endpoint {
                    env["B2_ENDPOINT"] = endpoint
                }
                
            case .azure:
                env["AZURE_ACCOUNT_NAME"] = credentials["accountName"]
                env["AZURE_ACCOUNT_KEY"] = credentials["accountKey"]
                if let endpoint = endpoint {
                    env["AZURE_ENDPOINT"] = endpoint
                }
                
            case .gcs:
                if let jsonKey = credentials["jsonKey"] {
                    env["GOOGLE_APPLICATION_CREDENTIALS"] = jsonKey
                }
                if let projectId = credentials["projectId"] {
                    env["GOOGLE_PROJECT_ID"] = projectId
                }
                
            case .sftp:
                if let privateKey = credentials["privateKey"] {
                    env["RESTIC_SFTP_KEY"] = privateKey
                }
                if let password = credentials["password"] {
                    env["RESTIC_SFTP_PASSWORD"] = password
                }
                
            case .rest:
                if let username = credentials["username"] {
                    env["RESTIC_REST_USERNAME"] = username
                }
                if let password = credentials["password"] {
                    env["RESTIC_REST_PASSWORD"] = password
                }
            }
            
            return env
        }
    }
    
    struct CloudRepository {
        let provider: CloudProvider
        let bucket: String
        let prefix: String?
        let credentials: CloudCredentials
        
        var repositoryURL: String {
            var components = URLComponents()
            components.scheme = provider.scheme
            
            switch provider {
            case .s3:
                components.host = bucket
                if let region = credentials.region {
                    components.host = "\(bucket).s3.\(region).amazonaws.com"
                }
            case .b2:
                components.host = bucket
            case .azure:
                if let accountName = credentials.credentials["accountName"] {
                    components.host = "\(accountName).blob.core.windows.net"
                    components.path = "/\(bucket)"
                }
            case .gcs:
                components.host = bucket
            case .sftp:
                if let host = credentials.endpoint {
                    components.host = host
                    components.path = "/\(bucket)"
                }
            case .rest:
                if let endpoint = credentials.endpoint {
                    components.host = endpoint
                    components.path = "/\(bucket)"
                }
            }
            
            if let prefix = prefix {
                components.path = (components.path ?? "") + "/\(prefix)"
            }
            
            return components.url?.absoluteString ?? ""
        }
    }
    
    func initializeCloudRepository(repository: CloudRepository, password: String) async throws -> Repository {
        do {
            // Validate cloud credentials
            guard !repository.repositoryURL.isEmpty else {
                throw ResticError.invalidConfiguration(reason: "Invalid repository URL")
            }
            
            // Create command with cloud environment
            let command = ResticCommand(
                repository: repository.repositoryURL,
                arguments: ["init"],
                environment: repository.credentials.toEnvironment()
            )
            
            _ = try await executeCommand(command)
            
            // Create local Repository object
            let repo = Repository(
                name: repository.bucket,
                path: URL(string: repository.repositoryURL)!,
                cloudProvider: repository.provider
            )
            
            // Store credentials securely
            try await storeCloudCredentials(repository.credentials, for: repo)
            
            logger.info("Successfully initialized cloud repository: \(repository.repositoryURL, privacy: .private)")
            return repo
            
        } catch {
            if let resticError = error as? ResticError {
                throw resticError
            }
            throw ResticError.commandExecutionFailed(command: "init", error: error.localizedDescription)
        }
    }
    
    private func storeCloudCredentials(_ credentials: CloudCredentials, for repository: Repository) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(credentials)
        
        // Store in keychain with repository URL as key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: repository.path.absoluteString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ResticError.custom(
                message: "Failed to store cloud credentials",
                suggestion: "Check keychain access and try again"
            )
        }
    }
    
    func retrieveCloudCredentials(for repository: Repository) async throws -> CloudCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: repository.path.absoluteString,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let credentials = try? JSONDecoder().decode(CloudCredentials.self, from: data) else {
            throw ResticError.custom(
                message: "Failed to retrieve cloud credentials",
                suggestion: "Repository credentials may need to be reconfigured"
            )
        }
        
        return credentials
    }
}

// MARK: - Repository Extensions

extension Repository {
    var isCloudRepository: Bool {
        cloudProvider != nil
    }
    
    var cloudProvider: CloudProvider? {
        CloudProvider.allCases.first { provider in
            path.scheme == provider.scheme
        }
    }
}
