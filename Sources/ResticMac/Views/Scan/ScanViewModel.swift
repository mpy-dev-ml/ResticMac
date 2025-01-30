import Foundation
import SwiftUI

@MainActor
class ScanViewModel: ObservableObject {
    private let resticService: any ResticServiceProtocol
    @Published var repositories: [RepositoryScanResult] = []
    @Published var isScanning = false
    @Published var error: Error?
    
    init(resticService: any ResticServiceProtocol) {
        self.resticService = resticService
    }
    
    func handleSelectedDirectory(_ result: Result<[URL], Error>) async {
        do {
            guard let url = try result.get().first else { return }
            
            isScanning = true
            defer { isScanning = false }
            
            let service = self.resticService
            repositories = try await withCheckedThrowingContinuation { continuation in
                Task {
                    do {
                        let repos = try await service.scanForRepositories(in: url)
                        continuation.resume(returning: repos)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            self.error = error
        }
    }
}
