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
    
    func start() {
        isRunning = true
        progress = 0
        output.removeAll()
        AppLogger.info("Command execution started", category: .process)
    }
    
    func finish() {
        isRunning = false
        progress = 100
        AppLogger.info("Command execution completed", category: .process)
    }
    
    func updateProgress(_ percentage: Double) {
        progress = percentage
    }
    
    func appendOutput(_ line: String) {
        appendLine(line, type: .standard)
    }
    
    func appendError(_ line: String) {
        appendLine(line, type: .error)
    }
    
    private func appendLine(_ line: String, type: OutputType) {
        output.append(OutputLine(text: line, type: type, timestamp: Date()))
        
        // Trim old lines if we exceed maxLines
        if output.count > maxLines {
            output.removeFirst(output.count - maxLines)
        }
    }
}
