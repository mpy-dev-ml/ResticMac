import Foundation
import Logging
import ResticMac // Add import for ResticError

// MARK: - Output Format Protocol

/// Protocol for different output format handlers
protocol OutputFormat {
    func parseOutput(_ line: String) -> CommandOutput
}

/// JSON implementation of OutputFormat
struct JSONOutputFormat: OutputFormat {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    func decode<T: Decodable>(_ data: Data) throws -> T {
        try decoder.decode(T.self, from: data)
    }
    
    func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }
    
    func parseOutput(_ line: String) -> CommandOutput {
        // Implement parsing logic here
        // For now, just return a default output
        return CommandOutput(type: .unknown, message: line)
    }
}

// MARK: - Command Output Handler

/// Handles and processes output from Restic commands
final class CommandOutputHandler: ProcessOutputHandler {
    private weak var displayViewModel: CommandDisplayViewModel?
    private let logger = Logger(label: "com.resticmac.CommandOutputHandler")
    private let outputFormat: OutputFormat
    
    init(displayViewModel: CommandDisplayViewModel?, outputFormat: OutputFormat = JSONOutputFormat()) {
        self.displayViewModel = displayViewModel
        self.outputFormat = outputFormat
    }
    
    func handleOutput(_ line: String) async {
        let output = outputFormat.parseOutput(line)
        await processOutput(output)
    }
    
    func handleError(_ line: String) async {
        if line.contains("error:") {
            logger.error("Restic error: \(line)")
            await displayViewModel?.appendOutput("Error: \(line)")
            await displayViewModel?.handleError(ResticError.commandFailed(code: -1, message: line))
        } else {
            await displayViewModel?.appendOutput(line)
        }
    }
    
    func handleComplete(_ exitCode: Int32) async {
        await displayViewModel?.appendOutput("\nCommand completed with exit code: \(exitCode)\n")
        if exitCode == 0 {
            await displayViewModel?.complete()
        }
    }
    
    private func processOutput(_ output: CommandOutput) async {
        switch output.type {
        case .progress(let progress):
            await displayViewModel?.updateProgress(progress)
            await displayViewModel?.appendOutput(output.message)
        case .summary:
            await displayViewModel?.appendOutput(output.message)
            await displayViewModel?.complete()
        case .unknown:
            await displayViewModel?.appendOutput(output.message)
        }
    }
}

// MARK: - Supporting Types

struct CommandOutput {
    enum OutputType {
        case progress(Double)
        case summary
        case unknown
    }
    
    let type: OutputType
    let message: String
}
