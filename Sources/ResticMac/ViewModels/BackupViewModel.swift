import Foundation
import SwiftUI

final class BackupViewModel: ObservableObject {
    @Published var selectedPaths: [URL] = []
    @Published var repositories: [Repository] = []
    @Published var selectedRepository: Repository?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isLoading = false
    
    private let resticService: ResticServiceProtocol
    
    init(resticService: ResticServiceProtocol) {
        self.resticService = resticService
    }
    
    func loadRepositories() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Scan for repositories in the default directory
            let defaultDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let results = try await resticService.scanForRepositories(in: defaultDirectory)
            
            // Convert scan results to repositories
            repositories = results.compactMap { result in
                guard result.isValid else { return nil }
                return try? Repository(name: result.path.lastPathComponent, path: result.path)
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    func createBackup() async throws {
        guard let repository = selectedRepository else {
            throw BackupError.noRepositorySelected
        }
        
        guard !selectedPaths.isEmpty else {
            throw BackupError.noPathsSelected
        }
        
        try await resticService.createSnapshot(repository: repository, paths: selectedPaths)
    }
    
    func addPath(_ url: URL) {
        if !selectedPaths.contains(url) {
            selectedPaths.append(url)
        }
    }
    
    func removePath(_ url: URL) {
        selectedPaths.removeAll { $0 == url }
    }
}

enum BackupError: LocalizedError {
    case noPathsSelected
    case noRepositorySelected
    
    var errorDescription: String? {
        switch self {
        case .noPathsSelected:
            return "Please select at least one path to backup"
        case .noRepositorySelected:
            return "Please select a repository for backup"
        }
    }
}
