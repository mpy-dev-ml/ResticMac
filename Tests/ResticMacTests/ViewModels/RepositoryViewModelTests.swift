import XCTest
@testable import ResticMac

@MainActor
final class RepositoryViewModelTests: XCTestCase {
    var viewModel: RepositoryViewModel!
    var mockService: MockResticService!
    let testPath = URL(fileURLWithPath: "/test/path")
    let testPassword = "testPassword123"
    
    override func setUp() {
        super.setUp()
        mockService = MockResticService()
        viewModel = RepositoryViewModel(resticService: mockService)
    }
    
    override func tearDown() {
        viewModel = nil
        mockService = nil
        super.tearDown()
    }
    
    func testCreateRepository_Success() async {
        await viewModel.createRepository(path: testPath, name: "Test Repo", password: testPassword)
        
        XCTAssertTrue(await mockService.initializeRepositoryCalled)
        XCTAssertEqual(await mockService.lastInitializedPath, testPath)
        XCTAssertEqual(await mockService.lastInitializedPassword, testPassword)
        XCTAssertFalse(viewModel.isCreatingRepository)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.repositories.count, 1)
    }
    
    func testCreateRepository_Failure() async {
        await mockService.reset()
        mockService.shouldThrowError = true
        
        await viewModel.createRepository(path: testPath, name: "Test Repo", password: testPassword)
        
        XCTAssertTrue(await mockService.initializeRepositoryCalled)
        XCTAssertFalse(viewModel.isCreatingRepository)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.repositories.isEmpty)
    }
    
    func testValidatePath() {
        // Test invalid path
        XCTAssertFalse(viewModel.validatePath(URL(fileURLWithPath: "/nonexistent/path")))
        
        // Test valid path (this assumes /tmp exists and is writable)
        XCTAssertTrue(viewModel.validatePath(URL(fileURLWithPath: "/tmp")))
    }
    
    func testValidatePassword() {
        // Test invalid passwords
        XCTAssertFalse(viewModel.validatePassword(""))
        XCTAssertFalse(viewModel.validatePassword("short"))
        
        // Test valid password
        XCTAssertTrue(viewModel.validatePassword("validpassword123"))
    }
    
    func testRemoveRepository() async {
        // First create a repository
        await viewModel.createRepository(path: testPath, name: "Test Repo", password: testPassword)
        XCTAssertEqual(viewModel.repositories.count, 1)
        
        // Then remove it
        if let repository = viewModel.repositories.first {
            await viewModel.removeRepository(repository)
            XCTAssertTrue(viewModel.repositories.isEmpty)
        } else {
            XCTFail("Repository should exist")
        }
    }
}