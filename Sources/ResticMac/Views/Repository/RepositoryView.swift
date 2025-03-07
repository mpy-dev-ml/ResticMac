import SwiftUI

struct RepositoryView: View {
    @StateObject private var viewModel: RepositoryViewModel
    @State private var showingForm = false
    @State private var showingDeleteAlert = false
    @State private var navigationPath = NavigationPath()
    
    init(resticService: ResticServiceProtocol, commandDisplay: CommandDisplayViewModel) {
        _viewModel = StateObject(wrappedValue: RepositoryViewModel(resticService: resticService, commandDisplay: commandDisplay))
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                if viewModel.repositories.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(viewModel.repositories) { repository in
                            NavigationLink {
                                RepositoryDetailView(repository: repository, viewModel: viewModel)
                            } label: {
                                RepositoryRowView(
                                    repository: repository,
                                    isSelected: viewModel.selectedRepository?.id == repository.id
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation {
                                        // Use the repository from our list to ensure we have latest version
                                        viewModel.selectRepository(repository)
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.selectRepository(repository)
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { indexSet in
                            guard let index = indexSet.first,
                                  index < viewModel.repositories.count else { return }
                            let repository = viewModel.repositories[index]
                            viewModel.selectRepository(repository)
                            showingDeleteAlert = true
                        }
                    }
                    .listStyle(.inset)
                    .refreshable {
                        await viewModel.refreshRepositories()
                    }
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Repositories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingForm = true }) {
                        Label("Add Repository", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            RepositoryForm(viewModel: viewModel)
        }
        .alert("Delete Repository", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let repository = viewModel.selectedRepository {
                    Task {
                        await viewModel.deleteRepository(repository)
                    }
                }
                viewModel.selectRepository(nil)
            }
            Button("Cancel", role: .cancel) {
                viewModel.selectRepository(nil)
            }
        } message: {
            Text("Are you sure you want to delete this repository? This action cannot be undone.")
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
}

struct RepositoryRowView: View {
    let repository: Repository
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(repository.name)
                    .font(.headline)
                Text(repository.path.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let lastBackup = repository.lastBackup {
                    Text("Last backup: \(lastBackup.formatted())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 8))
                .opacity(isSelected ? 1 : 0.5)
                .animation(.easeInOut, value: isSelected)
        }
    }
}