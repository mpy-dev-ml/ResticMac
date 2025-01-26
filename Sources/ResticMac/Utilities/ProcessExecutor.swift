import Foundation
import Combine
import OSLog

/// Result type for process execution
struct ProcessResult {
    let output: String
    let error: String
    let exitCode: Int32
    
    var isSuccess: Bool {
        exitCode == Constants.ExitCodes.success
    }
}

/// Error types for process execution
enum ProcessError: LocalizedError {
    case executionFailed(exitCode: Int32, message: String)
    case processTerminated
    case outputDecodingFailed
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let code, let message):
            return "Process failed with exit code \(code): \(message)"
        case .processTerminated:
            return "Process was terminated unexpectedly"
        case .outputDecodingFailed:
            return "Failed to decode process output"
        }
    }
}

/// Protocol for process execution output handling
protocol ProcessOutputHandler {
    func handleOutput(_ line: String)
    func handleError(_ line: String)
}

/// Utility class for executing shell commands
final class ProcessExecutor {
    private let logger = Logger(label: "com.resticmac.ProcessExecutor")
    private var outputHandler: ProcessOutputHandler?
    
    init(outputHandler: ProcessOutputHandler? = nil) {
        self.outputHandler = outputHandler
    }
    
    /// Execute a command and return the result
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Array of arguments
    ///   - environment: Optional environment variables
    ///   - currentDirectoryURL: Working directory for the process
    /// - Returns: ProcessResult containing output and exit code
    func execute(
        command: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        // Configure process
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        if let env = environment {
            process.environment = env
        }
        
        if let workingDirectory = currentDirectoryURL {
            process.currentDirectoryURL = workingDirectory
        }
        
        // Setup output handling
        var outputData = Data()
        var errorData = Data()
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    // Handle standard output
                    outputPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        outputData.append(data)
                        
                        if let str = String(data: data, encoding: .utf8) {
                            self.outputHandler?.handleOutput(str)
                        }
                    }
                    
                    // Handle standard error
                    errorPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        errorData.append(data)
                        
                        if let str = String(data: data, encoding: .utf8) {
                            self.outputHandler?.handleError(str)
                        }
                    }
                    
                    // Process termination handler
                    process.terminationHandler = { process in
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        errorPipe.fileHandleForReading.readabilityHandler = nil
                        
                        let output = String(data: outputData, encoding: .utf8) ?? ""
                        let error = String(data: errorData, encoding: .utf8) ?? ""
                        
                        if process.terminationStatus != Constants.ExitCodes.success {
                            continuation.resume(throwing: ProcessError.executionFailed(
                                exitCode: process.terminationStatus,
                                message: error
                            ))
                        } else {
                            continuation.resume(returning: ProcessResult(
                                output: output,
                                error: error,
                                exitCode: process.terminationStatus
                            ))
                        }
                    }
                    
                    // Launch process
                    self.logger.debug("Executing: \(command) \(arguments.joined(separator: " "))")
                    try process.run()
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
    
    /// Execute a command and stream its output line by line
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Array of arguments
    ///   - environment: Optional environment variables
    ///   - currentDirectoryURL: Working directory for the process
    /// - Returns: AsyncStream of output lines
    func executeWithStream(
        command: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await execute(
                        command: command,
                        arguments: arguments,
                        environment: environment,
                        currentDirectoryURL: currentDirectoryURL
                    )
                    
                    result.output.split(separator: "\n").forEach { line in
                        continuation.yield(String(line))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
