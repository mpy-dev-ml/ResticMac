import Foundation

struct RepositoryScanResult: Codable, Identifiable {
    let id: UUID
    let path: URL
    var isValid: Bool
    let lastChecked: Date
    var snapshots: [SnapshotInfo]
    
    init(path: URL) {
        self.id = UUID()
        self.path = path
        self.isValid = false
        self.lastChecked = Date()
        self.snapshots = []
    }
    
    enum CodingKeys: String, CodingKey {
        case id, path, isValid, lastChecked, snapshots
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let pathString = try container.decode(String.self, forKey: .path)
        path = URL(fileURLWithPath: pathString)
        isValid = try container.decode(Bool.self, forKey: .isValid)
        lastChecked = try container.decode(Date.self, forKey: .lastChecked)
        snapshots = try container.decode([SnapshotInfo].self, forKey: .snapshots)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path.path, forKey: .path)
        try container.encode(isValid, forKey: .isValid)
        try container.encode(lastChecked, forKey: .lastChecked)
        try container.encode(snapshots, forKey: .snapshots)
    }
}

struct SnapshotInfo: Codable, Identifiable {
    let id: String
    let time: Date
    let paths: [String]
    let hostname: String
    let username: String
    let tags: [String]
    
    enum CodingKeys: String, CodingKey {
        case id, time, paths, hostname, username, tags
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        time = try container.decode(Date.self, forKey: .time)
        paths = try container.decode([String].self, forKey: .paths)
        hostname = try container.decode(String.self, forKey: .hostname)
        username = try container.decode(String.self, forKey: .username)
        tags = try container.decode([String].self, forKey: .tags)
    }
    
    var isOrphaned: Bool {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return time < thirtyDaysAgo && tags.isEmpty
    }
}

struct ScanError: LocalizedError {
    let message: String
    
    var errorDescription: String? {
        return message
    }
}
