import Foundation
import Combine

class ScanViewModel: ObservableObject {
    private let resticService: ResticServiceProtocol
    @Published var scanResults: [RepositoryScanResult] = []
    @Published var isScanning = false
    @Published var error: Error?
    
    init(resticService: ResticServiceProtocol) {
        self.resticService = resticService
    }
    
    @MainActor
    func scanDirectory(_ url: URL) async {
        isScanning = true
        error = nil
        
        do {
            scanResults = try await resticService.scanForRepositories(in: url)
        } catch {
            self.error = error
        }
        
        isScanning = false
    }
    
    var orphanedSnapshots: [(Repository, [SnapshotInfo])] {
        scanResults.compactMap { result in
            guard result.isValid,
                  let repository = try? Repository(name: result.path.lastPathComponent, path: result.path),
                  !result.snapshots.filter(\.isOrphaned).isEmpty else {
                return nil
            }
            return (repository, result.snapshots.filter(\.isOrphaned))
        }
    }
}
