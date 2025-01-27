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
        // Implement parsing logic here
        // For now, just return a default output
        return CommandOutput(type: .unknown, message: line)
    }
}

// MARK: - Command Output Handler

/// Handles and processes output from Restic commands
final class CommandOutputHandler: ProcessOutputHandler {
    private weak var displayViewModel: CommandDisplayViewModel?
    
    init(displayViewModel: CommandDisplayViewModel?) {
        self.displayViewModel = displayViewModel
        Task { @MainActor in
            displayViewModel?.start()
        }
    }
    
    func handleOutput(_ line: String) async {
        for subline in line.split(separator: "\n") {
            let lineStr = String(subline)
            await displayViewModel?.appendOutput(lineStr)
            AppLogger.debug("Command output: \(lineStr)", category: .process)
            
            // Check for progress information
            if let progress = parseProgress(from: lineStr) {
                await displayViewModel?.updateProgress(progress)
            }
        }
    }
    
    func handleError(_ line: String) async {
        for subline in line.split(separator: "\n") {
            let lineStr = String(subline)
            await displayViewModel?.appendOutput(lineStr)
            AppLogger.error("Command error: \(lineStr)", category: .process)
        }
    }
    
    func handleComplete(_ exitCode: Int32) async {
        await displayViewModel?.finish()
        AppLogger.info("Command completed with exit code: \(exitCode)", category: .process)
    }
    
    private func parseProgress(from line: String) -> Double? {
        // Example progress line: "[42.32%] 12 / 100 files"
        let progressPattern = #"\[(\d+\.\d+)%\]"#
        
        guard let range = line.range(of: progressPattern, options: .regularExpression),
              let percentStr = line[range].split(separator: "%").first?.dropFirst(),
              let percent = Double(percentStr) else {
            return nil
        }
        
        return percent
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
