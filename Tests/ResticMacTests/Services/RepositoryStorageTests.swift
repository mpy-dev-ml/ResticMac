import XCTest
@testable import ResticMac

final class RepositoryStorageTests: XCTestCase {
    var storage: RepositoryStorage!
    var userDefaults: UserDefaults!
    let testPath = URL(fileURLWithPath: "/test/path")
    
    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "com.resticmac.tests")
        storage = RepositoryStorage(userDefaults: userDefaults)
    }
    
    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "com.resticmac.tests")
        storage = nil
        userDefaults = nil
        super.tearDown()
    }
    
    func testSaveAndLoadRepositories() async throws {
        let repository1 = Repository(path: testPath, name: "Test Repo 1")
        let repository2 = Repository(path: testPath.appendingPathComponent("sub"), name: "Test Repo 2")
        
        // Save repositories
        try await storage.saveRepositories([repository1, repository2])
        
        // Load repositories
        let loadedRepos = try await storage.loadRepositories()
        
        XCTAssertEqual(loadedRepos.count, 2)
        XCTAssertEqual(loadedRepos[0].id, repository1.id)
        XCTAssertEqual(loadedRepos[1].id, repository2.id)
    }
    
    func testAddRepository() async throws {
        let repository = Repository(path: testPath, name: "Test Repo")
        
        // Add repository
        try await storage.addRepository(repository)
        
        // Verify repository was added
        let loadedRepos = try await storage.loadRepositories()
        XCTAssertEqual(loadedRepos.count, 1)
        XCTAssertEqual(loadedRepos[0].id, repository.id)
    }
    
    func testRemoveRepository() async throws {
        let repository1 = Repository(path: testPath, name: "Test Repo 1")
        let repository2 = Repository(path: testPath.appendingPathComponent("sub"), name: "Test Repo 2")
        
        // Add repositories
        try await storage.saveRepositories([repository1, repository2])
        
        // Remove one repository
        try await storage.removeRepository(repository1)
        
        // Verify repository was removed
        let loadedRepos = try await storage.loadRepositories()
        XCTAssertEqual(loadedRepos.count, 1)
        XCTAssertEqual(loadedRepos[0].id, repository2.id)
    }
    
    func testLoadEmptyRepositories() async throws {
        let repositories = try await storage.loadRepositories()
        XCTAssertTrue(repositories.isEmpty)
    }
    
    func testSaveInvalidData() async {
        // Corrupt the data in UserDefaults
        userDefaults.set("invalid data".data(using: .utf8), forKey: "com.resticmac.repositories")
        
        do {
            _ = try await storage.loadRepositories()
            XCTFail("Should throw an error for invalid data")
        } catch {
            XCTAssertTrue(error is StorageError)
        }
    }
}