import Foundation

enum ResticError: LocalizedError {
    case notInstalled
    case commandFailed(code: Int, message: String)
    case invalidRepository
    case invalidPassword
    case passwordNotFound
    case invalidOutput(String)
    case backupFailed(Error)
    case networkError(String)
    case permissionDenied
    case unknown(String)
    case initializationFailed(Error)
    case restoreFailed(Error)
    case checkFailed(Error)
    case repositoryInvalid([String])
    
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
        case .invalidOutput(let message):
            return "Invalid command output format: \(message)"
        case .backupFailed(let error):
            return "Backup failed: \(error.localizedDescription)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .permissionDenied:
            return "Permission denied. Please check your file permissions"
        case .unknown(let message):
            return "Unknown error: \(message)"
        case .initializationFailed(let error):
            return "Failed to initialize repository: \(error.localizedDescription)"
        case .restoreFailed(let error):
            return "Failed to restore snapshot: \(error.localizedDescription)"
        case .checkFailed(let error):
            return "Repository check failed: \(error.localizedDescription)"
        case .repositoryInvalid(let errors):
            return "Repository is invalid: \(errors.joined(separator: ", "))"
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
        case .repositoryInvalid:
            return "Try running 'restic check' on the repository to fix any issues"
        default:
            return nil
        }
    }
}