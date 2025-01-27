import Foundation
import Logging

@MainActor
final class CommandDisplayViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var output: [String] = []
    
    private let maxLines = 1000
    private let logger = Logger(label: "com.resticmac.CommandDisplayViewModel")
    
    func start() {
        isRunning = true
        progress = 0
        output.removeAll()
        logger.info("Command execution started")
    }
    
    func finish() {
        isRunning = false
        progress = 100
        logger.info("Command execution completed")
    }
    
    func updateProgress(_ percentage: Double) {
        progress = percentage
    }
    
    func appendOutput(_ line: String) {
        output.append(line)
        
        // Trim old lines if we exceed maxLines
        if output.count > maxLines {
            output.removeFirst(output.count - maxLines)
        }
    }
}
