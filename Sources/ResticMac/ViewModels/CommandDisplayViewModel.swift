import Foundation
import SwiftUI

final class CommandDisplayViewModel: ObservableObject {
    @Published var output: String = ""
    @Published var progress: Double = 0.0
    @Published var isRunning: Bool = false
    @Published var error: Error?
    
    func appendOutput(_ line: String) {
        output += line + "\n"
    }
    
    func updateProgress(_ value: Double) {
        progress = value
    }
    
    func handleError(_ error: Error) {
        self.error = error
        isRunning = false
    }
    
    func start() {
        isRunning = true
        progress = 0.0
        output = ""
        error = nil
    }
    
    func complete() {
        isRunning = false
    }
}
