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
}

@MainActor
final class ResticService: ResticServiceProtocol, ObservableObject {
    private let logger = Logger(label: "com.resticmac.ResticService")
    private let executor: ProcessExecutor
    private var commandDisplay: CommandDisplayViewModel?
    
    init(executor: ProcessExecutor = ProcessExecutor(), commandDisplay: CommandDisplayViewModel? = nil) {
        self.executor = executor
        self.commandDisplay = commandDisplay
    }
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {
        self.commandDisplay = display
        executor.outputHandler = CommandOutputHandler(displayViewModel: display)
    }
    
    func verifyInstallation() async throws {
        let result = try await executor.execute(
            command: "which",
            arguments: ["restic"]
        )
        guard result.isSuccess else {
            throw ResticError.notInstalled
        }
    }
    
    func initializeRepository(name: String, path: URL, password: String) async throws -> Repository {
        try await verifyInstallation()
        
        let command = ResticCommand.initRepository(at: path, password: password)
        commandDisplay?.start()
        
        do {
            _ = try await executeCommand(command)
            logger.info("Repository initialised at \(path.path)")
            let repository = Repository(name: name, path: path)
            commandDisplay?.complete()
            return repository
            
        } catch {
            logger.error("Failed to initialize repository: \(error.localizedDescription)")
            throw ResticError.initializationFailed(error)
        }
    }
    
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult] {
        try await verifyInstallation()
        
        let command = ResticCommand.scanRepository(repository: directory, password: "")
        
        do {
            let output = try await executeCommand(command)
            return try parseRepositoryScanResults(from: output)
        } catch {
            logger.error("Failed to scan for repositories: \(error.localizedDescription)")
            throw error
        }
    }
    
    func checkRepository(repository: Repository) async throws -> RepositoryStatus {
        try await verifyInstallation()
        
        guard let password = try? repository.retrievePassword() else {
            throw ResticError.passwordNotFound
        }
        
        let command = ResticCommand.check(repository: repository.path, password: password)
        
        do {
            let output = try await executeCommand(command)
            return try parseRepositoryStatus(from: output)
        } catch {
            logger.error("Failed to check repository: \(error.localizedDescription)")
            throw ResticError.checkFailed(error)
        }
    }
    
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot {
        try await verifyInstallation()
        
        guard let password = try? repository.retrievePassword() else {
            throw ResticError.passwordNotFound
        }
        
        let command = ResticCommand.backup(repository: repository.path, paths: paths, password: password)
        commandDisplay?.start()
        
        do {
            let output = try await executeCommand(command)
            let snapshot = try parseSnapshotResult(from: output)
            commandDisplay?.complete()
            return snapshot
        } catch {
            logger.error("Failed to create snapshot: \(error.localizedDescription)")
            throw ResticError.backupFailed(error)
        }
    }
    
    func listSnapshots(repository: Repository) async throws -> [Snapshot] {
        try await verifyInstallation()
        
        guard let password = try? repository.retrievePassword() else {
            throw ResticError.passwordNotFound
        }
        
        let command = ResticCommand.listSnapshots(repository: repository.path, password: password)
        
        do {
            let output = try await executeCommand(command)
            return try parseSnapshotList(from: output)
        } catch {
            logger.error("Failed to list snapshots: \(error.localizedDescription)")
            throw ResticError.commandFailed(code: -1, message: error.localizedDescription)
        }
    }
    
    func restoreSnapshot(repository: Repository, snapshot: String, targetPath: URL) async throws {
        try await verifyInstallation()
        
        guard let password = try? repository.retrievePassword() else {
            throw ResticError.passwordNotFound
        }
        
        let command = ResticCommand.restore(repository: repository.path, snapshot: snapshot, target: targetPath, password: password)
        commandDisplay?.start()
        
        do {
            _ = try await executeCommand(command)
            commandDisplay?.complete()
        } catch {
            logger.error("Failed to restore snapshot: \(error.localizedDescription)")
            throw ResticError.restoreFailed(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func executeCommand(_ command: ResticCommand) async throws -> String {
        logger.info("Executing command: \(command.displayCommand)")
        
        var environment: [String: String] = [:]
        if let password = command.password {
            environment["RESTIC_PASSWORD"] = password
        }
        
        let result = try await executor.execute(
            command: "restic",
            arguments: command.arguments,
            environment: environment
        )
        
        if !result.isSuccess {
            throw ResticError.commandFailed(code: Int(result.exitCode), message: result.error)
        }
        
        return result.output
    }
    
    private func parseRepositoryScanResults(from output: String) throws -> [RepositoryScanResult] {
        guard let data = output.data(using: .utf8) else {
            throw ResticError.invalidOutput("Could not convert output to data")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([RepositoryScanResult].self, from: data)
    }
    
    private func parseRepositoryStatus(from output: String) throws -> RepositoryStatus {
        guard let data = output.data(using: .utf8) else {
            throw ResticError.invalidOutput("Could not convert output to data")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(RepositoryStatus.self, from: data)
    }
    
    private func parseSnapshotResult(from output: String) throws -> Snapshot {
        guard let data = output.data(using: .utf8) else {
            throw ResticError.invalidOutput("Could not convert output to data")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(Snapshot.self, from: data)
    }
    
    private func parseSnapshotList(from output: String) throws -> [Snapshot] {
        guard let data = output.data(using: .utf8) else {
            throw ResticError.invalidOutput("Could not convert output to data")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([Snapshot].self, from: data)
    }
}