import Foundation

enum ResticError: LocalizedError {
    case notInstalled
    case validationFailed(errors: [String])
    case initializationFailed(underlying: Error)
    case commandFailed(underlying: Error)
    case invalidOutput(String)
    case missingPassword
    case missingRepository
    case invalidSnapshot
    case invalidTarget
    case invalidName(String)
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Restic is not installed"
        case .validationFailed(let errors):
            return errors.joined(separator: "\n")
        case .initializationFailed(let error):
            return "Failed to initialise repository: \(error.localizedDescription)"
        case .commandFailed(let error):
            return "Command failed: \(error.localizedDescription)"
        case .invalidOutput(let message):
            return "Invalid command output: \(message)"
        case .missingPassword:
            return "Repository password is required"
        case .missingRepository:
            return "Repository path is required"
        case .invalidSnapshot:
            return "Invalid snapshot ID"
        case .invalidTarget:
            return "Invalid restore target path"
        case .invalidName(let message):
            return message
        }
    }
}

struct ResticCommand {
    let executable: String = "/usr/local/bin/restic"
    let repository: URL
    let password: String
    let operation: Operation
    
    enum Operation {
        case initialize
        case check
        case backup(paths: [URL])
        case snapshots
        case restore(snapshot: String, target: URL)
        case ls(snapshotID: String)
        
        var arguments: [String] {
            switch self {
            case .initialize:
                return ["init"]
            case .check:
                return ["check"]
            case .backup(let paths):
                return ["backup"] + paths.map { $0.path }
            case .snapshots:
                return ["snapshots", "--json"]
            case .restore(let snapshot, let target):
                return ["restore", snapshot, "--target", target.path]
            case .ls(let snapshotID):
                return ["ls", snapshotID, "--json"]
            }
        }
    }
    
    var arguments: [String] {
        ["--repo", repository.path] + operation.arguments
    }
    
    var environment: [String: String] {
        ["RESTIC_PASSWORD": password]
    }
    
    init(repository: URL, password: String, operation: Operation) {
        self.repository = repository
        self.password = password
        self.operation = operation
    }
}