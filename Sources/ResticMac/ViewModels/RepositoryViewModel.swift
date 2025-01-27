import Foundation
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var isLoading = false
    @Published var isCreatingRepository = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var validationState = RepositoryValidationState()
    @Published var selectedRepository: Repository?
    
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
        Task { await resticService.setCommandDisplay(commandDisplay) }
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
            // Use the user's Documents folder as the default scan location
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let results = try await resticService.scanForRepositories(in: documentsURL)
            await MainActor.run {
                self.repositories = results.compactMap { result -> Repository? in
                    guard result.isValid else { return nil }
                    var repo = Repository(name: result.path.lastPathComponent, path: result.path)
                    repo.lastChecked = Date()
                    return repo
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to scan for repositories: \(error.localizedDescription)"
                self.showError = true
            }
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
        // For now, we just remove it from our list
        // In the future, we might want to actually delete the repository files
        repositories.removeAll { $0.path == repository.path }
    }
    
    func listSnapshots(for repository: Repository) async throws -> [Snapshot] {
        return try await resticService.listSnapshots(repository: repository)
    }
    
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot {
        return try await resticService.createSnapshot(repository: repository, paths: paths)
    }
}
