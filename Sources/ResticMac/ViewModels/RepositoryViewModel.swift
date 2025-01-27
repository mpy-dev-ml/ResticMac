import Foundation
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published private(set) var repositories: [Repository] = []
    @Published private(set) var isLoading = false
    @Published var isCreatingRepository = false
    @Published var selectedRepository: Repository?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var validationState = RepositoryValidationState()
    
    private let resticService: ResticServiceProtocol
    private let commandDisplay: CommandDisplayViewModel
    private var refreshTask: Task<Void, Never>?
    
    var hasSelectedRepository: Bool {
        selectedRepository != nil
    }
    
    // Dictionary for O(1) lookups
    private var repositoryMap: [UUID: Repository] {
        Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
    }
    
    init(resticService: ResticServiceProtocol, commandDisplay: CommandDisplayViewModel) {
        self.resticService = resticService
        self.commandDisplay = commandDisplay
        Task { 
            await resticService.setCommandDisplay(commandDisplay)
            await scanForRepositories()
        }
    }
    
    func repository(withId id: UUID) -> Repository? {
        repositoryMap[id]
    }
    
    func selectRepository(_ repository: Repository?) {
        if let repository = repository {
            // Ensure we're using the latest version from our repositories array
            selectedRepository = repositoryMap[repository.id] ?? repository
        } else {
            selectedRepository = nil
        }
        objectWillChange.send()
    }
    
    @MainActor
    func refreshRepositories() async {
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        // Create new refresh task
        refreshTask = Task {
            do {
                isLoading = true
                defer { isLoading = false }
                
                // Store currently selected repository ID
                let selectedId = selectedRepository?.id
                
                // Scan for repositories
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let results = try await resticService.scanForRepositories(in: documentsURL)
                
                // Only update if task hasn't been cancelled
                if !Task.isCancelled {
                    let newRepositories = results.compactMap { result -> Repository? in
                        guard result.isValid else { return nil }
                        var repo = Repository(name: result.path.lastPathComponent, path: result.path)
                        repo.lastChecked = Date()
                        return repo
                    }.sorted { $0.name < $1.name }
                    
                    withAnimation {
                        repositories = newRepositories
                        
                        // Restore selection if repository still exists
                        if let id = selectedId,
                           let repository = repositoryMap[id] {
                            selectedRepository = repository
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Failed to refresh repositories: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
        
        // Wait for task completion
        await refreshTask?.value
    }
    
    @MainActor
    func refreshSelectedRepository() async throws {
        guard let repository = selectedRepository else { return }
        
        let status = try await checkRepository(repository)
        if status.isValid {
            let snapshots = try await listSnapshots(repository: repository)
            var updatedRepo = repository
            updatedRepo.lastChecked = Date()
            if let lastSnapshot = snapshots.last {
                updatedRepo.lastBackup = lastSnapshot.time
            }
            
            withAnimation {
                updateRepository(updatedRepo)
                selectedRepository = updatedRepo
            }
        }
    }
    
    func updateRepository(_ repository: Repository) {
        withAnimation {
            if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
                repositories[index] = repository
                if selectedRepository?.id == repository.id {
                    selectedRepository = repository
                }
                objectWillChange.send()
            }
        }
    }
    
    func deleteRepository(_ repository: Repository) async {
        // Remove from list first for immediate UI feedback
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories.remove(at: index)
            if selectedRepository?.id == repository.id {
                selectedRepository = nil
            }
        }
        
        do {
            // Then attempt to delete the actual repository
            try FileManager.default.removeItem(at: repository.path)
        } catch {
            self.errorMessage = "Failed to delete repository: \(error.localizedDescription)"
            self.showError = true
        }
        
        // Always refresh the list to ensure consistency
        await scanForRepositories()
    }
    
    func scanForRepositories() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let results = try await resticService.scanForRepositories(in: documentsURL)
            
            withAnimation {
                let newRepositories = results.compactMap { result -> Repository? in
                    guard result.isValid else { return nil }
                    var repo = Repository(name: result.path.lastPathComponent, path: result.path)
                    repo.lastChecked = Date()
                    return repo
                }.sorted { $0.name < $1.name }
                
                // Update selected repository if it exists in new list
                if let selected = selectedRepository,
                   let updated = newRepositories.first(where: { $0.id == selected.id }) {
                    selectedRepository = updated
                }
                
                repositories = newRepositories
            }
        } catch {
            errorMessage = "Failed to scan for repositories: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func checkRepository(_ repository: Repository) async throws -> RepositoryStatus {
        let status = try await resticService.checkRepository(repository: repository)
        if status.isValid {
            // Update repository status
            if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
                var updatedRepo = repositories[index]
                updatedRepo.lastChecked = Date()
                repositories[index] = updatedRepo
            }
        }
        return status
    }
    
    func createRepository(name: String, path: URL) async throws -> Repository {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let repository = try await resticService.initializeRepository(
                name: name,
                path: path
            )
            
            withAnimation {
                repositories.append(repository)
                repositories.sort { $0.name < $1.name }
            }
            
            return repository
        } catch {
            errorMessage = "Failed to create repository: \(error.localizedDescription)"
            showError = true
            throw error
        }
    }
    
    func removeRepository(_ repository: Repository) async {
        do {
            try repository.removePassword()
            repositories.removeAll { $0.id == repository.id }
        } catch {
            errorMessage = "Failed to remove repository: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func listSnapshots(repository: Repository) async throws -> [Snapshot] {
        do {
            return try await resticService.listSnapshots(repository: repository)
        } catch {
            self.errorMessage = "Failed to list snapshots: \(error.localizedDescription)"
            self.showError = true
            throw error
        }
    }
    
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot {
        return try await resticService.createSnapshot(repository: repository, paths: paths)
    }
    
    struct RepositoryValidationState {
        var isNameValid = true
        var isPathValid = true
        var isPasswordValid = true
        var nameError = ""
        var pathError = ""
        var passwordError = ""
    }
    
    func validatePath(_ path: URL) -> Bool {
        // Check if path exists and is writable
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        if !fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) {
            do {
                try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
                return true
            } catch {
                return false
            }
        }
        
        return isDirectory.boolValue && fileManager.isWritableFile(atPath: path.path)
    }
    
    func validatePassword(_ password: String) -> Bool {
        // Enhanced password validation matching the UI requirements
        let hasMinLength = password.count >= 8
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumber = password.contains(where: { $0.isNumber })
        let hasSpecial = password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) })
        
        // Require minimum length plus at least 3 other criteria
        let criteriaCount = [hasUppercase, hasLowercase, hasNumber, hasSpecial]
            .filter { $0 }
            .count
            
        return hasMinLength && criteriaCount >= 3
    }
}
