import SwiftUI
import Foundation

struct PreviewResticService: ResticServiceProtocol {
    func setCommandDisplay(_ display: CommandDisplayViewModel) async {}
    func verifyInstallation() async throws {}
    func initializeRepository(name: String, path: URL, password: String) async throws -> Repository {
        Repository(name: name, path: path)
    }
    func scanForRepositories(in directory: URL) async throws -> [RepositoryScanResult] { [] }
    func checkRepository(repository: Repository) async throws -> RepositoryStatus { .ok }
    func createSnapshot(repository: Repository, paths: [URL]) async throws -> Snapshot {
        Snapshot(id: "test", 
                time: .now, 
                paths: [], 
                hostname: "", 
                username: "", 
                excludes: [], 
                tags: [])
    }
    func listSnapshots(repository: Repository) async throws -> [Snapshot] { [] }
    func restoreSnapshot(repository: Repository, snapshot: String, targetPath: URL) async throws {}
    func listSnapshotContents(repository: Repository, snapshot: String, path: String?) async throws -> [SnapshotEntry] { [] }
}
