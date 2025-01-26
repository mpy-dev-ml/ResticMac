import SwiftUI
import Logging

@MainActor
class BackupViewModel: ObservableObject {
    private let logger = Logger(label: "com.resticmac.BackupViewModel")
    private let resticService: ResticService
    private let commandDisplay: CommandDisplayViewModel
    private let storage: RepositoryStorage
    
    @Published var selectedPaths: [URL] = []
    @Published var selectedRepository: Repository?
    @Published var repositories: [Repository] = []
    @Published var isBackingUp = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    init(resticService: ResticService,
         commandDisplay: CommandDisplayViewModel,
         storage: RepositoryStorage) {
        self.resticService = resticService
        self.commandDisplay = commandDisplay
        self.storage = storage
        
        // Load repositories
        Task {
            await loadRepositories()
        }
    }
    
    static func create() async -> BackupViewModel {
        let resticService = ResticService()
        let commandDisplay = CommandDisplayViewModel()
        let storage = await RepositoryStorage.shared
        
        return BackupViewModel(
            resticService: resticService,
            commandDisplay: commandDisplay,
            storage: storage
        )
    }
    
    func createBackup() async {
        guard let repository = selectedRepository,
              !selectedPaths.isEmpty else {
            errorMessage = "Please select a repository and at least one path"
            showError = true
            return
        }
        
        isBackingUp = true
        
        do {
            await resticService.setCommandDisplay(commandDisplay)
            let command = ResticCommand.backup(repository: repository.path,
                                             paths: selectedPaths,
                                             password: try repository.retrievePassword())
            
            commandDisplay.displayCommand(command)
            _ = try await resticService.executeCommand(command)
            isBackingUp = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isBackingUp = false
            logger.error("Backup failed: \(error.localizedDescription)")
        }
    }
    
    private func loadRepositories() async {
        do {
            repositories = try await Task.detached { @RepositoryStorageActor in
                try self.storage.loadRepositories()
            }.value
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            logger.error("Failed to load repositories: \(error.localizedDescription)")
        }
    }
}