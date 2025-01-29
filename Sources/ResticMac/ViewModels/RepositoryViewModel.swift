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
    
    init(resticService: ResticService = .shared, commandDisplay: CommandDisplayViewModel) {
        self.resticService = resticService
        self.commandDisplay = commandDisplay
        
        DispatchQueue.main.async {
            self.resticService.setCommandDisplay(commandDisplay)
            self.scanForRepositories()
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
    
    func scanForRepositories() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let defaultDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let results = try self.resticService.scanForRepositories(in: defaultDirectory)
                
                DispatchQueue.main.async {
                    self.repositories = results.compactMap { result in
                        guard result.isValid else { return nil }
                        return Repository(name: result.path.lastPathComponent, path: result.path)
                    }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                }
            }
        }
    }
    
    func createRepository(name: String, at path: URL) {
        isCreatingRepository = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let repository = try self.resticService.initializeRepository(name: name, path: path)
                DispatchQueue.main.async {
                    self.repositories.append(repository)
                    self.selectedRepository = repository
                    self.isCreatingRepository = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isCreatingRepository = false
                }
            }
        }
    }
    
    func deleteRepository(_ repository: Repository) {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.resticService.deleteRepository(at: repository.path)
                DispatchQueue.main.async {
                    if let index = self.repositories.firstIndex(where: { $0.id == repository.id }) {
                        self.repositories.remove(at: index)
                    }
                    if self.selectedRepository?.id == repository.id {
                        self.selectedRepository = nil
                    }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                }
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let snapshot = try self.resticService.createSnapshot(repository: repository, paths: paths)
                DispatchQueue.main.async {
                    completion(.success(snapshot))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
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
