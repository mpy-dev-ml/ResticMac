import Foundation

struct RepositoryStatus {
    let state: State
    let errors: [String]
    
    enum State: String {
        case ok
        case corrupted
        case locked
        case unknown
    }
    
    var isValid: Bool {
        state == .ok
    }
    
    static let ok = RepositoryStatus(state: .ok, errors: [])
    static let unknown = RepositoryStatus(state: .unknown, errors: ["Unknown repository status"])
}

struct RepositoryStatusDetails: Codable {
    let isValid: Bool
    let errors: [String]
    let lastCheck: Date
    
    enum CodingKeys: String, CodingKey {
        case isValid = "is_valid"
        case errors
        case lastCheck = "last_check"
    }
}
