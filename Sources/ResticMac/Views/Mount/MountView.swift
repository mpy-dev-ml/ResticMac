import SwiftUI
import UniformTypeIdentifiers

struct MountView: View {
    @StateObject private var viewModel: MountViewModel
    @State private var showMountSheet = false
    @State private var selectedMountPoint: MountService.MountPoint?
    @State private var showErrorAlert = false
    @State private var errorMessage: String?
    
    init(mountService: MountService, resticService: ResticService) {
        _viewModel = StateObject(wrappedValue: MountViewModel(mountService: mountService, resticService: resticService))
    }
    
    var body: some View {
        NavigationSplitView {
            List(viewModel.activeMounts, selection: $selectedMountPoint) { mount in
                MountPointRow(mount: mount)
                    .contextMenu {
                        Button("Open in Finder") {
                            NSWorkspace.shared.open(mount.path)
                        }
                        Button("Unmount", role: .destructive) {
                            Task {
                                await viewModel.unmount(mount)
                            }
                        }
                    }
            }
            .navigationTitle("Mounted Repositories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showMountSheet = true }) {
                        Label("Mount Repository", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let mount = selectedMountPoint {
                MountDetailView(mount: mount)
            } else {
                ContentUnavailableView(
                    "No Mount Selected",
                    systemImage: "externaldrive",
                    description: Text("Select a mounted repository to view its details")
                )
            }
        }
        .sheet(isPresented: $showMountSheet) {
            MountRepositorySheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: viewModel.error) { error in
            if let error = error {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

struct MountPointRow: View {
    let mount: MountService.MountPoint
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: mount.isSnapshotMount ? "clock.fill" : "folder.fill")
                    .foregroundStyle(.secondary)
                Text(mount.path.lastPathComponent)
                    .font(.headline)
            }
            
            Text(mount.path.path)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let snapshot = mount.snapshot {
                Text("Snapshot: \(snapshot)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("Mounted \(mount.startTime.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MountDetailView: View {
    let mount: MountService.MountPoint
    @State private var directoryContents: [URL] = []
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        VStack {
            // Mount Info Header
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Mount Point") {
                        Text(mount.path.path)
                            .textSelection(.enabled)
                    }
                    
                    if let snapshot = mount.snapshot {
                        LabeledContent("Snapshot") {
                            Text(snapshot)
                                .textSelection(.enabled)
                        }
                    }
                    
                    LabeledContent("Mounted") {
                        Text(mount.startTime.formatted())
                    }
                    
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(mount.path)
                    }
                }
                .padding()
            }
            .padding()
            
            // Directory Contents
            List {
                ForEach(directoryContents, id: \.self) { url in
                    FileRow(url: url)
                }
            }
        }
        .navigationTitle(mount.path.lastPathComponent)
        .task {
            await loadDirectoryContents()
        }
    }
    
    private func loadDirectoryContents() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: mount.path,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ]
            )
            await MainActor.run {
                directoryContents = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
            }
        } catch {
            self.error = error
        }
    }
}

struct FileRow: View {
    let url: URL
    @State private var isDirectory: Bool = false
    @State private var fileSize: Int64?
    @State private var modificationDate: Date?
    
    var body: some View {
        HStack {
            Image(systemName: isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading) {
                Text(url.lastPathComponent)
                    .font(.body)
                
                HStack {
                    if let fileSize = fileSize {
                        Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    }
                    if let modificationDate = modificationDate {
                        Text("Modified \(modificationDate.formatted(.relative(presentation: .named)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .task {
            await loadFileAttributes()
        }
        .contextMenu {
            if !isDirectory {
                Button("Quick Look") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
    
    private func loadFileAttributes() async {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey
            ])
            
            await MainActor.run {
                isDirectory = resourceValues.isDirectory ?? false
                fileSize = resourceValues.fileSize as Int64?
                modificationDate = resourceValues.contentModificationDate
            }
        } catch {
            print("Error loading file attributes: \(error)")
        }
    }
}

struct MountRepositorySheet: View {
    @ObservedObject var viewModel: MountViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedRepository: Repository?
    @State private var selectedSnapshot: Snapshot?
    @State private var mountPoint: String = ""
    @State private var showSnapshotPicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Repository") {
                    Picker("Repository", selection: $selectedRepository) {
                        Text("Select Repository").tag(nil as Repository?)
                        ForEach(viewModel.repositories) { repository in
                            Text(repository.name).tag(Optional(repository))
                        }
                    }
                }
                
                if let repository = selectedRepository {
                    Section("Snapshot (Optional)") {
                        HStack {
                            if let snapshot = selectedSnapshot {
                                VStack(alignment: .leading) {
                                    Text(snapshot.id.prefix(8))
                                        .font(.headline)
                                    Text(snapshot.time.formatted())
                                        .font(.caption)
                                }
                            } else {
                                Text("Latest Version")
                            }
                            
                            Spacer()
                            
                            Button("Choose...") {
                                showSnapshotPicker = true
                            }
                        }
                    }
                    
                    Section("Mount Location") {
                        HStack {
                            TextField("Mount Point", text: $mountPoint)
                            Button("Choose...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                
                                if panel.runModal() == .OK {
                                    mountPoint = panel.url?.path ?? ""
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Mount Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mount") {
                        Task {
                            guard let repository = selectedRepository,
                                  !mountPoint.isEmpty else { return }
                            
                            await viewModel.mount(
                                repository: repository,
                                at: URL(fileURLWithPath: mountPoint),
                                snapshot: selectedSnapshot?.id
                            )
                            dismiss()
                        }
                    }
                    .disabled(selectedRepository == nil || mountPoint.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showSnapshotPicker) {
            if let repository = selectedRepository {
                SnapshotPickerSheet(
                    viewModel: viewModel,
                    repository: repository,
                    selectedSnapshot: $selectedSnapshot
                )
            }
        }
        .task {
            await viewModel.loadRepositories()
        }
    }
}

struct SnapshotPickerSheet: View {
    @ObservedObject var viewModel: MountViewModel
    let repository: Repository
    @Binding var selectedSnapshot: Snapshot?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(selection: $selectedSnapshot) {
                ForEach(viewModel.snapshots) { snapshot in
                    SnapshotRow(snapshot: snapshot)
                        .tag(snapshot)
                }
            }
            .navigationTitle("Choose Snapshot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Choose") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadSnapshots(for: repository)
        }
    }
}

struct SnapshotRow: View {
    let snapshot: Snapshot
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(snapshot.time.formatted())
                .font(.headline)
            
            Text("ID: \(snapshot.id.prefix(8))")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let tags = snapshot.tags, !tags.isEmpty {
                HStack {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
