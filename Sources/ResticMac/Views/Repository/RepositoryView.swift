import SwiftUI

struct RepositoryView: View {
    @State private var viewModel: RepositoryViewModel?
    @State private var showingCreateSheet = false
    @State private var repositoryToDelete: Repository?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                RepositoryContentView(
                    viewModel: viewModel,
                    showingCreateSheet: $showingCreateSheet,
                    repositoryToDelete: $repositoryToDelete
                )
            } else {
                ProgressView("Loading...")
                    .onAppear {
                        Task {
                            viewModel = await RepositoryViewModel.create()
                        }
                    }
            }
        }
    }
}

private struct RepositoryContentView: View {
    @ObservedObject var viewModel: RepositoryViewModel
    @Binding var showingCreateSheet: Bool
    @Binding var repositoryToDelete: Repository?
    
    var body: some View {
        VStack {
            if viewModel.repositories.isEmpty {
                emptyStateView
            } else {
                repositoryListView
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            RepositoryForm(viewModel: viewModel)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .alert("Delete Repository", isPresented: .init(
            get: { repositoryToDelete != nil },
            set: { if !$0 { repositoryToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let repository = repositoryToDelete {
                    Task {
                        await viewModel.removeRepository(repository)
                    }
                }
                repositoryToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                repositoryToDelete = nil
            }
        } message: {
            if let repository = repositoryToDelete {
                Text("Are you sure you want to delete '\(repository.name)'? This will not delete the repository files.")
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Repositories")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Create a repository to start backing up your files")
                .foregroundColor(.secondary)
            
            Button("Create Repository") {
                showingCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var repositoryListView: some View {
        List {
            ForEach(viewModel.repositories) { repository in
                repositoryRow(repository)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Label("Add Repository", systemImage: "plus")
                }
            }
        }
    }
    
    private func repositoryRow(_ repository: Repository) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(repository.name)
                    .font(.headline)
                
                Text(repository.path.path)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Created: \(repository.createdAt.formatted())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Menu {
                Button(role: .destructive) {
                    repositoryToDelete = repository
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}