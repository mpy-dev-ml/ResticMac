import Foundation
import SwiftUI

@MainActor
class MountViewModel: ObservableObject {
    private let mountService: MountService
    private let resticService: ResticService
    
    @Published private(set) var activeMounts: [MountService.MountPoint] = []
    @Published private(set) var repositories: [Repository] = []
    @Published private(set) var snapshots: [Snapshot] = []
    @Published private(set) var error: Error?
    @Published private(set) var isLoading = false
    
    init(mountService: MountService, resticService: ResticService) {
        self.mountService = mountService
        self.resticService = resticService
        
        // Start monitoring mounts
        Task {
            await monitorMounts()
        }
    }
    
    func mount(repository: Repository, at path: URL, snapshot: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let mount = try await mountService.mountRepository(repository, at: path, snapshot: snapshot)
            activeMounts = await mountService.getActiveMounts()
            
            // Notify success
            NotificationCenter.default.post(
                name: NSNotification.Name("RepositoryMounted"),
                object: nil,
                userInfo: ["mountPoint": mount]
            )
        } catch {
            self.error = error
        }
    }
    
    func unmount(_ mount: MountService.MountPoint) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await mountService.unmountRepository(at: mount.path)
            activeMounts = await mountService.getActiveMounts()
            
            // Notify success
            NotificationCenter.default.post(
                name: NSNotification.Name("RepositoryUnmounted"),
                object: nil,
                userInfo: ["mountPoint": mount]
            )
        } catch {
            self.error = error
        }
    }
    
    func loadRepositories() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            repositories = try await resticService.listRepositories()
        } catch {
            self.error = error
        }
    }
    
    func loadSnapshots(for repository: Repository) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            snapshots = try await resticService.listSnapshots(repository: repository)
        } catch {
            self.error = error
        }
    }
    
    private func monitorMounts() async {
        // Update active mounts periodically
        while true {
            activeMounts = await mountService.getActiveMounts()
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let repositoryMounted = Notification.Name("RepositoryMounted")
    static let repositoryUnmounted = Notification.Name("RepositoryUnmounted")
}
