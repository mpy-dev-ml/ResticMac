import SwiftUI

struct RepositoryForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: RepositoryViewModel
    
    @State private var name = ""
    @State private var path: URL?
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingPathPicker = false
    
    private var canCreate: Bool {
        guard let path = path else { return false }
        return !name.isEmpty &&
        viewModel.validatePath(path) &&
        viewModel.validatePassword(password) &&
        password == confirmPassword
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Repository Details") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    
                    pathPicker
                }
                
                Section("Security") {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                    
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                }
                
                if !password.isEmpty && password != confirmPassword {
                    Text("Passwords do not match")
                        .foregroundColor(.red)
                }
                
                if password.count > 0 && password.count < 8 {
                    Text("Password must be at least 8 characters")
                        .foregroundColor(.red)
                }
            }
            .disabled(viewModel.isCreatingRepository)
            .navigationTitle("Create Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createRepository()
                    }
                    .disabled(!canCreate || viewModel.isCreatingRepository)
                }
            }
            .fileImporter(
                isPresented: $showingPathPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    path = urls.first
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showError = true
                }
            }
        }
    }
    
    private var pathPicker: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Location")
                    .foregroundColor(.secondary)
                if let path = path {
                    Text(path.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Select a folder")
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button("Choose") {
                showingPathPicker = true
            }
        }
    }
    
    private func createRepository() {
        guard let path = path else { return }
        Task {
            do {
                try await viewModel.createRepository(
                    name: name,
                    path: path,
                    password: password
                )
                dismiss()
            } catch {
                // Handle error
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}