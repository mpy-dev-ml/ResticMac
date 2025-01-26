import Foundation
import SwiftShell
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
    private let logger = Logger(label: "com.resticmac.ResticService")
    private weak var commandDisplay: CommandDisplayViewModel?
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {
        self.commandDisplay = display
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
        
        var context = CustomContext(main)
        if let password = command.password {
            context.env["RESTIC_PASSWORD"] = password
        }
        
        await commandDisplay?.displayCommand(command)
        
        do {
            let runAsync: AsyncCommand
            
            // Special handling for find command
            if case .scan = command {
                runAsync = context.runAsync("find", command.arguments)
            } else {
                runAsync = context.runAsync("restic", command.arguments)
            }
            
            var outputBuffer = ""
            var errorBuffer = ""
            
            // Handle output streaming
            for line in runAsync.stdout.lines() {
                let output = line + "\n"
                outputBuffer += output
                await commandDisplay?.appendOutput(output)
            }
            
            for line in runAsync.stderror.lines() {
                let error = "Error: " + line + "\n"
                errorBuffer += error
                await commandDisplay?.appendOutput(error)
            }
            
            let result = try runAsync.finish()
            if result.exitcode() != 0 {
                throw ResticError.commandFailed(code: result.exitcode(), message: errorBuffer)
            }
            
            return outputBuffer
        } catch let error as ResticError {
            logger.error("Command failed: \(error.localizedDescription)")
            await commandDisplay?.appendOutput("Error: \(error.localizedDescription)\n")
            throw error
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