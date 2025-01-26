import XCTest
@testable import ResticMac

@MainActor
final class CommandDisplayViewModelTests: XCTestCase {
    var viewModel: CommandDisplayViewModel!
    let testCommand = ResticCommand.version
    
    override func setUp() {
        super.setUp()
        viewModel = CommandDisplayViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    func testDisplayCommand() {
        viewModel.displayCommand(testCommand)
        
        XCTAssertEqual(viewModel.command, testCommand.displayCommand)
        XCTAssertTrue(viewModel.output.isEmpty)
        XCTAssertTrue(viewModel.isRunning)
        XCTAssertEqual(viewModel.progress, 0.0)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testAppendOutput() {
        viewModel.appendOutput("Line 1\n")
        XCTAssertEqual(viewModel.output, "Line 1\n")
        
        viewModel.appendOutput("Line 2\n")
        XCTAssertEqual(viewModel.output, "Line 1\nLine 2\n")
    }
    
    func testOutputLineLimiting() {
        // Add more lines than the maximum
        for i in 0...1500 {
            viewModel.appendOutput("Line \(i)\n")
        }
        
        // Check that output is limited
        let lines = viewModel.output.components(separatedBy: .newlines)
        XCTAssertLessThanOrEqual(lines.count, 1001) // 1000 lines + potentially 1 empty string
    }
    
    func testUpdateProgress() {
        viewModel.updateProgress(-0.5) // Should clamp to 0
        XCTAssertEqual(viewModel.progress, 0.0)
        
        viewModel.updateProgress(0.5)
        XCTAssertEqual(viewModel.progress, 0.5)
        
        viewModel.updateProgress(1.5) // Should clamp to 1
        XCTAssertEqual(viewModel.progress, 1.0)
    }
    
    func testCompleteCommand_Success() {
        viewModel.displayCommand(testCommand)
        viewModel.completeCommand()
        
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.progress, 1.0)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testCompleteCommand_Error() {
        viewModel.displayCommand(testCommand)
        let error = ResticError.commandFailed("Test error")
        viewModel.completeCommand(error: error)
        
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.progress, 0.0)
        XCTAssertEqual(viewModel.errorMessage, error.localizedDescription)
    }
    
    func testClear() {
        // Set some state
        viewModel.displayCommand(testCommand)
        viewModel.appendOutput("Test output")
        viewModel.updateProgress(0.5)
        
        // Clear
        viewModel.clear()
        
        // Verify everything is reset
        XCTAssertTrue(viewModel.command.isEmpty)
        XCTAssertTrue(viewModel.output.isEmpty)
        XCTAssertFalse(viewModel.isRunning)
        XCTAssertEqual(viewModel.progress, 0.0)
        XCTAssertNil(viewModel.errorMessage)
    }
}