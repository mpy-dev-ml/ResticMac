import Foundation
import Logging

@globalActor
actor RepositoryStorageActor {
    static let shared = RepositoryStorageActor()
}

@RepositoryStorageActor
class RepositoryStorage {
    private let logger = Logging.Logger(label: "com.resticmac.RepositoryStorage")
    private let repositoryKey = "com.resticmac.repositories"
    
    // Use static shared instance to avoid Sendable issues
    static let shared = RepositoryStorage()
    
    private init() {}
    
    func loadRepositories() throws -> [Repository] {
        guard let data = UserDefaults.standard.data(forKey: repositoryKey) else {
            logger.info("No saved repositories found")
            return []
        }
        
        do {
            let repositories = try JSONDecoder().decode([Repository].self, from: data)
            logger.info("Loaded \(repositories.count) repositories")
            return repositories
        } catch {
            logger.error("Failed to load repositories: \(error.localizedDescription)")
            throw StorageError.loadFailed(error.localizedDescription)
        }
    }
    
    func addRepository(_ repository: Repository) throws {
        var repositories = try loadRepositories()
        repositories.append(repository)
        try saveRepositories(repositories)
        logger.info("Added repository: \(repository.name)")
    }
    
    func removeRepository(_ repository: Repository) throws {
        var repositories = try loadRepositories()
        repositories.removeAll { $0.id == repository.id }
        try saveRepositories(repositories)
        logger.info("Removed repository: \(repository.name)")
    }
    
    private func saveRepositories(_ repositories: [Repository]) throws {
        do {
            let data = try JSONEncoder().encode(repositories)
            UserDefaults.standard.set(data, forKey: repositoryKey)
            logger.info("Saved \(repositories.count) repositories")
        } catch {
            logger.error("Failed to save repositories: \(error.localizedDescription)")
            throw StorageError.saveFailed(error.localizedDescription)
        }
    }
}

enum StorageError: LocalizedError {
    case saveFailed(String)
    case loadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let message):
            return "Failed to save repositories: \(message)"
        case .loadFailed(let message):
            return "Failed to load repositories: \(message)"
        }
    }
}