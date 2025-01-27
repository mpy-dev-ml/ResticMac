import Foundation
import Combine
import OSLog
import Logging

/// Result type for process execution
struct ProcessResult {
    let output: String
    let error: String
    let exitCode: Int32
    
    var isSuccess: Bool {
        exitCode == 0
    }
}

/// Error types for process execution
enum ProcessError: LocalizedError {
    case executionFailed(exitCode: Int32, message: String)
    case processTerminated
    case outputDecodingFailed
    case timeout(duration: TimeInterval)
    case cleanupFailed
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let code, let message):
            return "Process failed with exit code \(code): \(message)"
        case .processTerminated:
            return "Process was terminated unexpectedly"
        case .outputDecodingFailed:
            return "Failed to decode process output"
        case .timeout(let duration):
            return "The operation timed out after \(Int(duration)) seconds. Please try again or increase the timeout duration."
        case .cleanupFailed:
            return "Failed to clean up process resources"
        }
    }
}

/// Protocol for process execution output handling
protocol ProcessOutputHandler {
    func handleOutput(_ line: String) async
    func handleError(_ line: String) async
    func handleComplete(_ exitCode: Int32) async
}

actor DataCollector {
    private var data = Data()
    
    func append(_ newData: Data) {
        data.append(newData)
    }
    
    func toString() -> String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

/// Utility class for executing shell commands
actor ProcessExecutor {
    private let logger = Logger(subsystem: "com.resticmac", category: "ProcessExecutor")
    internal var outputHandler: ProcessOutputHandler?
    private let defaultTimeout: TimeInterval = 300 // 5 minutes default timeout
    
    init(outputHandler: ProcessOutputHandler? = nil) {
        self.outputHandler = outputHandler
    }
    
    /// Execute a command and return the result
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Array of arguments
    ///   - environment: Optional environment variables
    ///   - currentDirectoryURL: Working directory for the process
    ///   - timeout: Optional timeout duration
    /// - Returns: ProcessResult containing output and exit code
    func execute(
        command: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        logger.info("Executing command: \(command) \(arguments.joined(separator: " "))")
        
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
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
        
        let outputCollector = DataCollector()
        let errorCollector = DataCollector()
        
        // Setup output handling
        let outputStream = outputPipe.fileHandleForReading
        let errorStream = errorPipe.fileHandleForReading
        
        outputStream.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await outputCollector.append(data)
                if let str = String(data: data, encoding: .utf8) {
                    await self?.outputHandler?.handleOutput(str)
                    self?.logger.debug("Process output: \(str)")
                }
            }
        }
        
        errorStream.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await errorCollector.append(data)
                if let str = String(data: data, encoding: .utf8) {
                    await self?.outputHandler?.handleError(str)
                    self?.logger.error("Process error: \(str)")
                }
            }
        }
        
        // Start process with timeout
        try process.run()
        
        let timeoutDuration = timeout ?? defaultTimeout
        let startTime = Date()
        
        while process.isRunning {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms check interval
            
            if Date().timeIntervalSince(startTime) > timeoutDuration {
                do {
                    try cleanup(process, outputStream, errorStream)
                } catch {
                    logger.error("Cleanup failed during timeout: \(error.localizedDescription)")
                }
                logger.error("Process timed out after \(timeoutDuration) seconds")
                throw ProcessError.timeout(duration: timeoutDuration)
            }
        }
        
        // Clean up file handles
        do {
            try cleanup(process, outputStream, errorStream)
        } catch {
            logger.error("Cleanup failed after process completion: \(error.localizedDescription)")
        }
        
        guard process.terminationStatus == 0 else {
            logger.error("Process failed with exit code: \(process.terminationStatus)")
            throw ProcessError.executionFailed(exitCode: process.terminationStatus, message: await errorCollector.toString())
        }
        
        logger.info("Command completed successfully")
        await outputHandler?.handleComplete(process.terminationStatus)
        return ProcessResult(
            output: await outputCollector.toString(),
            error: await errorCollector.toString(),
            exitCode: process.terminationStatus
        )
    }
    
    private func cleanup(_ process: Process, _ outputStream: FileHandle, _ errorStream: FileHandle) throws {
        outputStream.readabilityHandler = nil
        errorStream.readabilityHandler = nil
        
        if process.isRunning {
            process.terminate()
        }
        
        do {
            try outputStream.close()
            try errorStream.close()
        } catch {
            logger.error("Failed to clean up process resources: \(error.localizedDescription)")
            throw ProcessError.cleanupFailed
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
