import SwiftUI
import Logging

@MainActor
class CommandDisplayViewModel: ObservableObject {
    private let logger = Logger(label: "com.resticmac.CommandDisplayViewModel")
    
    @Published var command: String = ""
    @Published var output: String = ""
    @Published var isRunning = false
    @Published var progress: Double = 0.0
    @Published var errorMessage: String?
    
    private var outputLines: [String] = []
    private let maxLines = 1000  // Limit output lines to prevent memory issues
    
    func displayCommand(_ command: ResticCommand) {
        self.command = command.displayCommand
        self.output = ""
        self.outputLines = []
        self.isRunning = true
        self.progress = 0.0
        self.errorMessage = nil
    }
    
    func appendOutput(_ newOutput: String) {
        // Split output into lines and add to our buffer
        let lines = newOutput.components(separatedBy: .newlines)
        outputLines.append(contentsOf: lines)
        
        // Keep only the last maxLines
        if outputLines.count > maxLines {
            outputLines.removeFirst(outputLines.count - maxLines)
        }
        
        // Update the displayed output
        output = outputLines.joined(separator: "\n")
    }
    
    func updateProgress(_ progress: Double) {
        self.progress = min(max(progress, 0.0), 1.0)
    }
    
    func completeCommand(error: Error? = nil) {
        isRunning = false
        progress = error == nil ? 1.0 : 0.0
        if let error = error {
            errorMessage = error.localizedDescription
            logger.error("Command failed: \(error.localizedDescription)")
        }
    }
    
    func clear() {
        command = ""
        output = ""
        outputLines = []
        isRunning = false
        progress = 0.0
        errorMessage = nil
    }
}