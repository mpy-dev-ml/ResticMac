import Foundation
import os

enum OutputType {
    case standard
    case error
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
    
    private let maxLines = 1000
    
    func start() async {
        isRunning = true
        progress = 0
        output.removeAll()
        AppLogger.shared.info("Command execution started")
    }
    
    func finish() async {
        isRunning = false
        progress = 100
        AppLogger.shared.info("Command execution completed")
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
    private func appendLine(_ line: String, type: OutputType) {
        output.append(OutputLine(text: line, type: type, timestamp: Date()))
        
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
