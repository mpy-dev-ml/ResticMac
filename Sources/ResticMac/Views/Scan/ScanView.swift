import SwiftUI

struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel
    @State private var showingDirectoryPicker = false
    
    init(resticService: ResticServiceProtocol) {
        _viewModel = StateObject(wrappedValue: ScanViewModel(resticService: resticService))
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Repository Scanner")
                    .font(.title)
                Spacer()
                Button("Scan Directory") {
                    showingDirectoryPicker = true
                }
                .disabled(viewModel.isScanning)
            }
            .padding()
            
            if viewModel.isScanning {
                ProgressView("Scanning for repositories...")
            } else {
                List {
                    Section("Found Repositories") {
                        ForEach(viewModel.scanResults) { result in
                            VStack(alignment: .leading) {
                                HStack {
                                    Image(systemName: result.isValid ? "checkmark.circle" : "xmark.circle")
                                        .foregroundColor(result.isValid ? .green : .red)
                                    Text(result.path.path)
                                }
                                if result.isValid {
                                    Text("\(result.snapshots.count) snapshots")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    if !viewModel.orphanedSnapshots.isEmpty {
                        Section("Orphaned Snapshots") {
                            ForEach(viewModel.orphanedSnapshots, id: \.0.id) { repo, snapshots in
                                DisclosureGroup("\(repo.name) (\(snapshots.count) orphaned)") {
                                    ForEach(snapshots) { snapshot in
                                        VStack(alignment: .leading) {
                                            Text(snapshot.time, style: .date)
                                            Text("Host: \(snapshot.hostname)")
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await viewModel.scanDirectory(url)
                    }
                }
            case .failure(let error):
                viewModel.error = error
            }
        }
    }
}
