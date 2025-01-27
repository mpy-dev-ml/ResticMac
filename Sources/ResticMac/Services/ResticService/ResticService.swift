import Foundation
import Combine
import os

@MainActor
protocol ResticServiceProtocol {
    func setCommandDisplay(_ display: CommandDisplayViewModel) async
    func verifyInstallation() async throws
    func initializeRepository(name: String, path: URL, password: String) async throws -> Repository
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult]
    func checkRepository(repository: Repository) async throws -> RepositoryStatus
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot
    func listSnapshots(repository: Repository) async throws -> [Snapshot]
    func restoreSnapshot(repository: Repository, snapshot: String, targetPath: URL) async throws
    func listSnapshotContents(repository: Repository, snapshot: String, path: String?) async throws -> [SnapshotEntry]
}

@MainActor
final class ResticService: ResticServiceProtocol, ObservableObject {
    private let executor: ProcessExecutor
    private var displayViewModel: CommandDisplayViewModel?
    
    init(executor: ProcessExecutor = ProcessExecutor()) {
        self.executor = executor
    }
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {
        self.displayViewModel = display
    }
    
    func verifyInstallation() async throws {
        do {
            _ = try await executor.execute(
                "restic",
                arguments: ["version"],
                environment: [:]
            )
        } catch {
            AppLogger.error("Failed to verify Restic installation: \(error.localizedDescription)", category: .process)
            throw ResticError.notInstalled
        }
    }
    
    func initializeRepository(name: String, path: URL, password: String) async throws -> Repository {
        // Validate inputs
        var validationErrors: [String] = []
        
        // Validate name
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationErrors.append("Repository name cannot be empty")
        }
        
        // Validate path
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        if !fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) {
            do {
                try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
            } catch {
                validationErrors.append("Failed to create repository directory: \(error.localizedDescription)")
            }
        } else if !isDirectory.boolValue {
            validationErrors.append("Repository path must be a directory")
        }
        
        // Check write permissions
        if !fileManager.isWritableFile(atPath: path.path) {
            validationErrors.append("Repository directory is not writable")
        }
        
        // Validate password
        if password.count < 8 {
            validationErrors.append("Password must be at least 8 characters long")
        }
        
        // Check for existing repository
        if fileManager.fileExists(atPath: path.appendingPathComponent("config").path) {
            validationErrors.append("A repository already exists at this location")
        }
        
        if !validationErrors.isEmpty {
            throw ResticError.repositoryInvalid(validationErrors)
        }
        
        // Create repository
        do {
            let command = ResticCommand.initialize(repository: path, password: password)
            _ = try await executeCommand(command)
            
            // Create and store repository
            let repository = Repository(name: name, path: path)
            try repository.storePassword(password)
            
            AppLogger.info("Successfully initialized repository at \(path.path)", category: .repository)
            return repository
            
        } catch let error as ProcessError {
            AppLogger.error("Failed to initialize repository: \(error.localizedDescription)", category: .repository)
            throw ResticError.initializationFailed(error.localizedDescription)
        } catch {
            AppLogger.error("Unexpected error during repository initialization: \(error.localizedDescription)", category: .repository)
            throw ResticError.unknown(error.localizedDescription)
        }
    }
    
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult] {
        // Implementation for scanning repositories
        return []
    }
    
    func checkRepository(repository: Repository) async throws -> RepositoryStatus {
        let command = ResticCommand.check(repository: repository.path, password: try repository.retrievePassword())
        _ = try await executeCommand(command)
        return .ok
    }
    
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot {
        let command = ResticCommand.backup(repository: repository.path, paths: paths, password: try repository.retrievePassword())
        _ = try await executeCommand(command)
        return Snapshot(id: UUID().uuidString, time: Date(), paths: paths.map(\.path), hostname: "", username: "", excludes: nil, tags: nil)
    }
    
    func listSnapshots(repository: Repository) async throws -> [Snapshot] {
        let command = ResticCommand.snapshots(repository: repository.path, password: try repository.retrievePassword())
        let output = try await executeCommand(command)
        return try parseSnapshotsOutput(output)
    }
    
    func restoreSnapshot(repository: Repository, snapshot: String, targetPath: URL) async throws {
        let command = ResticCommand.restore(repository: repository.path, snapshot: snapshot, target: targetPath, password: try repository.retrievePassword())
        _ = try await executeCommand(command)
    }
    
    func listSnapshotContents(repository: Repository, snapshot: String, path: String?) async throws -> [SnapshotEntry] {
        let command = ResticCommand.ls(repository: repository.path, snapshotID: snapshot, password: try repository.retrievePassword())
        let output = try await executeCommand(command)
        return try parseSnapshotContents(output)
    }
    
    private func executeCommand(_ command: ResticCommand) async throws -> String {
        do {
            let result = try await executor.execute(
                command.executable,
                arguments: command.arguments,
                environment: command.environment
            )
            return result.output
        } catch let error as ProcessError {
            switch error {
            case .executionFailed(let code, let message):
                throw ResticError.commandFailed(code: Int(code), message: message)
            case .processStartFailed(let message):
                throw ResticError.commandExecutionFailed(ProcessError.processStartFailed(message: message))
            case .timeout:
                throw ResticError.commandExecutionFailed(error)
            }
        } catch {
            throw ResticError.unknown(error.localizedDescription)
        }
    }
    
    private func parseSnapshotsOutput(_ output: String) throws -> [Snapshot] {
        // Implementation for parsing snapshots output
        return []
    }
    
    private func parseSnapshotContents(_ output: String) throws -> [SnapshotEntry] {
        // Implementation for parsing snapshot contents
        return []
    }
    
    deinit {
        AppLogger.debug("ResticService deinitialised", category: .process)
    }
}

struct SnapshotEntry: Identifiable, Codable {
    let id: String
    let type: EntryType
    let name: String
    let size: Int64
    let modTime: Date
    
    enum EntryType: String, Codable {
        case file
        case directory
    }
}