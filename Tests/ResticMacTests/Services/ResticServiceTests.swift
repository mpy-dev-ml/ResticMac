import XCTest
@testable import ResticMac

final class ResticServiceTests: XCTestCase {
    var service: ResticService!
    var commandDisplay: CommandDisplayViewModel!
    let testPath = URL(fileURLWithPath: "/test/path")
    let testPassword = "testPassword123"
    
    override func setUp() {
        super.setUp()
        service = ResticService()
        commandDisplay = CommandDisplayViewModel()
    }
    
    override func tearDown() {
        service = nil
        commandDisplay = nil
        super.tearDown()
    }
    
    func testVerifyInstallation() async throws {
        // This test assumes restic is installed
        do {
            try await service.verifyInstallation()
        } catch {
            XCTFail("Verification failed: \(error)")
        }
    }
    
    func testCommandDisplay() async {
        await service.setCommandDisplay(commandDisplay)
        
        let command = ResticCommand.version
        XCTAssertEqual(commandDisplay.command, "")
        
        do {
            _ = try await service.executeCommand(command)
            XCTAssertEqual(commandDisplay.command, command.displayCommand)
            XCTAssertFalse(commandDisplay.output.isEmpty)
            XCTAssertFalse(commandDisplay.isRunning)
            XCTAssertNil(commandDisplay.errorMessage)
        } catch {
            XCTFail("Command execution failed: \(error)")
        }
    }
    
    func testCommandError() async {
        await service.setCommandDisplay(commandDisplay)
        
        // Create an invalid command that should fail
        let command = ResticCommand.initialize(path: URL(fileURLWithPath: "/invalid/path"), password: "test")
        
        do {
            _ = try await service.executeCommand(command)
            XCTFail("Command should have failed")
        } catch {
            XCTAssertFalse(commandDisplay.isRunning)
            XCTAssertNotNil(commandDisplay.errorMessage)
        }
    }
    
    func testPasswordHandling() async throws {
        let command = ResticCommand.initialize(path: testPath, password: testPassword)
        XCTAssertEqual(command.password, testPassword)
        XCTAssertFalse(command.displayCommand.contains(testPassword))
    }
    
    func testInitializeRepository() async {
        await service.setCommandDisplay(commandDisplay)
        
        do {
            let repository = try await service.initializeRepository(at: testPath, password: testPassword)
            XCTAssertEqual(repository.path, testPath)
            XCTAssertEqual(repository.name, testPath.lastPathComponent)
            
            // Verify password was saved
            let savedPassword = try repository.retrievePassword()
            XCTAssertEqual(savedPassword, testPassword)
        } catch {
            XCTFail("Repository initialization failed: \(error)")
        }
    }
}