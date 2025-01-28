import Foundation

protocol ProcessOutputHandler: Sendable {
    func handleOutput(_ line: String) async
    func handleError(_ line: String) async
    func handleComplete(_ exitCode: Int32)
}

struct ProcessResult: Sendable {
    let output: String
    let error: String
    let exitCode: Int32
    
    var isSuccess: Bool {
        exitCode == 0
    }
}

enum ProcessError: LocalizedError, Sendable {
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

@globalActor
actor ProcessExecutorActor {
    static let shared = ProcessExecutorActor()
}

@ProcessExecutorActor
final class ProcessExecutor: Sendable {
    private let defaultTimeout: TimeInterval = 300 // 5 minutes default timeout
    private var outputHandler: (any ProcessOutputHandler)?
    
    init() {}
    
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
        environment: [String: String]? = nil,
        outputHandler: (any ProcessOutputHandler)? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        await AppLogger.shared.info("Executing command: \(executable) \(arguments.joined(separator: " "))")
        
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        if let env = environment {
            process.environment = env
        }
        
        if let cwd = currentDirectoryURL {
            process.currentDirectoryURL = cwd
        }
        
        let outputData = AsyncStream<Data> { continuation in
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        
        let errorData = AsyncStream<Data> { continuation in
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
        
        // Set up output handling tasks
        let outputTask = Task {
            var collectedOutput = Data()
            for await data in outputData {
                collectedOutput.append(data)
                if let str = String(data: data, encoding: .utf8) {
                    await outputHandler?.handleOutput(str)
                }
            }
            return collectedOutput
        }
        
        let errorTask = Task {
            var collectedError = Data()
            for await data in errorData {
                collectedError.append(data)
                if let str = String(data: data, encoding: .utf8) {
                    await outputHandler?.handleError(str)
                }
            }
            return collectedError
        }
        
        do {
            try process.run()
        } catch {
            throw ProcessError.processStartFailed(message: error.localizedDescription)
        }
        
        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                process.waitUntilExit()
                
                let outputData = await outputTask.value
                let errorData = await errorTask.value
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                outputHandler?.handleComplete(process.terminationStatus)
                
                if process.terminationStatus != 0 {
                    throw ProcessError.executionFailed(
                        exitCode: process.terminationStatus,
                        message: error.isEmpty ? output : error
                    )
                }
                
                return ProcessResult(
                    output: output,
                    error: error,
                    exitCode: process.terminationStatus
                )
            }
            
            group.addTask { [self] in [self]; in
                try await Task.sleep(for: .seconds(timeout ?? self.defaultTimeout))
                process.terminate()
                throw ProcessError.timeout(duration: timeout ?? self.defaultTimeout)
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
