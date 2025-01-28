import Foundation
import os

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
        guard let data = line.data(using: .utf8) else {
            return CommandOutput(type: .unknown, message: line)
        }
        
        do {
            // Try to parse as JSON
            if let _ = try? JSONSerialization.jsonObject(with: data, options: []) {
                return CommandOutput(type: .unknown, message: line)
            }
        }
        
        // Check for specific error patterns
        if line.contains("error:") || line.contains("Fatal:") {
            return CommandOutput(type: .unknown, message: line)
        }
        
        // Progress indicators
        if line.contains("[") && line.contains("]") && line.contains("%") {
            return CommandOutput(type: .unknown, message: line)
        }
        
        // Default to text output
        return CommandOutput(type: .unknown, message: line)
    }
}

// MARK: - Command Output Handler

/// Handles and processes output from Restic commands
@MainActor
final class CommandOutputHandler: ProcessOutputHandler {
    nonisolated func handleComplete(_ exitCode: Int32) {
        <#code#>
    }
    
    private weak var displayViewModel: CommandDisplayViewModel?
    
    init(displayViewModel: CommandDisplayViewModel?) {
        self.displayViewModel = displayViewModel
        Task {
            await displayViewModel?.start()
        }
    }
    
    func handleOutput(_ line: String) {
        displayViewModel?.appendOutput(line)
    }
    
    func handleError(_ line: String) {
        displayViewModel?.appendError(line)
    }
    
    func handleComplete(_ exitCode: Int32) async {
        await displayViewModel?.finish()
    }
    
    func updateProgress(_ percentage: Double) async {
        await displayViewModel?.updateProgress(percentage)
    }
}

// MARK: - Supporting Types

struct CommandOutput {
    enum OutputType {
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

enum CommandProgress {
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
