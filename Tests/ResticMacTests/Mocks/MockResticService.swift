import Foundation
@testable import ResticMac

actor MockResticService: ResticServiceProtocol {
    var verifyInstallationCalled = false
    var initializeRepositoryCalled = false
    var lastInitializedPath: URL?
    var lastInitializedPassword: String?
    var shouldThrowError = false
    var commandDisplay: CommandDisplayViewModel?
    
    func setCommandDisplay(_ display: CommandDisplayViewModel) {
        self.commandDisplay = display
    }
    
    func verifyInstallation() async throws {
        verifyInstallationCalled = true
        if shouldThrowError {
            throw ResticError.notInstalled
        }
    }
    
    func initializeRepository(at path: URL, password: String) async throws -> Repository {
        initializeRepositoryCalled = true
        lastInitializedPath = path
        lastInitializedPassword = password
        
        if shouldThrowError {
            throw ResticError.commandFailed("Mock error")
        }
        
        return Repository(path: path, name: path.lastPathComponent)
    }
    
    func executeCommand(_ command: ResticCommand) async throws -> String {
        if shouldThrowError {
            throw ResticCommandError.executionFailed("Mock error")
        }
        return "Mock command output"
    }
    
    // Helper method to reset state between tests
    func reset() {
        verifyInstallationCalled = false
        initializeRepositoryCalled = false
        lastInitializedPath = nil
        lastInitializedPassword = nil
        shouldThrowError = false
        commandDisplay = nil
    }
}