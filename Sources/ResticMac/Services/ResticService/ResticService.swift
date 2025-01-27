import Foundation
import Combine
import os

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
            operation: .ls(snapshotID: snapshot)
        )
        let output = try await executeCommand(command)
        return try parseSnapshotContents(output)
    }
    
    private func executeCommand(_ command: ResticCommand) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = command.environment
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        
        let outputData = try await withCheckedThrowingContinuation { continuation in
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.resume(returning: handle.availableData)
                }
            }
        }
        
        let errorData = try await withCheckedThrowingContinuation { continuation in
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.resume(returning: handle.availableData)
                }
            }
        }
        
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
        
        if process.terminationStatus != 0 {
            let errorMessage = String(decoding: errorData, as: UTF8.self)
            throw ResticError.commandFailed(underlying: NSError(
                domain: "ResticError",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            ))
        }
        
        return String(decoding: outputData, as: UTF8.self)
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
        AppLogger.debug("ResticService deinitialised", category: .process)
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