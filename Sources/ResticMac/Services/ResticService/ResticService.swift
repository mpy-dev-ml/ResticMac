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
}

@ResticServiceActor
final class ResticService: ResticServiceProtocol, Sendable {
    static let shared = ResticService()
    private let executor: ProcessExecutor
    private var displayViewModel: CommandDisplayViewModel?
    
    private init() {
        self.executor = ProcessExecutor()
    }
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {
        self.displayViewModel = display
    }
    
    func verifyInstallation() async throws {
        do {
            _ = try await executor.execute(
                "/usr/local/bin/restic",
                arguments: ["version"],
                environment: [:]
            )
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
        _ = try await executeCommand(command)
        return Snapshot(
            id: UUID().uuidString,
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
        _ = try await executeCommand(command)
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
    
    private func executeCommand(_ command: ResticCommand) async throws -> String {
        await AppLogger.shared.debug("Executing command: \(command.executable) \(command.arguments.joined(separator: " "))")
        let result = try await executor.execute(
            command.executable,
            arguments: command.arguments,
            environment: command.environment
        )
        
        if !result.isSuccess {
            throw ResticError.commandFailed(underlying: NSError(
                domain: "ResticError",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: result.error]
            ))
        }
        
        return result.output
    }
    
    private func parseSnapshotsOutput(_ output: String) throws -> [Snapshot] {
        // Implementation here
        []
    }
    
    private func parseSnapshotContents(_ output: String) throws -> [SnapshotEntry] {
        // Implementation here
        []
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
