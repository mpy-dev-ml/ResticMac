import Foundation
import Logging
import Combine

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
    private let logger = Logger(label: "com.resticmac.ResticService")
    private var displayViewModel: CommandDisplayViewModel?
    
    init(executor: ProcessExecutor = ProcessExecutor()) {
        self.executor = executor
    }
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {
        self.displayViewModel = display
    }
    
    func verifyInstallation() async throws {
        let handler = CommandOutputHandler(displayViewModel: displayViewModel)
        do {
            let result = try await executor.execute(
                "restic",
                arguments: ["version"],
                environment: [:],
                outputHandler: handler
            )
            if !result.isSuccess {
                throw ResticError.notInstalled
            }
        } catch {
            throw ResticError.notInstalled
        }
    }
    
    func initializeRepository(name: String, path: URL, password: String) async throws -> Repository {
        let command = ResticCommand.initialize(repository: path, password: password)
        _ = try await executeCommand(command)
        return Repository(name: name, path: path)
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
        let handler = CommandOutputHandler(displayViewModel: displayViewModel)
        
        do {
            let result = try await executor.execute(
                command.executable,
                arguments: command.arguments,
                environment: command.environment,
                outputHandler: handler
            )
            
            if !result.isSuccess {
                throw ResticError.commandFailed(code: Int(result.exitCode), message: result.error)
            }
            
            return result.output
        } catch let error as ProcessError {
            logger.error("Process execution failed: \(error.localizedDescription)")
            throw ResticError.commandExecutionFailed(error)
        } catch {
            logger.error("Unexpected error: \(error.localizedDescription)")
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
        logger.debug("ResticService deinitialised")
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