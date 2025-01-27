import Foundation
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published private(set) var repositories: [Repository] = []
    @Published private(set) var isLoading = false
    @Published var isCreatingRepository = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var validationState = RepositoryValidationState()
    @Published var selectedRepositoryId: UUID?
    
    var selectedRepository: Repository? {
        guard let id = selectedRepositoryId else { return nil }
        return repositories.first { $0.id == id }
    }
    
    func selectRepository(_ repository: Repository?) {
        selectedRepositoryId = repository?.id
    }
    
    func updateRepository(_ repository: Repository) {
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[index] = repository
            objectWillChange.send()
        }
    }
    
    func refreshRepository(_ repository: Repository) async throws {
        // Check repository status
        let status = try await checkRepository(repository)
        if status.isValid {
            // Load latest snapshots
            let snapshots = try await listSnapshots(repository: repository)
            
            // Update repository with latest info
            var updatedRepo = repository
            updatedRepo.lastChecked = Date()
            if let lastSnapshot = snapshots.last {
                updatedRepo.lastBackup = lastSnapshot.time
            }
            updateRepository(updatedRepo)
        }
    }
    
    struct RepositoryValidationState {
        var isNameValid = true
        var isPathValid = true
        var isPasswordValid = true
        var nameError = ""
        var pathError = ""
        var passwordError = ""
    }
    
    private let resticService: ResticServiceProtocol
    private let commandDisplay: CommandDisplayViewModel
    
    init(resticService: ResticServiceProtocol, commandDisplay: CommandDisplayViewModel) {
        self.resticService = resticService
        self.commandDisplay = commandDisplay
        Task { 
            await resticService.setCommandDisplay(commandDisplay)
            await scanForRepositories()
        }
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
    
    @MainActor
    func scanForRepositories() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let results = try await resticService.scanForRepositories(in: documentsURL)
            
            // Update on main actor to ensure UI updates
            self.repositories = results.compactMap { result -> Repository? in
                guard result.isValid else { return nil }
                var repo = Repository(name: result.path.lastPathComponent, path: result.path)
                repo.lastChecked = Date()
                return repo
            }
            
            // Sort repositories by name
            self.repositories.sort { $0.name < $1.name }
            
        } catch {
            self.errorMessage = "Failed to scan for repositories: \(error.localizedDescription)"
            self.showError = true
        }
    }
    
    func refreshRepositories() async {
        await scanForRepositories()
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
    
    func createRepository(name: String, path: URL, password: String) async {
        guard !isCreatingRepository else { return }
        
        isCreatingRepository = true
        validationState = RepositoryValidationState()
        
        do {
            // Validate inputs before proceeding
            var hasError = false
            
            // Validate name
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationState.isNameValid = false
                validationState.nameError = "Please enter a repository name"
                hasError = true
            }
            
            // Validate path
            if !validatePath(path) {
                validationState.isPathValid = false
                validationState.pathError = "Please select a valid directory"
                hasError = true
            }
            
            // Validate password
            if !validatePassword(password) {
                validationState.isPasswordValid = false
                validationState.passwordError = "Password must meet security requirements"
                hasError = true
            }
            
            if hasError {
                isCreatingRepository = false
                return
            }
            
            // Create repository
            let repository = try await resticService.initializeRepository(
                name: name,
                path: path,
                password: password
            )
            
            // Add to repositories list
            repositories.append(repository)
            
            // Reset state
            isCreatingRepository = false
            showError = false
            errorMessage = ""
            
        } catch let error as ResticError {
            handleResticError(error)
        } catch {
            showError = true
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
        }
        
        isCreatingRepository = false
    }
    
    private func handleResticError(_ error: ResticError) {
        showError = true
        switch error {
        case .notInstalled:
            errorMessage = "Restic is not installed. Please install Restic and try again."
        case .validationFailed(let errors):
            errorMessage = errors.joined(separator: "\n")
        case .initializationFailed(let underlying):
            errorMessage = "Failed to initialise repository: \(underlying.localizedDescription)"
        default:
            errorMessage = "An error occurred: \(error.localizedDescription)"
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
    
    func deleteRepository(_ repository: Repository) async {
        // Remove from list first for immediate UI feedback
        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories.remove(at: index)
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
}
