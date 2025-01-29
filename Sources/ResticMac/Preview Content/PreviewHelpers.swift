import SwiftUI
import Foundation

// MARK: - Repository Types
struct RepositoryStats: Codable {
    let totalSize: UInt64
    let totalFiles: UInt64
    let uniqueSize: UInt64
}

struct RepositoryHealth {
    enum Status {
        case healthy
        case warning
        case error
    }
    
    let status: Status
    let issues: [String]
}

class PreviewResticService: ResticServiceProtocol {
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
    
    func snapshotProgress() -> AsyncStream<SnapshotProgress> {
        AsyncStream { continuation in
            continuation.yield(SnapshotProgress(type: .pruning, current: 0, total: 0, percentage: 0.0))
            continuation.finish()
        }
    }
    
    func restoreProgress() -> AsyncStream<RestoreProgress> {
        AsyncStream { continuation in
            continuation.yield(RestoreProgress(output: ""))
            continuation.finish()
        }
    }
    
    func forgetSnapshot(repository: Repository, snapshot: String) async throws {}
    
    func pruneRepository(repository: Repository) async throws {}
    
    func getRepositoryStats(_ repository: Repository) async throws -> RepositoryStats {
        return RepositoryStats(totalSize: 0, totalFiles: 0, uniqueSize: 0)
    }
    
    func checkRepositoryHealth(_ repository: Repository) async throws -> RepositoryHealth {
        return RepositoryHealth(status: .healthy, issues: [])
    }
}

// MARK: - Preview Data
extension Repository {
    static var preview: Repository {
        Repository(name: "Preview Repository", path: URL(fileURLWithPath: "/tmp/preview"))
    }
}
