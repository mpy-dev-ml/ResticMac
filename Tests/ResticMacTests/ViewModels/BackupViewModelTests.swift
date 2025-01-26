import XCTest
@testable import ResticMac

@MainActor
final class BackupViewModelTests: XCTestCase {
    var viewModel: BackupViewModel!
    var mockService: MockResticService!
    var commandDisplay: CommandDisplayViewModel!
    let testPath = URL(fileURLWithPath: "/test/path")
    
    override func setUp() {
        super.setUp()
        mockService = MockResticService()
        commandDisplay = CommandDisplayViewModel()
        viewModel = BackupViewModel(resticService: mockService, commandDisplay: commandDisplay)
    }
    
    override func tearDown() {
        viewModel = nil
        mockService = nil
        commandDisplay = nil
        super.tearDown()
    }
    
    func testCreateBackup_NoRepository() async {
        viewModel.selectedPaths = [testPath]
        await viewModel.createBackup()
        
        XCTAssertTrue(viewModel.showError)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isBackingUp)
    }
    
    func testCreateBackup_NoPaths() async {
        viewModel.selectedRepository = Repository(path: testPath, name: "Test Repo")
        await viewModel.createBackup()
        
        XCTAssertTrue(viewModel.showError)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isBackingUp)
    }
    
    func testCreateBackup_Success() async {
        // Setup test data
        let repository = Repository(path: testPath, name: "Test Repo")
        try? repository.savePassword("testPassword")
        viewModel.selectedRepository = repository
        viewModel.selectedPaths = [testPath]
        
        await viewModel.createBackup()
        
        XCTAssertFalse(viewModel.isBackingUp)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(commandDisplay.command, ResticCommand.backup(
            repository: repository.path,
            paths: [testPath],
            password: "testPassword"
        ).displayCommand)
    }
    
    func testCreateBackup_Failure() async {
        // Setup test data
        let repository = Repository(path: testPath, name: "Test Repo")
        try? repository.savePassword("testPassword")
        viewModel.selectedRepository = repository
        viewModel.selectedPaths = [testPath]
        
        // Configure mock to fail
        mockService.shouldThrowError = true
        
        await viewModel.createBackup()
        
        XCTAssertFalse(viewModel.isBackingUp)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.showError)
    }
    
    func testLoadRepositories() async {
        // Create test repositories in storage
        let storage = RepositoryStorage(userDefaults: UserDefaults(suiteName: "com.resticmac.tests"))
        let repository1 = Repository(path: testPath, name: "Test Repo 1")
        let repository2 = Repository(path: testPath.appendingPathComponent("sub"), name: "Test Repo 2")
        try? await storage.saveRepositories([repository1, repository2])
        
        // Create new view model to trigger repository loading
        viewModel = BackupViewModel(resticService: mockService, commandDisplay: commandDisplay)
        
        // Wait a bit for async loading
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(viewModel.repositories.count, 2)
    }
}