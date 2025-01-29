import SwiftUI

/// A view component that allows users to select multiple folders for backup.
/// Provides a list interface to add and remove paths with proper visual feedback.
struct PathSelector: View {
    @Binding var selectedPaths: [URL]
    @State private var isShowingFileDialogue = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected Folders")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    isShowingFileDialogue = true
                }) {
                    Label("Add Folder", systemImage: "plus.circle")
                }
            }
            
            if selectedPaths.isEmpty {
                Text("No folders selected")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                List {
                    ForEach(selectedPaths, id: \.self) { path in
                        HStack {
                            Label(path.path, systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button(action: {
                                selectedPaths.removeAll { $0 == path }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .accessibilityLabel("Remove folder")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 100, maxHeight: 200)
            }
        }
        .fileImporter(
            isPresented: $isShowingFileDialogue,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                selectedPaths.append(contentsOf: urls)
            case .failure(let error):
                print("Error selecting folders: \(error.localizedDescription)")
            }
        }
    }
}

struct PathSelector_Previews: PreviewProvider {
    static var previews: some View {
        PathSelector(selectedPaths: .constant([
            URL(fileURLWithPath: "/Users/example/Documents"),
            URL(fileURLWithPath: "/Users/example/Pictures")
        ]))
        .padding()
        .frame(width: 400)
    }
}
