import Foundation
import os

// MARK: - Output Format Protocol

/// Protocol for different output format handlers
protocol OutputFormat: Sendable {
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
        guard let data = line.data(using: .utf8) else {
            return CommandOutput(type: .error, message: "Invalid UTF-8 string: \(line)")
        }
        
        // Try to parse as JSON
        if let _ = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            return CommandOutput(type: .json, message: line)
        }
        
        // Check for specific error patterns
        if line.contains("error:") || line.contains("Fatal:") {
            return CommandOutput(type: .error, message: line)
        }
        
        // Progress indicators
        if let progress = parseProgress(from: line) {
            return CommandOutput(type: .progress(progress), message: line)
        }
        
        // Default to text output
        return CommandOutput(type: .text, message: line)
    }
    
    private func parseProgress(from line: String) -> Double? {
        // Match patterns like [12.34%] or [45.67 percent]
        let pattern = #/\[(\d+\.?\d*)%?\]/#
        if let match = line.firstMatch(of: pattern) {
            return Double(match.1)
        }
        return nil
    }
}

// MARK: - Command Output Handler

/// Handles and processes output from Restic commands
@MainActor
final class CommandOutputHandler: ProcessOutputHandler {
    private weak var displayViewModel: CommandDisplayViewModel?
    private let outputFormat: OutputFormat
    
    init(displayViewModel: CommandDisplayViewModel?, outputFormat: OutputFormat = JSONOutputFormat()) {
        self.displayViewModel = displayViewModel
        self.outputFormat = outputFormat
        Task {
            await displayViewModel?.start()
        }
    }
    
    nonisolated func handleOutput(_ line: String) async {
        let output = outputFormat.parseOutput(line)
        
        await Task { @MainActor in
            displayViewModel?.appendOutput(line)
            
            if case .progress(let percentage) = output.type {
                await displayViewModel?.updateProgress(percentage)
            }
        }.value
    }
    
    nonisolated func handleError(_ line: String) async {
        await Task { @MainActor in
            displayViewModel?.appendError(line)
        }.value
    }
    
    nonisolated func handleComplete(_ exitCode: Int32) {
        Task { @MainActor in
            if exitCode == 0 {
                displayViewModel?.updateStatus(.completed)
            } else {
                displayViewModel?.updateStatus(.failed(code: exitCode))
            }
            displayViewModel?.isProcessing = false
            await displayViewModel?.finish()
        }
    }
}

// MARK: - Supporting Types

struct CommandOutput: Sendable {
    enum OutputType: Sendable {
        case progress(Double)
        case summary
        case unknown
        case text
        case json
        case error
    }
    
    let type: OutputType
    let message: String
}

// MARK: - Progress Types

enum CommandProgress: Sendable {
    case indeterminate
    case percentage(Double)
    case complete
    
    var description: String {
        switch self {
        case .indeterminate:
            return "Processing..."
        case .percentage(let value):
            return "\(Int(value))% Complete"
        case .complete:
            return "Completed"
        }
    }
}
