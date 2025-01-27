import Foundation

enum ResticCommand {
    case version
    case initRepository(at: URL, password: String)
    case backup(repository: URL, paths: [URL], password: String)
    case check(repository: URL, password: String)
    case scanRepository(repository: URL, password: String)
    case listSnapshots(repository: URL, password: String)
    case restore(repository: URL, snapshot: String, target: URL, password: String)
    
    var displayCommand: String {
        switch self {
        case .version:
            return "restic version"
        case .initRepository(let path, _):
            return "restic init --repository \(path.path) --json"
        case .backup(let repository, let paths, _):
            let pathsString = paths.map { $0.path }.joined(separator: " ")
            return "restic backup --repository \(repository.path) \(pathsString) --json"
        case .check(let repository, _):
            return "restic check --repository \(repository.path) --json"
        case .scanRepository(let repository, _):
            return "restic snapshots --repository \(repository.path) --json"
        case .listSnapshots(let repository, _):
            return "restic snapshots --repository \(repository.path) --json"
        case .restore(let repository, let snapshot, let target, _):
            return "restic restore \(snapshot) --repository \(repository.path) --target \(target.path) --json"
        }
    }
    
    var arguments: [String] {
        switch self {
        case .version:
            return ["version"]
        case .initRepository(let path, _):
            return ["init", "--repository", path.path, "--json"]
        case .backup(let repository, let paths, _):
            var args = ["backup", "--repository", repository.path, "--json"]
            args.append(contentsOf: paths.map { $0.path })
            return args
        case .check(let repository, _):
            return ["check", "--repository", repository.path, "--json"]
        case .scanRepository(let repository, _):
            return ["snapshots", "--repository", repository.path, "--json"]
        case .listSnapshots(let repository, _):
            return ["snapshots", "--repository", repository.path, "--json"]
        case .restore(let repository, let snapshot, let target, _):
            return ["restore", snapshot, "--repository", repository.path, "--target", target.path, "--json"]
        }
    }
    
    var password: String? {
        switch self {
        case .version:
            return nil
        case .initRepository(_, let password),
             .backup(_, _, let password),
             .check(_, let password),
             .scanRepository(_, let password),
             .listSnapshots(_, let password),
             .restore(_, _, _, let password):
            return password
        }
    }
    
    var requiresRepository: Bool {
        switch self {
        case .version:
            return false
        default:
            return true
        }
    }
    
    var requiresPassword: Bool {
        switch self {
        case .version:
            return false
        default:
            return true
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