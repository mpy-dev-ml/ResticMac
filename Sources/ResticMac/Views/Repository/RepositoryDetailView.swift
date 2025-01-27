import SwiftUI

struct RepositoryDetailView: View {
    let repository: Repository
    @ObservedObject var viewModel: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingBackupSheet = false
    @State private var showingDeleteAlert = false
    @State private var isCheckingStatus = false
    @State private var snapshots: [Snapshot] = []
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var currentRepository: Repository {
        viewModel.selectedRepository ?? repository
    }
    
    var body: some View {
        List {
            Section {
                InfoRow(title: "Name", value: currentRepository.name)
                InfoRow(title: "Location", value: currentRepository.path.path)
                if let lastChecked = currentRepository.lastChecked {
                    InfoRow(title: "Last Checked", value: lastChecked.formatted())
                }
                if let lastBackup = currentRepository.lastBackup {
                    InfoRow(title: "Last Backup", value: lastBackup.formatted())
                }
            } header: {
                Text("Repository Information")
            }
            
            Section {
                Button {
                    showingBackupSheet = true
                } label: {
                    Label("Create Backup", systemImage: "arrow.up.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isCheckingStatus)
                
                Button {
                    Task { await checkStatus() }
                } label: {
                    HStack {
                        Label("Check Status", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isCheckingStatus {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isCheckingStatus)
                
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete Repository", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isCheckingStatus)
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
        .navigationTitle(currentRepository.name)
        .task {
            await loadSnapshots()
        }
        .onChange(of: currentRepository) { _, _ in
            Task {
                await loadSnapshots()
            }
        }
        .sheet(isPresented: $showingBackupSheet) {
            BackupView(repository: currentRepository, viewModel: viewModel)
        }
        .alert("Delete Repository", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteRepository(currentRepository)
                    dismiss()
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
    
    private func checkStatus() async {
        isCheckingStatus = true
        defer { isCheckingStatus = false }
        
        do {
            try await viewModel.refreshRepository(currentRepository)
        } catch {
            errorMessage = "Failed to check repository status: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func loadSnapshots() async {
        do {
            snapshots = try await viewModel.listSnapshots(repository: currentRepository)
        } catch {
            errorMessage = "Failed to load snapshots: \(error.localizedDescription)"
            showError = true
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
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