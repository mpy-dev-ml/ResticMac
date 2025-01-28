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
    case notInitialized
    
    var errorDescription: String? {
        switch self {
        case .executionFailed(let code, let message):
            return "Process failed with exit code \(code): \(message)"
        case .processStartFailed(let message):
            return "Failed to start process: \(message)"
        case .timeout(let duration):
            return "Process timed out after \(Int(duration)) seconds"
        case .notInitialized:
            return "ProcessExecutor not initialized. Call setup() first"
        }
    }
}

@globalActor
actor ProcessExecutorActor {
    static let shared = ProcessExecutorActor()
}

@ProcessExecutorActor
final class ProcessExecutor: @unchecked Sendable {
    private let defaultTimeout: TimeInterval = 300 // 5 minutes default timeout
    private var isInitialized: Bool = false
    
    init() async throws {
        try await setup()
    }
    
    private func setup() async throws {
        guard !isInitialized else { return }
        // Perform any necessary async initialization here
        isInitialized = true
    }
    
    func execute(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        guard isInitialized else {
            throw ProcessError.notInitialized
        }
        
        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                let process = Process()
                var outputData = Data()
                var errorData = Data()
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                
                if let env = environment {
                    process.environment = env
                }
                
                if let workDir = workingDirectory {
                    process.currentDirectoryURL = workDir
                }
                
                // Set up async output handling
                let outputHandle = outputPipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading
                
                Task {
                    for try await line in outputHandle.bytes.lines {
                        outputData.append(line.data(using: .utf8)!)
                        outputData.append("\n".data(using: .utf8)!)
                    }
                }
                
                Task {
                    for try await line in errorHandle.bytes.lines {
                        errorData.append(line.data(using: .utf8)!)
                        errorData.append("\n".data(using: .utf8)!)
                    }
                }
                
                // Start process with timeout
                try process.run()
                
                if let timeout = timeout ?? self.defaultTimeout {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                            process.terminate()
                            throw ProcessError.timeout(duration: timeout)
                        }
                        
                        group.addTask {
                            process.waitUntilExit()
                            try group.cancelAll()
                        }
                        
                        try await group.next()
                    }
                } else {
                    process.waitUntilExit()
                }
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                guard process.terminationStatus == 0 else {
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
            
            return try await group.next() ?? ProcessResult(output: "", error: "", exitCode: -1)
        }
    }
}
