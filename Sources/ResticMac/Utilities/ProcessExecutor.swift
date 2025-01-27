import Foundation
import os

protocol ProcessOutputHandler: AnyObject {
    func handleOutput(_ line: String) async
    func handleError(_ line: String) async
    func handleComplete(_ exitCode: Int32) async
}

struct ProcessResult {
    let output: String
    let error: String
    let exitCode: Int32
    
    var isSuccess: Bool {
        exitCode == 0
    }
}

enum ProcessError: LocalizedError {
    case executionFailed(exitCode: Int32, message: String)
    case processStartFailed(message: String)
    case timeout(duration: TimeInterval)
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let code, let message):
            return "Process failed with exit code \(code): \(message)"
        case .processStartFailed(let message):
            return "Failed to start process: \(message)"
        case .timeout(let duration):
            return "Process timed out after \(Int(duration)) seconds"
        }
    }
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

actor ProcessExecutor {
    private let defaultTimeout: TimeInterval = 300 // 5 minutes default timeout
    private var outputHandler: ProcessOutputHandler?
    
    /// Execute a command and return the result
    /// - Parameters:
    ///   - executable: The command to execute
    ///   - arguments: Array of arguments
    ///   - environment: Optional environment variables
    ///   - outputHandler: Optional handler for process output
    ///   - currentDirectoryURL: Working directory for the process
    ///   - timeout: Optional timeout duration
    /// - Returns: ProcessResult containing output and exit code
    /// - Throws: ProcessError if execution fails
    func execute(
        _ executable: String,
        arguments: [String],
        environment: [String: String],
        outputHandler: ProcessOutputHandler? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        AppLogger.info("Executing command: \(executable) \(arguments.joined(separator: " "))", category: .process)
        
        let process: Process = Process()
        let outputPipe: Pipe = Pipe()
        let errorPipe: Pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = environment
        
        if let cwd = currentDirectoryURL {
            process.currentDirectoryURL = cwd
        }
        
        let outputCollector: DataCollector = DataCollector()
        let errorCollector: DataCollector = DataCollector()
        
        do {
            try process.run()
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await line in outputPipe.fileHandleForReading.bytes.lines {
                        await outputCollector.append(line.data(using: .utf8) ?? Data())
                        await outputHandler?.handleOutput(line)
                        AppLogger.debug("Process output: \(line)", category: .process)
                    }
                }
                
                group.addTask {
                    for try await line in errorPipe.fileHandleForReading.bytes.lines {
                        await errorCollector.append(line.data(using: .utf8) ?? Data())
                        await outputHandler?.handleError(line)
                        AppLogger.error("Process error: \(line)", category: .process)
                    }
                }
                
                if let timeoutDuration = timeout {
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(timeoutDuration * 1_000_000_000))
                        if process.isRunning {
                            process.terminate()
                            throw ProcessError.timeout(duration: timeoutDuration)
                        }
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
                throw ProcessError.executionFailed(exitCode: result.exitCode, message: result.error)
            }
            
            AppLogger.info("Command completed successfully", category: .process)
            await outputHandler?.handleComplete(process.terminationStatus)
            return result
            
        } catch let error as ProcessError {
            AppLogger.error("Process error: \(error.localizedDescription)", category: .process)
            throw error
        } catch {
            AppLogger.error("Process execution failed: \(error.localizedDescription)", category: .process)
            throw ProcessError.processStartFailed(message: error.localizedDescription)
        }
    }
}
