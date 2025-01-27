import Foundation
import SwiftUI

@MainActor
class ScanViewModel: ObservableObject {
    private let resticService: ResticServiceProtocol
    @Published var scanResults: [RepositoryScanResult] = []
    @Published var isScanning = false
    @Published var error: Error?
    
    init(resticService: ResticServiceProtocol) {
        self.resticService = resticService
    }
    
    func scanDirectory(_ url: URL) async {
        isScanning = true
        defer { isScanning = false }
        
        do {
            scanResults = try await resticService.scanForRepositories(in: url)
        } catch {
            self.error = error
        }
    }
}
