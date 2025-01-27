import Foundation
import KeychainAccess

struct Repository: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let path: URL
    var lastChecked: Date?
    var lastBackup: Date?
    let createdAt: Date
    
    init(name: String, path: URL) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.createdAt = Date()
    }
    
    // Custom initializer for creating with all properties
    init(id: UUID = UUID(), name: String, path: URL, createdAt: Date = Date(), lastChecked: Date? = nil, lastBackup: Date? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.lastChecked = lastChecked
        self.lastBackup = lastBackup
    }
    
    // Codable conformance for URL
    enum CodingKeys: String, CodingKey {
        case id, name, path, lastChecked, lastBackup, createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let pathString = try container.decode(String.self, forKey: .path)
        path = URL(fileURLWithPath: pathString)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastChecked = try container.decodeIfPresent(Date.self, forKey: .lastChecked)
        lastBackup = try container.decodeIfPresent(Date.self, forKey: .lastBackup)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path.path, forKey: .path)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastChecked, forKey: .lastChecked)
        try container.encodeIfPresent(lastBackup, forKey: .lastBackup)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Repository, rhs: Repository) -> Bool {
        lhs.id == rhs.id
    }
    
    // Mark keychain as transient since it's not Codable
    private var keychain: Keychain {
        Keychain(service: "com.resticmac.repository")
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