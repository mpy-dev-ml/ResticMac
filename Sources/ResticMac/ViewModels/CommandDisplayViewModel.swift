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

final class CommandDisplayViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var output: [OutputLine] = []
    @Published private(set) var status: CommandStatus = .notStarted
    @Published var isProcessing = false
    
    private let maxLines = 1000
    private let queue = DispatchQueue(label: "com.resticmac.commanddisplay", qos: .userInitiated)
    
    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = true
            self.isProcessing = true
            self.status = .running
            self.progress = 0
            self.output.removeAll()
            AppLogger.shared.info("Command execution started")
        }
    }
    
    func finish() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = false
            self.isProcessing = false
            self.progress = 100
            AppLogger.shared.info("Command execution completed")
        }
    }
    
    func updateStatus(_ newStatus: CommandStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.status = newStatus
            AppLogger.shared.info("Command status updated: \(newStatus.description)")
        }
    }
    
    func updateProgress(_ percentage: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.progress = percentage
        }
    }
    
    func appendOutput(_ line: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.appendLine(line, type: .standard)
        }
    }
    
    func appendError(_ line: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.appendLine(line, type: .error)
        }
    }
    
    private func appendLine(_ text: String, type: OutputType) {
        let line = OutputLine(text: text, type: type, timestamp: Date())
        
        DispatchQueue.main.async {
            self.output.append(line)
            if self.output.count > self.maxLines {
                self.output.removeFirst(self.output.count - self.maxLines)
            }
        }
    }
    
    func appendCommand(_ command: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.appendLine("> \(command)", type: .standard)
            AppLogger.shared.info("Executing command: \(command)")
        }
    }
}
