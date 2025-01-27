import Foundation
import KeychainAccess

struct Repository: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let path: URL
    let createdAt: Date
    var lastBackup: Date?
    
    // Mark keychain as transient since it's not Codable
    private var keychain: Keychain {
        Keychain(service: "com.resticmac.repository")
    }
    
    init(id: UUID = UUID(), name: String, path: URL) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = Date()
        self.lastBackup = nil
    }
    
    init(id: UUID = UUID(), name: String, path: URL, createdAt: Date, lastBackup: Date?) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.lastBackup = lastBackup
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Repository, rhs: Repository) -> Bool {
        lhs.id == rhs.id
    }
    
    func storePassword(_ password: String) throws {
        try keychain.set(password, key: id.uuidString)
    }
    
    func retrievePassword() throws -> String {
        guard let password = try keychain.get(id.uuidString) else {
            throw RepositoryError.passwordNotFound
        }
        return password
    }
    
    func removePassword() throws {
        try keychain.remove(id.uuidString)
    }
}

enum RepositoryError: LocalizedError {
    case passwordNotFound
    
    var errorDescription: String? {
        switch self {
        case .passwordNotFound:
            return "Password not found for repository"
        }
    }
}