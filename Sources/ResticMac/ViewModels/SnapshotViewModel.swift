import Foundation
import SwiftUI

@MainActor
final class SnapshotViewModel: ObservableObject {
    @Published private(set) var snapshots: [Snapshot] = []
    @Published private(set) var isLoading: Bool = false
    @Published var selectedSnapshot: Snapshot?
    
    private let resticService: ResticServiceProtocol
    
    init(resticService: ResticServiceProtocol) {
        self.resticService = resticService
    }
    
    func loadSnapshots(for repository: Repository) async throws {
        isLoading = true
        defer { isLoading = false }
        
        snapshots = try await resticService.listSnapshots(repository: repository)
    }
    
    func restoreSnapshot(_ snapshot: Snapshot, to target: URL, repository: Repository) async throws {
        isLoading = true
        defer { isLoading = false }
        
        try await resticService.restoreSnapshot(
            repository: repository,
            snapshot: snapshot.id,
            targetPath: target
        )
    }
}
