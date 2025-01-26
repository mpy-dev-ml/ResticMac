import SwiftUI

struct BackupView: View {
    @State private var viewModel: BackupViewModel?
    @State private var showingCommandDisplay = false
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                BackupContentView(viewModel: viewModel, showingCommandDisplay: $showingCommandDisplay)
            } else {
                ProgressView("Loading...")
                    .onAppear {
                        Task {
                            viewModel = await BackupViewModel.create()
                        }
                    }
            }
        }
    }
}

private struct BackupContentView: View {
    @ObservedObject var viewModel: BackupViewModel
    @Binding var showingCommandDisplay: Bool
    @StateObject private var commandDisplay = CommandDisplayViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            repositorySelector
            
            Divider()
            
            PathSelector(selectedPaths: $viewModel.selectedPaths)
            
            Divider()
            
            HStack {
                if viewModel.isBackingUp {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.trailing, 4)
                    Text("Creating backup...")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Create Backup") {
                    showingCommandDisplay = true
                    Task {
                        await viewModel.createBackup()
                    }
                }
                .disabled(viewModel.selectedRepository == nil ||
                         viewModel.selectedPaths.isEmpty ||
                         viewModel.isBackingUp)
            }
        }
        .padding()
        .sheet(isPresented: $showingCommandDisplay) {
            CommandDisplayView()
                .environmentObject(commandDisplay)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
    }
    
    private var repositorySelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository")
                .font(.headline)
            
            if viewModel.repositories.isEmpty {
                Text("No repositories available")
                    .foregroundColor(.secondary)
            } else {
                Picker("Repository", selection: $viewModel.selectedRepository) {
                    Text("Select Repository")
                        .tag(nil as Repository?)
                    
                    ForEach(viewModel.repositories) { repository in
                        Text(repository.name)
                            .tag(repository as Repository?)
                    }
                }
            }
        }
    }
}