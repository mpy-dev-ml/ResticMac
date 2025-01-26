import XCTest
import KeychainAccess
@testable import ResticMac

final class RepositoryTests: XCTestCase {
    var repository: Repository!
    let testPath = URL(fileURLWithPath: "/test/path")
    let testPassword = "testPassword123"
    
    override func setUp() {
        super.setUp()
        repository = Repository(path: testPath, name: "Test Repo")
    }
    
    override func tearDown() {
        // Clean up keychain after each test
        let keychain = Keychain(service: "com.resticmac.repositories")
        try? keychain.remove(repository.id.uuidString)
        repository = nil
        super.tearDown()
    }
    
    func testRepositoryInitialization() {
        XCTAssertEqual(repository.path, testPath)
        XCTAssertEqual(repository.name, "Test Repo")
        XCTAssertNotNil(repository.createdAt)
        XCTAssertNotNil(repository.id)
    }
    
    func testPasswordStorage() throws {
        // Save password
        try repository.savePassword(testPassword)
        
        // Retrieve password
        let retrievedPassword = try repository.retrievePassword()
        XCTAssertEqual(retrievedPassword, testPassword)
    }
    
    func testPasswordRetrieval_WhenNotSet() {
        XCTAssertThrowsError(try repository.retrievePassword()) { error in
            XCTAssertTrue(error is KeychainError)
        }
    }
    
    func testPasswordUpdate() throws {
        // Initial password
        try repository.savePassword(testPassword)
        
        // Update password
        let newPassword = "newPassword456"
        try repository.savePassword(newPassword)
        
        // Verify update
        let retrievedPassword = try repository.retrievePassword()
        XCTAssertEqual(retrievedPassword, newPassword)
    }
    
    func testRepositoryCodable() throws {
        // Create repository with test data
        let originalRepo = Repository(path: testPath, name: "Test Repo")
        try originalRepo.savePassword(testPassword)
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalRepo)
        
        // Decode
        let decoder = JSONDecoder()
        let decodedRepo = try decoder.decode(Repository.self, from: data)
        
        // Verify
        XCTAssertEqual(originalRepo.id, decodedRepo.id)
        XCTAssertEqual(originalRepo.path, decodedRepo.path)
        XCTAssertEqual(originalRepo.name, decodedRepo.name)
        XCTAssertEqual(originalRepo.createdAt, decodedRepo.createdAt)
        
        // Verify password persists through coding
        let retrievedPassword = try decodedRepo.retrievePassword()
        XCTAssertEqual(retrievedPassword, testPassword)
    }
    
    func testEquatable() {
        let repo1 = Repository(path: testPath, name: "Test Repo")
        let repo2 = Repository(path: testPath, name: "Test Repo")
        let repo3 = Repository(path: testPath, name: "Different Name")
        
        XCTAssertNotEqual(repo1, repo2) // Different IDs
        XCTAssertNotEqual(repo1, repo3)
        XCTAssertEqual(repo1, repo1) // Same instance
    }
}