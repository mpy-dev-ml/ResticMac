import Foundation

struct Snapshot: Codable, Identifiable {
    let id: String
    let time: Date
    let paths: [String]
    let hostname: String
    let username: String
    let excludes: [String]?
    let tags: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case time
        case paths
        case hostname
        case username
        case excludes
        case tags
    }
}
