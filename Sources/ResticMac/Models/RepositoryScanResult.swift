import Foundation

struct RepositoryScanResult: Codable, Identifiable {
    let id: UUID
    let path: URL
    var isValid: Bool
    var snapshots: [Snapshot]?
    
    init(path: URL, isValid: Bool = false, snapshots: [Snapshot]? = nil) {
        self.id = UUID()
        self.path = path
        self.isValid = isValid
        self.snapshots = snapshots
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case path
        case isValid = "is_valid"
        case snapshots
    }
}
