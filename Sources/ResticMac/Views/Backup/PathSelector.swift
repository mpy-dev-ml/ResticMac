import SwiftUI

struct PathSelector: View {
    @Binding var selectedPaths: [URL]
    @State private var showingPathPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backup Paths")
                    .font(.headline)
                
                Spacer()
                
                Button("Add Path") {
                    showingPathPicker = true
                }
            }
            
            if selectedPaths.isEmpty {
                Text("No paths selected")
                    .foregroundColor(.secondary)
            } else {
                List {
                    ForEach(selectedPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            
                            Text(path.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button {
                                selectedPaths.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: min(CGFloat(selectedPaths.count) * 30 + 10, 150))
            }
        }
        .fileImporter(
            isPresented: $showingPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                selectedPaths.append(contentsOf: urls)
            case .failure(let error):
                print("Failed to select paths: \(error.localizedDescription)")
            }
        }
    }
}