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
    private var _data = Data()
    
    func append(_ newData: Data) {
        _data.append(newData)
    }
    
    func getData() -> Data {
        _data
    }
}

func withTimeout<T>(_ duration: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            throw ProcessError.timeout(duration: duration)
        }
        
        let result = try await group.next()!
        group.cancelAll()
        return result
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
        environment: [String: String]?,
        outputHandler: ProcessOutputHandler? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        AppLogger.shared.info("Executing command: \(executable) \(arguments.joined(separator: " "))")
        
        let process: Process = Process()
        let outputPipe: Pipe = Pipe()
        let errorPipe: Pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = environment
        
        if let cwd = currentDirectoryURL {
            process.currentDirectoryURL = cwd
        }
        
        let outputCollector: DataCollector = DataCollector()
        let errorCollector: DataCollector = DataCollector()
        
        // Set up output handling
        Task {
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                if !line.isEmpty {
                    if let data = line.data(using: .utf8) {
                        await outputCollector.append(data)
                        await outputHandler?.handleOutput(line)
                        AppLogger.shared.debug("Process output: \(line)")
                    }
                }
            }
        }
        
        // Set up error handling
        Task {
            for try await line in errorPipe.fileHandleForReading.bytes.lines {
                if !line.isEmpty {
                    if let data = line.data(using: .utf8) {
                        await errorCollector.append(data)
                        await outputHandler?.handleError(line)
                    }
                }
            }
        }
        
        do {
            if let timeoutDuration = timeout {
                try await withTimeout(timeoutDuration) {
                    try process.run()
                    await process.waitUntilExit()
                }
            } else {
                try process.run()
                await process.waitUntilExit()
            }
            
            let result = ProcessResult(
                output: String(decoding: await outputCollector.getData(), as: UTF8.self),
                error: String(decoding: await errorCollector.getData(), as: UTF8.self),
                exitCode: Int32(process.terminationStatus)
            )
            
            if !result.isSuccess {
                AppLogger.shared.error("Process failed with exit code: \(result.exitCode)")
                throw ProcessError.executionFailed(exitCode: result.exitCode, message: result.error)
            }
            
            AppLogger.shared.info("Command completed successfully")
            await outputHandler?.handleComplete(process.terminationStatus)
            return result
            
        } catch let error as ProcessError {
            AppLogger.shared.error("Process error: \(error.localizedDescription)")
            throw error
        } catch {
            AppLogger.shared.error("Process execution failed: \(error.localizedDescription)")
            throw ProcessError.processStartFailed(message: error.localizedDescription)
        }
    }
}
