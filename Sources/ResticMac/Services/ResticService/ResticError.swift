import Foundation

enum ResticError: LocalizedError {
    case notInstalled
    case initializationFailed(String)
    case commandFailed(code: Int, message: String)
    case invalidOutput(String)
    case checkFailed(Error)
    case commandExecutionFailed(ProcessError)
    case unknown(String)
    case passwordNotFound
    case repositoryInvalid([String])
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Restic is not installed"
        case .initializationFailed(let message):
            return "Failed to initialize repository: \(message)"
        case .commandFailed(let code, let message):
            return "Command failed with code \(code): \(message)"
        case .invalidOutput(let message):
            return "Invalid output: \(message)"
        case .checkFailed(let error):
            return "Failed to check repository: \(error.localizedDescription)"
        case .commandExecutionFailed(let error):
            return "Process execution failed: \(error.localizedDescription)"
        case .unknown(let message):
            return "Unexpected error: \(message)"
        case .passwordNotFound:
            return "Repository password not found"
        case .repositoryInvalid(let errors):
            return "Repository is invalid: \(errors.joined(separator: ", "))"
        }
    }
}