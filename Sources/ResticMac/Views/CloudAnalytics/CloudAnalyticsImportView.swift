import SwiftUI
import UniformTypeIdentifiers

struct CloudAnalyticsImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CloudAnalyticsImportViewModel
    @State private var showingFilePicker = false
    @State private var showingPreview = false
    
    init(repository: Repository) {
        _viewModel = StateObject(wrappedValue: CloudAnalyticsImportViewModel(repository: repository))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Import Options") {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Select File", systemImage: "doc")
                    }
                    
                    if let selectedFile = viewModel.selectedFile {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text(selectedFile.lastPathComponent)
                                    .font(.headline)
                                Text(selectedFile.pathExtension.uppercased())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                if !viewModel.previewRecords.isEmpty {
                    Section("Preview") {
                        Button {
                            showingPreview = true
                        } label: {
                            Label("View Data Preview", systemImage: "eye")
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Records: \(viewModel.previewRecords.count)")
                            Text("Date Range: \(viewModel.dateRange)")
                            Text("Total Size: \(viewModel.totalSize)")
                        }
                        .font(.caption)
                    }
                }
                
                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button {
                        Task {
                            await viewModel.importData()
                            dismiss()
                        }
                    } label: {
                        if viewModel.isImporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Import Data")
                        }
                    }
                    .disabled(viewModel.selectedFile == nil || viewModel.isImporting)
                }
            }
            .navigationTitle("Import Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        await viewModel.selectFile(url)
                    }
                case .failure(let error):
                    viewModel.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingPreview) {
                ImportPreviewView(records: viewModel.previewRecords)
            }
        }
    }
}

struct ImportPreviewView: View {
    let records: [ImportRecord]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(records.prefix(100), id: \.timestamp) { record in
                    ImportRecordRow(record: record)
                }
                
                if records.count > 100 {
                    Text("Showing first 100 of \(records.count) records")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Data Preview")
            .navigationBarTitleDisplayMode(.inline)
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

struct ImportRecordRow: View {
    let record: ImportRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.timestamp.formatted())
                .font(.headline)
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                GridRow {
                    Text("Storage:")
                    Text(ByteCountFormatter.string(fromByteCount: record.storageMetrics.totalBytes, countStyle: .file))
                }
                
                GridRow {
                    Text("Transfer:")
                    Text(ByteCountFormatter.string(fromByteCount: record.transferMetrics.totalTransferredBytes, countStyle: .file))
                }
                
                GridRow {
                    Text("Snapshots:")
                    Text("\(record.snapshotMetrics.totalSnapshots)")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class CloudAnalyticsImportViewModel: ObservableObject {
    private let repository: Repository
    private let importer: CloudAnalyticsImport
    
    @Published private(set) var selectedFile: URL?
    @Published private(set) var previewRecords: [ImportRecord] = []
    @Published private(set) var isImporting = false
    @Published var error: String?
    
    var dateRange: String {
        guard let first = previewRecords.first?.timestamp,
              let last = previewRecords.last?.timestamp else {
            return "No data"
        }
        return "\(first.formatted()) - \(last.formatted())"
    }
    
    var totalSize: String {
        let bytes = previewRecords.reduce(0) { $0 + $1.storageMetrics.totalBytes }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    init(repository: Repository) {
        self.repository = repository
        self.importer = CloudAnalyticsImport(persistence: CloudAnalyticsPersistence())
    }
    
    func selectFile(_ url: URL) async {
        selectedFile = url
        error = nil
        
        do {
            // Load preview data
            let data = try Data(contentsOf: url)
            let fileType = try identifyFileType(url)
            
            switch fileType {
            case .csv:
                previewRecords = try await loadCSVPreview(data)
            case .json:
                previewRecords = try await loadJSONPreview(data)
            case .resticStats:
                previewRecords = try await loadResticStatsPreview(data)
            }
        } catch {
            self.error = error.localizedDescription
            self.selectedFile = nil
            self.previewRecords = []
        }
    }
    
    func importData() async {
        guard let url = selectedFile else { return }
        
        isImporting = true
        error = nil
        
        do {
            try await importer.importAnalytics(from: url, for: repository)
        } catch {
            self.error = error.localizedDescription
        }
        
        isImporting = false
    }
    
    private func identifyFileType(_ url: URL) throws -> ImportFileType {
        // Implementation similar to CloudAnalyticsImport
        .csv // Placeholder
    }
    
    private func loadCSVPreview(_ data: Data) async throws -> [ImportRecord] {
        // Implementation similar to CloudAnalyticsImport
        [] // Placeholder
    }
    
    private func loadJSONPreview(_ data: Data) async throws -> [ImportRecord] {
        // Implementation similar to CloudAnalyticsImport
        [] // Placeholder
    }
    
    private func loadResticStatsPreview(_ data: Data) async throws -> [ImportRecord] {
        // Implementation similar to CloudAnalyticsImport
        [] // Placeholder
    }
}
