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
            
            repositories = try await resticService.scanForRepositories(in: url)
        } catch {
            self.error = error
        }
    }
}
