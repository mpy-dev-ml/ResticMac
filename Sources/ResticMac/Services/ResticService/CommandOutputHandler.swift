import Foundation
import os

// MARK: - Output Format Protocol

/// Protocol for different output format handlers
protocol OutputFormat: Sendable {
    func format(_ data: Data) -> String
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
    
    func format(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return "Invalid JSON data"
        }
        
        return String(describing: json)
    }
}

// MARK: - Command Output Handler

/// Handles and processes output from Restic commands
final class CommandOutputHandler: ProcessOutputHandler {
    private let displayViewModel: CommandDisplayViewModel?
    private let outputFormat: any OutputFormat
    
    init(displayViewModel: CommandDisplayViewModel?, outputFormat: any OutputFormat = JSONOutputFormat()) {
        self.displayViewModel = displayViewModel
        self.outputFormat = outputFormat
        Task { @MainActor in
            displayViewModel?.start()
        }
    }
    
    nonisolated func handleOutput(_ line: String) {
        Task { @MainActor [displayViewModel] in
            displayViewModel?.appendOutput(line)
        }
    }
    
    nonisolated func handleError(_ line: String) {
        Task { @MainActor [displayViewModel] in
            displayViewModel?.appendError(line)
        }
    }
    
    nonisolated func handleComplete(_ exitCode: Int32) {
        Task { @MainActor [displayViewModel] in
            if exitCode == 0 {
                displayViewModel?.finish()
            } else {
                displayViewModel?.updateStatus(.failed(code: exitCode))
            }
        }
    }
    
    nonisolated func handleOutput(_ data: Data) {
        let formattedOutput = outputFormat.format(data)
        Task { @MainActor [displayViewModel] in
            displayViewModel?.appendOutput(formattedOutput)
        }
    }
    
    nonisolated func handleError(_ data: Data) {
        let errorOutput = String(data: data, encoding: .utf8) ?? ""
        Task { @MainActor [displayViewModel] in
            displayViewModel?.appendError(errorOutput)
        }
    }
    
    nonisolated func handleCompletion(_ exitCode: Int32) {
        Task { @MainActor [displayViewModel] in
            if exitCode == 0 {
                displayViewModel?.finish()
            } else {
                displayViewModel?.updateStatus(.failed(code: exitCode))
            }
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
}
