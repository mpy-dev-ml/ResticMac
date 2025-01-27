import Foundation
import os

/// Protocol for process execution output handling
protocol ProcessOutputHandler {
    func handleOutput(_ line: String) async
    func handleError(_ line: String) async
    func handleComplete(_ exitCode: Int32) async
}

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
struct ProcessError: LocalizedError {
    let message: String
    let exitCode: Int32
    
    var errorDescription: String? {
        message
    }
}

/// Data collector for process output
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
    internal var outputHandler: ProcessOutputHandler?
    private let defaultTimeout: TimeInterval = 300 // 5 minutes default timeout
    
    init(outputHandler: ProcessOutputHandler? = nil) {
        self.outputHandler = outputHandler
    }
    
    /// Execute a command and return the result
    /// - Parameters:
    ///   - executable: The command to execute
    ///   - arguments: Array of arguments
    ///   - environment: Optional environment variables
    ///   - currentDirectoryURL: Working directory for the process
    ///   - timeout: Optional timeout duration
    /// - Returns: ProcessResult containing output and exit code
    func execute(
        _ executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        AppLogger.info("Executing command: \(executable) \(arguments.joined(separator: " "))", category: .process)
        
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
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
                    AppLogger.debug("Process output: \(str)", category: .process)
                }
            }
        }
        
        errorStream.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await errorCollector.append(data)
                if let str = String(data: data, encoding: .utf8) {
                    await self?.outputHandler?.handleError(str)
                    AppLogger.error("Process error: \(str)", category: .process)
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
                    AppLogger.error("Cleanup failed during timeout: \(error.localizedDescription)", category: .process)
                }
                AppLogger.error("Process timed out after \(timeoutDuration) seconds", category: .process)
                throw ProcessError(message: "The operation timed out after \(Int(timeoutDuration)) seconds. Please try again or increase the timeout duration.", exitCode: -1)
            }
        }
        
        // Clean up file handles
        do {
            try cleanup(process, outputStream, errorStream)
        } catch {
            AppLogger.error("Cleanup failed after process completion: \(error.localizedDescription)", category: .process)
        }
        
        guard process.terminationStatus == 0 else {
            AppLogger.error("Process failed with exit code: \(process.terminationStatus)", category: .process)
            throw ProcessError(message: "Process failed with exit code: \(process.terminationStatus)", exitCode: process.terminationStatus)
        }
        
        AppLogger.info("Command completed successfully", category: .process)
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
            AppLogger.error("Failed to clean up process resources: \(error.localizedDescription)", category: .process)
            throw ProcessError(message: "Failed to clean up process resources", exitCode: -1)
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
                        command,
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
    
    /// Execute a command and return the result
    /// - Parameters:
    ///   - executable: The command to execute
    ///   - arguments: Array of arguments
    ///   - environment: Optional environment variables
    /// - Returns: ProcessResult containing output and exit code
    func execute(
        _ executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessResult {
        AppLogger.info("Executing command: \(executable) \(arguments.joined(separator: " "))", category: .process)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.environment = environment
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        let outputCollector = DataCollector()
        let errorCollector = DataCollector()
        
        do {
            try process.run()
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await line in outputPipe.fileHandleForReading.bytes.lines {
                        await outputCollector.append(line.data(using: .utf8) ?? Data())
                        AppLogger.debug("Process output: \(line)", category: .process)
                    }
                }
                
                group.addTask {
                    for try await line in errorPipe.fileHandleForReading.bytes.lines {
                        await errorCollector.append(line.data(using: .utf8) ?? Data())
                        AppLogger.error("Process error: \(line)", category: .process)
                    }
                }
                
                try await group.waitForAll()
            }
            
            process.waitUntilExit()
            
            let result = ProcessResult(
                output: await outputCollector.toString(),
                error: await errorCollector.toString(),
                exitCode: process.terminationStatus
            )
            
            if !result.isSuccess {
                AppLogger.error("Process failed with exit code: \(result.exitCode)", category: .process)
            } else {
                AppLogger.info("Command completed successfully", category: .process)
            }
            
            return result
        } catch {
            AppLogger.error("Process execution failed: \(error.localizedDescription)", category: .process)
            throw ProcessError(message: error.localizedDescription, exitCode: -1)
        }
    }
}
