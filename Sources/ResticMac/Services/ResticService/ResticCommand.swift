import Foundation

enum ResticCommand {
    case initialize(repository: URL, password: String)
    case backup(repository: URL, paths: [URL], password: String)
    case snapshots(repository: URL, password: String)
    case check(repository: URL, password: String)
    case restore(repository: URL, snapshot: String, target: URL, password: String)
    case ls(repository: URL, snapshotID: String, password: String)
    
    var executable: String { "restic" }
    
    var arguments: [String] {
        switch self {
        case .initialize(let repository, _):
            return ["init", "--repo", repository.path, "--json"]
            
        case .backup(let repository, let paths, _):
            return ["backup", "--repo", repository.path, "--json"] + paths.map { $0.path }
            
        case .snapshots(let repository, _):
            return ["snapshots", "--repo", repository.path, "--json"]
            
        case .check(let repository, _):
            return ["check", "--repo", repository.path, "--json"]
            
        case .restore(let repository, let snapshot, let target, _):
            return ["restore", snapshot, "--repo", repository.path, "--target", target.path, "--json"]
            
        case .ls(let repository, let snapshotID, _):
            return ["ls", "--repo", repository.path, snapshotID, "--json"]
        }
    }
    
    var environment: [String: String] {
        switch self {
        case .initialize(_, let password),
             .backup(_, _, let password),
             .snapshots(_, let password),
             .check(_, let password),
             .restore(_, _, _, let password),
             .ls(_, _, let password):
            return ["RESTIC_PASSWORD": password]
        }
    }
    
    var timeout: TimeInterval {
        switch self {
        case .backup:
            return 3600 // 1 hour for backups
        case .restore:
            return 3600 // 1 hour for restores
        case .check:
            return 1800 // 30 minutes for checks
        default:
            return 300 // 5 minutes for other operations
        }
    }
}

enum ResticCommandError: LocalizedError {
    case executionFailed(String)
    case invalidOutput(String)
    case missingPassword
    case missingRepository
    case invalidSnapshot
    case invalidTarget
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "Command execution failed: \(message)"
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
        }
    }
}