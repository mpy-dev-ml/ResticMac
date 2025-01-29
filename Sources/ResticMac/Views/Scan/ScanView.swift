import SwiftUI

struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel
    @State private var showFilePicker = false
    
    init(resticService: any ResticServiceProtocol) {
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
                    ForEach(viewModel.repositories) { result in
                        VStack(alignment: .leading) {
                            Text(result.name)
                                .font(.headline)
                            Text(result.path.path)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            Task {
                await viewModel.handleSelectedDirectory(result)
            }
        }
        .padding()
    }
}
