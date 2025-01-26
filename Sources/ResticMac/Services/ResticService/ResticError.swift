import Foundation

enum ResticError: LocalizedError {
    case notInstalled
    case commandFailed(code: Int, message: String)
    case invalidRepository
    case invalidPassword
    case passwordNotFound
    case invalidOutput
    case backupFailed(String)
    case networkError(String)
    case permissionDenied
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Restic is not installed. Please install it using Homebrew: brew install restic"
        case .commandFailed(let code, let message):
            return "Command failed with exit code \(code): \(message)"
        case .invalidRepository:
            return "Invalid or corrupted repository"
        case .invalidPassword:
            return "Invalid repository password"
        case .passwordNotFound:
            return "Repository password not found"
        case .invalidOutput:
            return "Invalid command output format"
        case .backupFailed(let message):
            return "Backup failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .permissionDenied:
            return "Permission denied. Please check your file permissions"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .notInstalled:
            return "Run 'brew install restic' in Terminal to install Restic"
        case .invalidPassword:
            return "Please check your repository password and try again"
        case .passwordNotFound:
            return "Please set your repository password and try again"
        case .permissionDenied:
            return "Try running the app again with appropriate permissions"
        default:
            return nil
        }
    }
}