import Foundation
import Logging

protocol ResticServiceProtocol {
    func setCommandDisplay(_ display: CommandDisplayViewModel) async
    func verifyInstallation() async throws
    func initializeRepository(at path: URL, password: String) async throws -> Repository
    func executeCommand(_ command: ResticCommand) async throws -> String
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult]
    func listSnapshots(repository: Repository) async throws -> [SnapshotInfo]
}

class ResticService: ResticServiceProtocol {
    private let logger = Logger(label: Constants.Loggers.resticService)
    private weak var commandDisplay: CommandDisplayViewModel?
    private var processExecutor: ProcessExecutor!
    
    init() {
        self.processExecutor = ProcessExecutor()
    }
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {
        self.commandDisplay = display
        self.processExecutor = ProcessExecutor(outputHandler: CommandOutputHandler(displayViewModel: display))
    }
    
    func verifyInstallation() async throws {
        do {
            let command = ResticCommand.version
            _ = try await executeCommand(command)
        } catch {
            throw ResticError.notInstalled
        }
    }
    
    func initializeRepository(at path: URL, password: String) async throws -> Repository {
        let repository = Repository(name: path.lastPathComponent, path: path)
        
        // Initialize repository
        let command = ResticCommand.initialize(repository: path, password: password)
        _ = try await executeCommand(command)
        
        // Store password securely
        try repository.storePassword(password)
        
        logger.info("Repository initialised at \(path.path)")
        await commandDisplay?.completeCommand()
        return repository
    }
    
    func executeCommand(_ command: ResticCommand) async throws -> String {
        logger.debug("Executing command: \(command.displayCommand)")
        
        var environment: [String: String] = [:]
        if let password = command.password {
            environment[Constants.Environment.resticPassword] = password
        }
        
        await commandDisplay?.displayCommand(command)
        
        do {
            let result: ProcessResult
            
            // Special handling for find command
            if case .scan = command {
                result = try await processExecutor.execute(
                    command: Constants.Commands.find,
                    arguments: command.arguments,
                    environment: environment
                )
            } else {
                result = try await processExecutor.execute(
                    command: Constants.Commands.restic,
                    arguments: command.arguments,
                    environment: environment
                )
            }
            
            if !result.isSuccess {
                throw ResticError.commandFailed(code: result.exitCode, message: result.error)
            }
            
            return result.output
            
        } catch let error as ProcessError {
            logger.error("Command failed: \(error.localizedDescription)")
            await commandDisplay?.appendOutput("Error: \(error.localizedDescription)\n")
            throw ResticError.commandFailed(code: -1, message: error.localizedDescription)
        } catch {
            logger.error("Command failed: \(error.localizedDescription)")
            await commandDisplay?.appendOutput("Error: \(error.localizedDescription)\n")
            throw ResticError.commandFailed(code: -1, message: error.localizedDescription)
        }
    }
    
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult] {
        logger.info("Scanning for repositories in \(directory.path)")
        
        // Find all potential repository config files
        let command = ResticCommand.scan(directory: directory)
        let output = try await executeCommand(command)
        
        // Process each found config file
        var results: [RepositoryScanResult] = []
        let configPaths = output.split(separator: "\n").map(String.init)
        
        for configPath in configPaths {
            let repoPath = (configPath as NSString).deletingLastPathComponent
            let repoURL = URL(fileURLWithPath: repoPath)
            var result = RepositoryScanResult(path: repoURL)
            
            do {
                // Try to list snapshots to verify repository
                let checkCommand = ResticCommand.check(repository: repoURL, password: "")
                _ = try await executeCommand(checkCommand)
                result.isValid = true
                
                // If valid, try to get snapshots
                let repository = Repository(name: repoURL.lastPathComponent, path: repoURL)
                result.snapshots = try await listSnapshots(repository: repository)
            } catch {
                logger.warning("Repository at \(repoPath) is invalid or inaccessible")
            }
            
            results.append(result)
        }
        
        return results
    }
    
    func listSnapshots(repository: Repository) async throws -> [SnapshotInfo] {
        guard let password = try? repository.retrievePassword() else {
            throw ResticError.passwordNotFound
        }
        
        let command = ResticCommand.snapshots(repository: repository.path, password: password)
        let output = try await executeCommand(command)
        
        guard let data = output.data(using: .utf8) else {
            throw ResticError.invalidOutput
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SnapshotInfo].self, from: data)
    }
}