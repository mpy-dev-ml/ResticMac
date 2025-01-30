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
    case deletionFailed(path: URL, underlying: Error)
    
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
        case .deletionFailed(let path, let error):
            return "Failed to delete repository at \(path.path): \(error.localizedDescription)"
        }
    }
}

enum EntryType: String, Codable {
    case file = "file"
    case directory = "dir"
    case symlink = "symlink"
}

struct RepositoryState: Codable {
    let version: Int
    let id: String
    let status: String
}

struct RepositoryStats: Codable {
    let totalSize: UInt64
    let totalFiles: UInt64
    let uniqueSize: UInt64
}

struct RepositoryHealth: Codable {
    let isLocked: Bool
    let needsIndexRebuild: Bool
    let errors: [String]
    
    var isHealthy: Bool {
        !isLocked && !needsIndexRebuild && errors.isEmpty
    }
}

struct Progress: Codable {
    let messageType: String
    let percentDone: Double
    let totalFiles: Int
    let totalBytes: UInt64
    let currentFiles: Int
    let currentBytes: UInt64
    
    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case percentDone = "percent_done"
        case totalFiles = "total_files"
        case totalBytes = "total_bytes"
        case currentFiles = "files_done"
        case currentBytes = "bytes_done"
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
        case ls(snapshot: String, path: String?)
        case unlock
        
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
            case .ls(let snapshot, let path):
                if let path = path {
                    return ["ls", snapshot, path, "--json"]
                } else {
                    return ["ls", snapshot, "--json"]
                }
            case .unlock:
                return ["unlock"]
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