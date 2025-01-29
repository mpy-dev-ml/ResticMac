import Foundation
import SwiftUI
import Combine

@MainActor
final class SnapshotViewModel: ObservableObject {
    @Published private(set) var snapshots: [Snapshot] = []
    @Published private(set) var isLoading: Bool = false
    @Published var selectedSnapshot: Snapshot?
    @Published private(set) var currentProgress: RestoreProgress?
    
    private let resticService: any ResticServiceProtocol
    private var progressCancellable: Task<Void, Never>?
    
    init(resticService: any ResticServiceProtocol) {
        self.resticService = resticService
        setupProgressTracking()
    }
    
    private func setupProgressTracking() {
        progressCancellable = Task { [weak self] in
            guard let self = self else { return }
            for await progress in self.resticService.restoreProgress() {
                self.currentProgress = progress
            }
        }
    }
    
    deinit {
        progressCancellable?.cancel()
    }
    
    func loadSnapshots(for repository: Repository) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            snapshots = try await resticService.listSnapshots(repository: repository)
        } catch {
            // Handle error appropriately
            snapshots = []
        }
    }
    
    func restoreSnapshot(_ snapshot: Snapshot, to targetPath: URL, in repository: Repository) async throws {
        try await resticService.restoreSnapshot(
            repository: repository,
            snapshot: snapshot.id,
            targetPath: targetPath
        )
    }
    
    func refreshSnapshots(for repository: Repository) {
        Task {
            await loadSnapshots(for: repository)
        }
    }
}
