import SwiftUI

struct RepositoryView: View {
    @StateObject private var viewModel: RepositoryViewModel
    @State private var showingForm = false
    @State private var showingError = false
    @State private var showingDeleteAlert = false
    @State private var selectedRepository: Repository?
    
    init(resticService: ResticServiceProtocol, commandDisplay: CommandDisplayViewModel) {
        _viewModel = StateObject(wrappedValue: RepositoryViewModel(resticService: resticService, commandDisplay: commandDisplay))
    }
    
    var body: some View {
        NavigationView {
            List {
                if viewModel.repositories.isEmpty {
                    emptyStateView
                } else {
                    repositoryListView
                }
            }
            .navigationTitle("Repositories")
        }
        .toolbar(content: {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingForm = true }) {
                    Label("Add Repository", systemImage: "plus")
                }
            }
        })
        .sheet(isPresented: $showingForm) {
            RepositoryForm(viewModel: viewModel)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Delete Repository", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let repository = selectedRepository {
                    Task {
                        await viewModel.deleteRepository(repository)
                    }
                }
                selectedRepository = nil
            }
            Button("Cancel", role: .cancel) {
                selectedRepository = nil
            }
        } message: {
            Text("Are you sure you want to delete this repository? This action cannot be undone.")
        }
        .onChange(of: viewModel.errorMessage) { _, message in
            showingError = !message.isEmpty
        }
    }
    
    private var emptyStateView: some View {
        VStack {
            Image(systemName: "folder.badge.questionmark")
                .resizable()
                .frame(width: 100, height: 100)
            Text("No Repositories")
                .font(.largeTitle)
            Text("Create a repository to start backing up your files.")
                .font(.body)
                .padding(.horizontal)
            Button("Create Repository") {
                showingForm = true
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var repositoryListView: some View {
        ForEach(viewModel.repositories) { repository in
            repositoryRow(repository)
        }
    }
    
    private func repositoryRow(_ repository: Repository) -> some View {
        NavigationLink {
            Text("Repository Details")
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(repository.name)
                        .font(.headline)
                    Text(repository.path.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Menu {
                    Button(role: .destructive) {
                        selectedRepository = repository
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}