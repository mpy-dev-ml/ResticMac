import Foundation
import os

enum OutputType {
    case standard
    case error
}

enum CommandStatus {
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
final class CommandDisplayViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var output: [OutputLine] = []
    @Published private(set) var status: CommandStatus = .notStarted
    @Published var isProcessing = false
    
    private let maxLines = 1000
    
    func start() async {
        isRunning = true
        isProcessing = true
        status = .running
        progress = 0
        output.removeAll()
        AppLogger.shared.info("Command execution started")
    }
    
    func finish() async {
        isRunning = false
        isProcessing = false
        progress = 100
        AppLogger.shared.info("Command execution completed")
    }
    
    func updateStatus(_ newStatus: CommandStatus) {
        status = newStatus
        AppLogger.shared.info("Command status updated: \(newStatus.description)")
    }
    
    func updateProgress(_ percentage: Double) async {
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
    
    @MainActor
    private func appendLine(_ text: String, type: OutputType) {
        let line = OutputLine(text: text, type: type, timestamp: Date())
        output.append(line)
        
        // Keep output buffer size under control
        if output.count > maxLines {
            output.removeFirst(output.count - maxLines)
        }
    }
    
    @MainActor
    func appendCommand(_ command: String) {
        appendLine("> \(command)", type: .standard)
        AppLogger.shared.info("Executing command: \(command)")
    }
}
