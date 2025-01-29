import Foundation
import SwiftUI
import Combine

@MainActor
final class BackupViewModel: ObservableObject {
    @Published var selectedPaths: [URL] = []
    @Published var repositories: [Repository] = []
    @Published var selectedRepository: Repository?
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isLoading = false
    @Published var progress: SnapshotProgress?
    
    private var resticService: ResticService
    private var cancellables = Set<AnyCancellable>()
    private var progressTask: Task<Void, Never>?
    
    init() {
        self.resticService = ResticService.shared
        startMonitoringProgress()
    }
    
    private func startMonitoringProgress() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            guard let self = self else { return }
            for await progress in self.resticService.snapshotProgress() {
                self.progress = progress
            }
        }
    }
    
    @MainActor
    func loadRepositories() async {
        isLoading = true
        
        do {
            // Scan for repositories in the default directory
            let defaultDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let results = try await resticService.scanForRepositories(in: defaultDirectory)
            
            // Convert scan results to repositories
            self.repositories = results.compactMap { result in
                guard result.isValid else { return nil }
                return Repository(name: result.path.lastPathComponent, path: result.path)
            }
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.showError = true
            self.isLoading = false
        }
    }
    
    @MainActor
    func startBackup() async throws {
        guard let repository = selectedRepository, !selectedPaths.isEmpty else {
            throw BackupError.noRepositorySelected
        }
        
        isLoading = true
        
        do {
            _ = try await resticService.createSnapshot(repository: repository, paths: selectedPaths)
            isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.showError = true
            throw error
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
    
    deinit {
        progressTask?.cancel()
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
