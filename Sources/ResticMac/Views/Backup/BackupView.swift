import SwiftUI

struct BackupView: View {
    @StateObject private var viewModel = BackupViewModel(resticService: ResticService())
    @State private var showingCommandDisplay = false
    @State private var showingPathPicker = false
    
    var body: some View {
        VStack {
            BackupContentView(
                viewModel: viewModel,
                showingCommandDisplay: $showingCommandDisplay,
                showingPathPicker: $showingPathPicker
            )
            .task {
                await viewModel.loadRepositories()
            }
        }
    }
}

struct BackupContentView: View {
    @ObservedObject var viewModel: BackupViewModel
    @Binding var showingCommandDisplay: Bool
    @Binding var showingPathPicker: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Repository Selection
            Picker("Repository", selection: $viewModel.selectedRepository) {
                Text("Select Repository").tag(nil as Repository?)
                ForEach(viewModel.repositories) { repository in
                    Text(repository.name).tag(Optional(repository))
                }
            }
            .pickerStyle(.menu)
            
            // Selected Paths List
            List {
                ForEach(viewModel.selectedPaths, id: \.self) { path in
                    HStack {
                        Text(path.lastPathComponent)
                        Spacer()
                        Button(action: { viewModel.removePath(path) }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .frame(height: 200)
            
            // Add Path Button
            Button(action: { showingPathPicker = true }) {
                Label("Add Path", systemImage: "plus")
            }
            
            // Backup Button
            Button(action: {
                showingCommandDisplay = true
                Task {
                    do {
                        try await viewModel.createBackup()
                    } catch {
                        // Error will be shown in CommandDisplayView
                    }
                }
            }) {
                Text("Start Backup")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .disabled(viewModel.selectedRepository == nil || viewModel.selectedPaths.isEmpty)
        }
        .padding()
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $showingPathPicker) {
            PathPicker { url in
                viewModel.addPath(url)
            }
        }
        .sheet(isPresented: $showingCommandDisplay) {
            CommandDisplayView(viewModel: CommandDisplayViewModel())
        }
    }
}

struct PathPicker: View {
    let onSelect: (URL) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Text("Path Picker Placeholder")
                .navigationTitle("Select Path")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}