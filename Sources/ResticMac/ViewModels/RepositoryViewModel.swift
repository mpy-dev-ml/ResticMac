import Foundation
import SwiftUI
import Combine

final class RepositoryViewModel: ObservableObject {
    @Published private(set) var repositories: [Repository] = []
    @Published private(set) var isLoading = false
    @Published var isCreatingRepository = false
    @Published var selectedRepository: Repository?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var validationState = RepositoryValidationState()
    
    private let resticService: ResticService
    private let commandDisplay: CommandDisplayViewModel
    private var cancellables = Set<AnyCancellable>()
    
    var hasSelectedRepository: Bool {
        selectedRepository != nil
    }
    
    // Dictionary for O(1) lookups
    private var repositoryMap: [UUID: Repository] {
        Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
    }
    
    init(commandDisplay: CommandDisplayViewModel) {
        self.commandDisplay = commandDisplay
        
        Task { @MainActor in
            self.resticService = await ResticService.shared
            await resticService.setCommandDisplay(commandDisplay)
            await scanForRepositories()
        }
    }
    
    @MainActor
    func scanForRepositories() async {
        isLoading = true
        
        do {
            // Use the home directory as the default scan location
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let results = try await resticService.scanForRepositories(in: homeDirectory)
            self.repositories = results.compactMap { result in
                guard result.isValid else { return nil }
                return Repository(name: result.path.lastPathComponent, path: result.path)
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }
    
    func repository(withId id: UUID) -> Repository? {
        repositoryMap[id]
    }
    
    func selectRepository(_ repository: Repository?) {
        AppLogger.shared.debug("RepositoryViewModel: Selecting repository: \(repository?.name ?? "nil")")
        DispatchQueue.main.async {
            if let repository = repository {
                // Ensure we're using the latest version from our repositories array
                let updatedRepository = self.repositoryMap[repository.id] ?? repository
                AppLogger.shared.debug("RepositoryViewModel: Found repository in map: \(updatedRepository.name)")
                self.selectedRepository = updatedRepository
            } else {
                AppLogger.shared.debug("RepositoryViewModel: Clearing repository selection")
                self.selectedRepository = nil
            }
            self.objectWillChange.send()
        }
    }
    
    func createRepository(name: String, at path: URL) {
        isCreatingRepository = true
        
        Task { @MainActor in
            do {
                let repository = try await resticService.initializeRepository(name: name, path: path)
                self.repositories.append(repository)
                self.selectedRepository = repository
                self.isCreatingRepository = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isCreatingRepository = false
            }
        }
    }
    
    func deleteRepository(_ repository: Repository) {
        isLoading = true
        
        Task { @MainActor in
            do {
                try await resticService.deleteRepository(at: repository.path)
                if let index = self.repositories.firstIndex(where: { $0.id == repository.id }) {
                    self.repositories.remove(at: index)
                }
                if self.selectedRepository?.id == repository.id {
                    self.selectedRepository = nil
                }
                self.isLoading = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isLoading = false
            }
        }
    }
    
    func updateRepository(_ repository: Repository) {
        DispatchQueue.main.async {
            if let index = self.repositories.firstIndex(where: { $0.id == repository.id }) {
                self.repositories[index] = repository
                if self.selectedRepository?.id == repository.id {
                    self.selectedRepository = repository
                }
            }
        }
    }
    
    func createSnapshot(repository: Repository, paths: [URL], completion: @escaping (Result<Snapshot, Error>) -> Void) {
        Task { @MainActor in
            do {
                let snapshot = try await resticService.createSnapshot(repository: repository, paths: paths)
                completion(.success(snapshot))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    struct RepositoryValidationState {
        var nameError: String?
        var pathError: String?
        
        var hasErrors: Bool {
            nameError != nil || pathError != nil
        }
        
        mutating func validateName(_ name: String) {
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nameError = "Repository name cannot be empty"
            } else {
                nameError = nil
            }
        }
        
        mutating func validatePath(_ path: String) {
            if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pathError = "Repository path cannot be empty"
            } else {
                pathError = nil
            }
        }
    }
}
