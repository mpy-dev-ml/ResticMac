import Foundation

protocol ProcessOutputHandler: Sendable {
    func handleOutput(_ line: String)
    func handleError(_ line: String)
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

enum ProcessError: LocalizedError {
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
            return "ProcessExecutor not initialized. Call initialize() first"
        }
    }
}

actor ProcessExecutor {
    private let defaultTimeout: TimeInterval = 300 // 5 minutes default timeout
    private var isInitialized: Bool = false
    
    init() {}
    
    func initialize() async throws {
        guard !isInitialized else { return }
        // Perform any necessary async initialization here
        isInitialized = true
    }
    
    private func setup() {
        // Any additional setup needed
    }
    
    func execute(_ command: String, 
                arguments: [String], 
                environment: [String: String]? = nil,
                timeout: TimeInterval? = nil,
                handler: (any ProcessOutputHandler)? = nil) async throws -> ProcessResult {
        guard isInitialized else {
            throw ProcessError.notInitialized
        }
        
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
        
        let handlerCopy = handler // Capture handler value
        
        actor OutputCollector {
            private(set) var data = Data()
            
            func append(_ newData: Data) {
                data.append(newData)
            }
            
            func getData() -> Data {
                data
            }
        }
        
        let outputCollector = OutputCollector()
        let errorCollector = OutputCollector()
        
        // Set up output handling
        outputPipe.fileHandleForReading.readabilityHandler = { [handlerCopy] handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task {
                    await outputCollector.append(data)
                    if let line = String(data: data, encoding: .utf8) {
                        handlerCopy?.handleOutput(line)
                    }
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { [handlerCopy] handle in
            let data = handle.availableData
            if !data.isEmpty {
                Task {
                    await errorCollector.append(data)
                    if let line = String(data: data, encoding: .utf8) {
                        handlerCopy?.handleError(line)
                    }
                }
            }
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Clean up file handles
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            
            let outputData = await outputCollector.getData()
            let errorData = await errorCollector.getData()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            handlerCopy?.handleComplete(process.terminationStatus)
            
            return ProcessResult(
                output: output,
                error: error,
                exitCode: process.terminationStatus
            )
        } catch {
            throw ProcessError.processStartFailed(message: error.localizedDescription)
        }
    }
}
