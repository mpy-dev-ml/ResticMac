import SwiftUI

struct BackupView: View {
    @StateObject private var viewModel = BackupViewModel()
    @State private var showingCommandDisplay = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Repository Selection
                Picker("Repository", selection: $viewModel.selectedRepository) {
                    Text("Select Repository").tag(nil as Repository?)
                    ForEach(viewModel.repositories) { repository in
                        Text(repository.name).tag(Optional(repository))
                    }
                }
                .pickerStyle(.menu)
                
                // Path Selection
                PathSelector(selectedPaths: $viewModel.selectedPaths)
                    .padding(.horizontal)
                
                // Progress View
                if let progress = viewModel.progress {
                    VStack(alignment: .leading) {
                        Text("Backup Progress")
                            .font(.headline)
                        ProgressView(value: Double(progress.processedFiles), total: Double(progress.totalFiles)) {
                            HStack {
                                Text("\(progress.processedFiles) of \(progress.totalFiles) files")
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: progress.processedBytes, countStyle: .file))
                            }
                            .font(.caption)
                        }
                    }
                    .padding()
                }
                
                // Backup Button
                Button(action: {
                    showingCommandDisplay = true
                    Task {
                        do {
                            try await viewModel.startBackup()
                            dismiss()
                        } catch {
                            // Error will be shown via viewModel.showError
                        }
                    }
                }) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Start Backup")
                            .font(.headline)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedRepository == nil || viewModel.selectedPaths.isEmpty || viewModel.isLoading)
                .padding()
            }
            .navigationTitle("Create Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $showingCommandDisplay) {
            CommandDisplayView(viewModel: CommandDisplayViewModel())
        }
        .task {
            await viewModel.loadRepositories()
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
                        try await $viewModel.createBackup
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

struct PathSelector: View {
    @Binding var selectedPaths: [URL]
    
    var body: some View {
        List {
            ForEach(selectedPaths, id: \.self) { path in
                HStack {
                    Text(path.lastPathComponent)
                    Spacer()
                    Button(action: {
                        selectedPaths.removeAll { $0 == path }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            
            Button(action: {
                // Add path logic here
            }) {
                Label("Add Path", systemImage: "plus.circle")
            }
        }
    }
}
