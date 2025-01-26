import SwiftUI
import Logging

@MainActor
class RepositoryViewModel: ObservableObject {
    private let logger = Logger(label: "com.resticmac.RepositoryViewModel")
    private let resticService: ResticService
    private let storage: RepositoryStorage
    
    @Published var repositories: [Repository] = []
    @Published var isCreatingRepository = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    init(resticService: ResticService,
         storage: RepositoryStorage) {
        self.resticService = resticService
        self.storage = storage
        
        // Load repositories
        Task {
            await loadRepositories()
        }
    }
    
    static func create() async -> RepositoryViewModel {
        let resticService = ResticService()
        let storage = await RepositoryStorage.shared
        
        return RepositoryViewModel(
            resticService: resticService,
            storage: storage
        )
    }
    
    func createRepository(path: URL, name: String, password: String) async {
        isCreatingRepository = true
        errorMessage = nil
        
        do {
            let repository = try await resticService.initializeRepository(at: path, password: password)
            try await Task.detached { @RepositoryStorageActor in
                try self.storage.addRepository(repository)
            }.value
            repositories.append(repository)
            isCreatingRepository = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isCreatingRepository = false
            logger.error("Failed to create repository: \(error.localizedDescription)")
        }
    }
    
    func removeRepository(_ repository: Repository) async {
        do {
            try await Task.detached { @RepositoryStorageActor in
                try self.storage.removeRepository(repository)
            }.value
            repositories.removeAll { $0.id == repository.id }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            logger.error("Failed to remove repository: \(error.localizedDescription)")
        }
    }
    
    private func loadRepositories() async {
        do {
            repositories = try await Task.detached { @RepositoryStorageActor in
                try self.storage.loadRepositories()
            }.value
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            logger.error("Failed to load repositories: \(error.localizedDescription)")
        }
    }
    
    func validatePath(_ path: URL) -> Bool {
        // Check if path exists and is writable
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        
        return FileManager.default.isWritableFile(atPath: path.path)
    }
    
    func validatePassword(_ password: String) -> Bool {
        // Basic password validation
        return password.count >= 8
    }
}