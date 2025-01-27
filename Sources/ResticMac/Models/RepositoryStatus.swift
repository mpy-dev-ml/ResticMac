import Foundation

struct RepositoryStatus: Codable {
    let isValid: Bool
    let errors: [String]
    let lastCheck: Date
    
    enum CodingKeys: String, CodingKey {
        case isValid = "is_valid"
        case errors
        case lastCheck = "last_check"
    }
}
