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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
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
        } else if !fileManager.isWritableFile(atPath: path.path) {
            validationErrors.append("Repository directory is not writable")
        }
        
        // Validate password
        if password.count < 8 {
            validationErrors.append("Password must be at least 8 characters long")
        }
        
        if !validationErrors.isEmpty {
            throw ResticError.validationFailed(errors: validationErrors)
        }
        
        // Initialize repository
        do {
            AppLogger.info("Initializing repository at \(path.path)", category: .repository)
            await displayViewModel?.appendCommand("Initialising repository...")
            
            let command = ResticCommand.initialize(repository: path, password: password)
            _ = try await executeCommand(command)
            
            // Create and return repository
            let now = Date()
            let repository = Repository(
                id: UUID(),
                name: trimmedName,
                path: path,
                createdAt: now,
                lastBackup: nil,
                lastChecked: now
            )
            
            // Store password securely
            try repository.storePassword(password)
            
            await displayViewModel?.appendOutput("Repository initialised successfully")
            AppLogger.info("Repository initialized successfully at \(path.path)", category: .repository)
            
            return repository
        } catch {
            AppLogger.error("Failed to initialize repository: \(error.localizedDescription)", category: .repository)
            throw ResticError.initializationFailed(underlying: error)
        }
    }
    
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult] {
        AppLogger.info("Scanning for repositories in \(directory.path)", category: .repository)
        await displayViewModel?.appendCommand("Scanning for repositories...")
        
        let fileManager = FileManager.default
        var results: [RepositoryScanResult] = []
        
        // Check if the directory itself is a repository
        if let result = try? await scanSingleDirectory(directory) {
            results.append(result)
            AppLogger.info("Found repository at \(directory.path)", category: .repository)
        }
        
        // Get contents of directory
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            AppLogger.warning("Failed to enumerate directory \(directory.path)", category: .repository)
            return results
        }
        
        // Scan each subdirectory
        for case let fileURL as URL in enumerator {
            guard try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            
            // Skip if we've already found it as a repository
            if results.contains(where: { $0.path == fileURL }) { continue }
            
            if let result = try? await scanSingleDirectory(fileURL) {
                results.append(result)
                AppLogger.info("Found repository at \(fileURL.path)", category: .repository)
            }
        }
        
        await displayViewModel?.appendOutput("Found \(results.count) repositories")
        return results
    }
    
    private func scanSingleDirectory(_ url: URL) async throws -> RepositoryScanResult? {
        // Check for config file
        let configPath = url.appendingPathComponent("config")
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return nil
        }
        
        // Try to check repository status
        do {
            let tempRepo = Repository(name: url.lastPathComponent, path: url)
            let status = try await checkRepository(repository: tempRepo)
            let snapshots = try? await listSnapshots(repository: tempRepo)
            
            return RepositoryScanResult(
                path: url,
                isValid: status.isValid,
                snapshots: snapshots
            )
        } catch {
            AppLogger.error("Failed to scan repository at \(url.path): \(error.localizedDescription)", category: .repository)
            return RepositoryScanResult(path: url, isValid: false)
        }
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
            await displayViewModel?.appendCommand("restic \(command.arguments.joined(separator: " "))")
            
            let result = try await executor.execute(
                command.executable,
                arguments: command.arguments,
                environment: command.environment
            )
            
            await displayViewModel?.appendOutput(result.output)
            return result.output
        } catch {
            await displayViewModel?.appendError(error.localizedDescription)
            throw error
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