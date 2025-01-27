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
        return path.isFileURL && FileManager.default.isWritableFile(atPath: path.path)
    }
    
    func validatePassword(_ password: String) -> Bool {
        return !password.isEmpty && password.count >= 8
    }
    
    func scanForRepositories(in directory: URL) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let results = try await resticService.scanForRepositories(in: directory)
        repositories = results.compactMap { result in
            guard result.isValid else { return nil }
            return try? Repository(name: result.path.lastPathComponent, path: result.path)
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
        isCreatingRepository = true
        defer { isCreatingRepository = false }
        
        let repository = try await resticService.initializeRepository(
            name: name,
            path: path,
            password: password
        )
        
        repositories.append(repository)
    }
    
    func removeRepository(_ repository: Repository) async {
        repositories.removeAll { $0.path == repository.path }
    }
    
    func deleteRepository(_ repository: Repository) async {
        // For now, we just remove it from our list
        // In the future, we might want to actually delete the repository files
        repositories.removeAll { $0.path == repository.path }
    }
}
