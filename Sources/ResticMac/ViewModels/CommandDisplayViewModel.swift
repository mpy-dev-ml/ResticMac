import Foundation
import os

enum OutputType {
    case standard
    case error
}

enum CommandStatus: CustomStringConvertible {
    case notStarted
    case running
    case completed
    case failed(code: Int32)
    
    var description: String {
        switch self {
        case .notStarted:
            return "Not Started"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .failed(let code):
            return "Failed (Exit Code: \(code))"
        }
    }
}

struct OutputLine: Identifiable {
    let id = UUID()
    let text: String
    let type: OutputType
    let timestamp: Date
}

@MainActor
final class CommandDisplayViewModel: ObservableObject, @unchecked Sendable {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var output: [OutputLine] = []
    @Published private(set) var status: CommandStatus = .notStarted
    @Published var isProcessing = false
    
    private let maxLines = 1000
    private let queue = DispatchQueue(label: "com.resticmac.commanddisplay", qos: .userInitiated)
    
    func start() {
        isRunning = true
        isProcessing = true
        status = .running
        progress = 0
        output.removeAll()
        Task { @AppLoggerActor in
            AppLogger.shared.info("Command execution started", metadata: ["status": "started"] as [String: String])
        }
    }
    
    func finish() {
        isRunning = false
        isProcessing = false
        progress = 100
        Task { @AppLoggerActor in
            AppLogger.shared.info("Command execution completed", metadata: ["status": "completed"] as [String: String])
        }
    }
    
    func updateStatus(_ newStatus: CommandStatus) {
        status = newStatus
        Task { @AppLoggerActor in
            AppLogger.shared.info("Command status updated", metadata: ["status": newStatus.description] as [String: String])
        }
    }
    
    func updateProgress(_ percentage: Double) {
        progress = percentage
    }
    
    func appendOutput(_ line: String) {
        Task { @MainActor in
            appendLine(line, type: .standard)
        }
    }
    
    func appendError(_ line: String) {
        Task { @MainActor in
            appendLine(line, type: .error)
        }
    }
    
    private func appendLine(_ text: String, type: OutputType) {
        let line = OutputLine(text: text, type: type, timestamp: Date())
        output.append(line)
        if output.count > maxLines {
            output.removeFirst(output.count - maxLines)
        }
    }
    
    func appendCommand(_ command: String) {
        Task { @MainActor in
            appendLine("> \(command)", type: .standard)
            Task { @AppLoggerActor in
                AppLogger.shared.info("Executing command", metadata: ["command": command] as [String: String])
            }
        }
    }
}
