import Foundation

@MainActor
final class CommandDisplayViewModel: ObservableObject {
    @Published var output: String = ""
    @Published var progress: Double = 0
    @Published var isRunning: Bool = false
    @Published var hasError: Bool = false
    @Published var errorMessage: String = ""
    
    func start() {
        output = ""
        progress = 0
        isRunning = true
        hasError = false
        errorMessage = ""
    }
    
    func appendOutput(_ text: String) {
        output += text + "\n"
    }
    
    func updateProgress(_ value: Double) {
        progress = value
    }
    
    func complete() {
        isRunning = false
    }
    
    func handleError(_ error: Error) {
        hasError = true
        errorMessage = error.localizedDescription
        isRunning = false
    }
}
