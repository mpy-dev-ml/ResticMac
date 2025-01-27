import Foundation
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published var repositories: [Repository] = []
    @Published var isLoading = false
    @Published var isCreatingRepository = false
    @Published var showError = false
    @Published var errorMessage = ""
    
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
    
    func scanForRepositories(in directory: URL) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let results = try await resticService.scanForRepositories(in: directory)
            repositories = results.compactMap { result in
                guard result.isValid else { return nil }
                return Repository(name: result.path.lastPathComponent, path: result.path)
            }
        } catch {
            errorMessage = "Failed to scan for repositories: \(error.localizedDescription)"
            showError = true
        }
    }
    
    func checkRepository(_ repository: Repository) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let status = try await resticService.checkRepository(repository: repository)
        if !status.isValid {
            throw ResticError.repositoryInvalid(status.errors)
        }
    }
    
    func createRepository(name: String, path: URL, password: String) async throws {
        print("Starting repository creation process")
        print("Name: \(name)")
        print("Path: \(path)")
        print("Password length: \(password.count)")
        
        isCreatingRepository = true
        defer { isCreatingRepository = false }
        
        do {
            print("Initializing repository...")
            let repository = try await resticService.initializeRepository(
                name: name,
                path: path,
                password: password
            )
            print("Repository initialized")
            repositories.append(repository)
            
            print("Verifying repository...")
            try await checkRepository(repository)
            print("Repository verified successfully")
            
        } catch let error as ResticError {
            print("Repository creation failed with ResticError: \(error)")
            switch error {
            case .repositoryInvalid(let errors):
                throw NSError(
                    domain: "ResticMac",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: errors.joined(separator: "\n")
                    ]
                )
            default:
                throw error
            }
        } catch {
            print("Repository creation failed with error: \(error)")
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
    
    func deleteRepository(_ repository: Repository) async {
        // For now, we just remove it from our list
        // In the future, we might want to actually delete the repository files
        repositories.removeAll { $0.path == repository.path }
    }
}
