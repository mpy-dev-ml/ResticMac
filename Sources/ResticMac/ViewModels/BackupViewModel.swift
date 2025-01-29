import Foundation
import SwiftUI
import Combine

final class BackupViewModel: ObservableObject {
    @Published var selectedPaths: [URL] = []
    @Published var repositories: [Repository] = []
    @Published var selectedRepository: Repository?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isLoading = false
    @Published var progress: SnapshotProgress?
    
    private let resticService: ResticService
    private var cancellables = Set<AnyCancellable>()
    
    init(resticService: ResticService = .shared) {
        self.resticService = resticService
        
        // Subscribe to backup progress updates
        resticService.snapshotProgressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.progress = progress
            }
            .store(in: &cancellables)
    }
    
    func loadRepositories() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Scan for repositories in the default directory
                let defaultDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let results = try self.resticService.scanForRepositories(in: defaultDirectory)
                
                DispatchQueue.main.async {
                    // Convert scan results to repositories
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
    
    func createBackup() {
        guard let repository = selectedRepository else {
            self.errorMessage = "No repository selected"
            self.showError = true
            return
        }
        
        guard !selectedPaths.isEmpty else {
            self.errorMessage = "No paths selected"
            self.showError = true
            return
        }
        
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                _ = try self.resticService.createSnapshot(repository: repository, paths: selectedPaths)
                DispatchQueue.main.async {
                    self.isLoading = false
                    // TODO: Handle successful snapshot creation
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
    case noRepositorySelected
    case noPathsSelected
    
    var errorDescription: String? {
        switch self {
        case .noRepositorySelected:
            return "No repository selected"
        case .noPathsSelected:
            return "No paths selected for backup"
        }
    }
}
