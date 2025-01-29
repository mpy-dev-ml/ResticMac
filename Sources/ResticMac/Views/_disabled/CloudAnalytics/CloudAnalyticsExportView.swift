import SwiftUI
import UniformTypeIdentifiers

struct CloudAnalyticsExportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CloudAnalyticsExportViewModel
    @State private var showingSavePanel = false
    @State private var selectedFormat: ExportFormat = .csv
    @State private var selectedTimeRange: TimeRange = .month
    @State private var showingPreview = false
    
    init(repository: Repository) {
        _viewModel = StateObject(wrappedValue: CloudAnalyticsExportViewModel(repository: repository))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Export Options") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                }
                
                Section {
                    Button {
                        Task {
                            await viewModel.generatePreview(
                                format: selectedFormat,
                                timeRange: selectedTimeRange
                            )
                            showingPreview = true
                        }
                    } label: {
                        Label("Preview Report", systemImage: "eye")
                    }
                    
                    Button {
                        showingSavePanel = true
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                }
                
                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Export Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingPreview) {
                PreviewView(content: viewModel.previewContent)
            }
            .fileExporter(
                isPresented: $showingSavePanel,
                document: viewModel.exportDocument,
                contentType: selectedFormat.contentType,
                defaultFilename: "cloud_analytics.\(selectedFormat.fileExtension)"
            ) { result in
                if case .failure(let error) = result {
                    viewModel.error = error.localizedDescription
                }
            }
            .disabled(viewModel.isExporting)
            .overlay {
                if viewModel.isExporting {
                    ProgressView("Exporting Data...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(8)
                }
            }
        }
    }
}

struct PreviewView: View {
    let content: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Preview")
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

@MainActor
class CloudAnalyticsExportViewModel: ObservableObject {
    private let repository: Repository
    private let exporter: CloudAnalyticsExport
    
    @Published private(set) var isExporting = false
    @Published private(set) var exportDocument: AnalyticsDocument?
    @Published private(set) var previewContent = ""
    @Published var error: String?
    
    init(repository: Repository) {
        self.repository = repository
        self.exporter = CloudAnalyticsExport(persistence: CloudAnalyticsPersistence())
    }
    
    func generatePreview(format: ExportFormat, timeRange: TimeRange) async {
        isExporting = true
        error = nil
        
        do {
            let report = try await exporter.generateReport(
                for: repository,
                timeRange: timeRange
            )
            
            switch format {
            case .markdown:
                previewContent = report.summary + "\n\n" + String(data: try await formatData(report, format: format), encoding: .utf8)!
            case .json:
                previewContent = String(data: try await formatData(report, format: format), encoding: .utf8)!
            case .csv:
                previewContent = String(data: try await formatData(report, format: format), encoding: .utf8)!
            }
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isExporting = false
    }
    
    private func formatData(_ report: AnalyticsReport, format: ExportFormat) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let data = try JSONEncoder().encode(report)
                continuation.resume(returning: data)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct AnalyticsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .markdown] }
    
    let data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Preview

struct CloudAnalyticsExportView_Previews: PreviewProvider {
    static var previews: some View {
        CloudAnalyticsExportView(repository: Repository.preview)
    }
}
