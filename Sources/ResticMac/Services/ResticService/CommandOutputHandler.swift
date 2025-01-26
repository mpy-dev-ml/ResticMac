import Foundation

final class CommandOutputHandler: ProcessOutputHandler {
    private weak var displayViewModel: CommandDisplayViewModel?
    
    init(displayViewModel: CommandDisplayViewModel?) {
        self.displayViewModel = displayViewModel
    }
    
    func handleOutput(_ line: String) {
        Task {
            await displayViewModel?.appendOutput(line)
        }
    }
    
    func handleError(_ line: String) {
        Task {
            await displayViewModel?.appendOutput("Error: " + line)
        }
    }
}
