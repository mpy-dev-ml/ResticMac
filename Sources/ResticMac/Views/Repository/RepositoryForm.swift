import SwiftUI
import Foundation

struct RepositoryForm: View {
    @Environment(\.dismiss) private var dismiss: DismissAction
    @ObservedObject var viewModel: RepositoryViewModel
    
    @State private var name = ""
    @State private var path: URL? = nil
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingPathPicker = false
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    
    var body: some View {
        Form {
            Section("Repository Details") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isCreatingRepository)
                    if !viewModel.validationState.isNameValid {
                        Text(viewModel.validationState.nameError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    pathPicker
                    if !viewModel.validationState.isPathValid {
                        Text(viewModel.validationState.pathError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            
            Section("Security") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if isPasswordVisible {
                            TextField("Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { isPasswordVisible.toggle() }) {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }
                    if !viewModel.validationState.isPasswordValid {
                        Text(viewModel.validationState.passwordError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    HStack {
                        if isConfirmPasswordVisible {
                            TextField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { isConfirmPasswordVisible.toggle() }) {
                            Image(systemName: isConfirmPasswordVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                passwordRequirements
            }
            
            Section {
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isCreatingRepository)
                    
                    Spacer()
                    
                    Button("Create Repository") {
                        guard let path = path else { return }
                        Task {
                            await viewModel.createRepository(
                                name: name,
                                path: path,
                                password: password
                            )
                            if !viewModel.showError {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isCreatingRepository || !isFormValid)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $showingPathPicker) {
            PathPicker(onSelect: { selectedPath in
                path = selectedPath
            })
        }
    }
    
    private var isFormValid: Bool {
        !name.isEmpty &&
        path != nil &&
        !password.isEmpty &&
        password == confirmPassword &&
        viewModel.validatePassword(password)
    }
    
    private var passwordRequirements: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Password Requirements:")
                .font(.caption)
                .foregroundColor(.secondary)
            RequirementRow(text: "At least 8 characters", 
                         isMet: password.count >= 8)
            RequirementRow(text: "Contains uppercase letter", 
                         isMet: password.contains(where: { $0.isUppercase }))
            RequirementRow(text: "Contains lowercase letter", 
                         isMet: password.contains(where: { $0.isLowercase }))
            RequirementRow(text: "Contains number", 
                         isMet: password.contains(where: { $0.isNumber }))
            RequirementRow(text: "Contains special character", 
                         isMet: password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }))
            if password != confirmPassword {
                Text("Passwords do not match")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
    
    private var pathPicker: some View {
        HStack {
            if let path = path {
                Text(path.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Select Location")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Choose...") {
                showingPathPicker = true
            }
        }
    }
}

struct RequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .secondary)
            Text(text)
                .foregroundColor(isMet ? .primary : .secondary)
        }
    }
}