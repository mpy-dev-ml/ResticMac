import SwiftUI

struct RepositoryDetailView: View {
    let repository: Repository
    @ObservedObject var viewModel: RepositoryViewModel
    @State private var showingBackupSheet = false
    @State private var showingDeleteAlert = false
    @State private var isCheckingStatus = false
    @State private var snapshots: [Snapshot] = []
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        List {
            Section {
                InfoRow(title: "Name", value: repository.name)
                InfoRow(title: "Location", value: repository.path.path)
                if let lastChecked = repository.lastChecked {
                    InfoRow(title: "Last Checked", value: lastChecked.formatted())
                }
                if let lastBackup = repository.lastBackup {
                    InfoRow(title: "Last Backup", value: lastBackup.formatted())
                }
            } header: {
                Text("Repository Information")
            }
            
            Section {
                Button(action: { showingBackupSheet = true }) {
                    Label("Create Backup", systemImage: "arrow.up.doc")
                }
                
                Button(action: checkStatus) {
                    if isCheckingStatus {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label("Check Status", systemImage: "checkmark.circle")
                    }
                }
                .disabled(isCheckingStatus)
                
                Button(role: .destructive, action: { showingDeleteAlert = true }) {
                    Label("Delete Repository", systemImage: "trash")
                }
            } header: {
                Text("Actions")
            }
            
            Section {
                if snapshots.isEmpty {
                    Text("No snapshots available")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(snapshots) { snapshot in
                        SnapshotRow(snapshot: snapshot)
                    }
                }
            } header: {
                Text("Snapshots")
            }
        }
        .navigationTitle(repository.name)
        .task {
            await loadSnapshots()
        }
        .sheet(isPresented: $showingBackupSheet) {
            BackupView(repository: repository, viewModel: viewModel)
        }
        .alert("Delete Repository", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteRepository(repository)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this repository? This action cannot be undone.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func checkStatus() {
        Task {
            isCheckingStatus = true
            defer { isCheckingStatus = false }
            do {
                let status = try await viewModel.checkRepository(repository)
                if !status.isValid {
                    errorMessage = "Repository check failed"
                    showError = true
                }
            } catch {
                errorMessage = "Failed to check repository status: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func loadSnapshots() async {
        do {
            snapshots = try await viewModel.listSnapshots(for: repository)
        } catch {
            errorMessage = "Failed to load snapshots: \(error.localizedDescription)"
            showError = true
        }
    }
}

// Helper Views
struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

struct SnapshotRow: View {
    let snapshot: Snapshot
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(snapshot.time.formatted())
                .font(.headline)
            Text(snapshot.paths.joined(separator: ", "))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}