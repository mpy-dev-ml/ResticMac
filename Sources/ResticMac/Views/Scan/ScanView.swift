import SwiftUI

struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel
    @State private var showFilePicker = false
    
    init(resticService: ResticServiceProtocol) {
        _viewModel = StateObject(wrappedValue: ScanViewModel(resticService: resticService))
    }
    
    var body: some View {
        VStack {
            Button("Select Directory") {
                showFilePicker = true
            }
            .disabled(viewModel.isScanning)
            
            if viewModel.isScanning {
                ProgressView("Scanning...")
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
                                if result.isValid, let snapshots = result.snapshots {
                                    Text("\(snapshots.count) snapshots")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder]
        ) { result in
            switch result {
            case .success(let url):
                Task {
                    await viewModel.scanDirectory(url)
                }
            case .failure(let error):
                print("Error selecting directory: \(error.localizedDescription)")
            }
        }
    }
}
