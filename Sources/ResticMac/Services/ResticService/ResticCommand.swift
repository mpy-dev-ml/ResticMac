import Foundation

enum ResticCommand {
    case version
    case initialize(repository: URL, password: String)
    case backup(repository: URL, paths: [URL], password: String)
    case check(repository: URL, password: String)
    case snapshots(repository: URL, password: String)
    case scan(directory: URL)
    case scanRepository(repository: URL, password: String)
    case listSnapshots(repository: URL, password: String)
    
    var command: String {
        switch self {
        case .version:
            return "\(Constants.Commands.restic) version"
        case .initialize(let path, _):
            return "\(Constants.Commands.restic) init --repo \"\(path.path)\""
        case .backup(let repository, let paths, _):
            let pathsString = paths.map { "\"\($0.path)\"" }.joined(separator: " ")
            return "\(Constants.Commands.restic) --repo \"\(repository.path)\" backup \(pathsString)"
        case .check(let repository, _):
            return "\(Constants.Commands.restic) --repo \"\(repository.path)\" check"
        case .snapshots(let repository, _):
            return "\(Constants.Commands.restic) --repo \"\(repository.path)\" snapshots \(Constants.Arguments.json)"
        case .scan(let directory):
            return Constants.Commands.find
        case .scanRepository(let repository, _):
            return "\(Constants.Commands.restic) --repo \"\(repository.path)\" scan"
        case .listSnapshots(let repository, _):
            return "\(Constants.Commands.restic) --repo \"\(repository.path)\" snapshots"
        }
    }
    
    var displayCommand: String {
        // Return command with password redacted for display
        var cmd = command
        if let password = password {
            cmd = cmd.replacingOccurrences(of: password, with: "********")
        }
        return cmd
    }
    
    var arguments: [String] {
        switch self {
        case .version:
            return ["version"]
        case .initialize(let repository, _):
            return ["init", "--repo", repository.path]
        case .backup(let repository, let paths, _):
            return ["backup", "--repo", repository.path] + paths.map { $0.path }
        case .check(let repository, _):
            return ["check", "--repo", repository.path]
        case .snapshots(let repository, _):
            return ["snapshots", "--repo", repository.path, Constants.Arguments.json]
        case .scan(let directory):
            return [directory.path, "-type", "f", "-name", "config"]
        case .scanRepository(let repository, _):
            return ["scan", "--repo", repository.path]
        case .listSnapshots(let repository, _):
            return ["snapshots", "--repo", repository.path]
        }
    }
    
    var password: String? {
        switch self {
        case .version:
            return nil
        case .initialize(_, let password),
             .backup(_, _, let password),
             .check(_, let password),
             .snapshots(_, let password),
             .scanRepository(_, let password),
             .listSnapshots(_, let password):
            return password
        case .scan:
            return nil
        }
    }
}

enum ResticCommandError: LocalizedError {
    case executionFailed(String)
    case invalidOutput(String)
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "Command execution failed: \(message)"
        case .invalidOutput(let message):
            return "Invalid command output: \(message)"
        }
    }
}