import SwiftUI
import Foundation

struct PreviewResticService: ResticServiceProtocol {
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {}
    func verifyInstallation() async throws {}
    
    func initializeRepository(name: String, path: URL) async throws -> Repository {
        return Repository(
            name: name,
            path: path
        )
    }
    
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult] {
        return []
    }
    
    func checkRepository(repository: Repository) async throws -> RepositoryStatus {
        return RepositoryStatus(state: .ok, errors: [])
    }
    
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot {
        return Snapshot(
            id: "snapshot1",
            time: Date(),
            paths: paths.map { $0.path },
            hostname: "preview",
            username: "preview",
            excludes: [],
            tags: []
        )
    }
    
    func listSnapshots(repository: Repository) async throws -> [Snapshot] {
        return []
    }
    
    func restoreSnapshot(repository: Repository, snapshot: String, targetPath: URL) async throws {}
    
    func listSnapshotContents(repository: Repository, snapshot: String, path: String?) async throws -> [SnapshotEntry] {
        return []
    }
    
    func deleteRepository(at path: URL) async throws {
        // Preview implementation - no actual deletion
    }
}
