import SwiftUI
import AppKit

struct MacTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.isEditable = true
        textField.isSelectable = true
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        
        init(text: Binding<String>) {
            self.text = text
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text.wrappedValue = textField.stringValue
                print("Text changed to: \(textField.stringValue)")
            }
        }
    }
}

struct MacSecureTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    
    func makeNSView(context: Context) -> NSSecureTextField {
        let textField = NSSecureTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.isEditable = true
        textField.isSelectable = true
        return textField
    }
    
    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        nsView.stringValue = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        
        init(text: Binding<String>) {
            self.text = text
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSSecureTextField {
                text.wrappedValue = textField.stringValue
                print("Password field updated")
            }
        }
    }
}

struct PasswordStrengthIndicator: View {
    let password: String
    
    private var strength: PasswordStrength {
        let hasMinLength = password.count >= 8
        let hasUppercase = password.contains(where: { $0.isUppercase })
        let hasLowercase = password.contains(where: { $0.isLowercase })
        let hasNumber = password.contains(where: { $0.isNumber })
        let hasSpecial = password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) })
        
        let score = [hasMinLength, hasUppercase, hasLowercase, hasNumber, hasSpecial]
            .filter { $0 }
            .count
        
        switch score {
        case 0...1: return .weak
        case 2...3: return .moderate
        case 4: return .strong
        case 5: return .veryStrong
        default: return .weak
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<4) { index in
                    Rectangle()
                        .frame(height: 4)
                        .foregroundColor(colorForBar(at: index))
                }
            }
            .animation(.easeInOut, value: strength)
            
            Text(strength.description)
                .font(.caption)
                .foregroundColor(strength.color)
        }
    }
    
    private func colorForBar(at index: Int) -> Color {
        switch (strength, index) {
        case (.weak, 0): return .red
        case (.moderate, 0...1): return .orange
        case (.strong, 0...2): return .yellow
        case (.veryStrong, _): return .green
        default: return .gray.opacity(0.3)
        }
    }
}

private enum PasswordStrength {
    case weak
    case moderate
    case strong
    case veryStrong
    
    var description: String {
        switch self {
        case .weak: return "Weak"
        case .moderate: return "Moderate"
        case .strong: return "Strong"
        case .veryStrong: return "Very Strong"
        }
    }
    
    var color: Color {
        switch self {
        case .weak: return .red
        case .moderate: return .orange
        case .strong: return .yellow
        case .veryStrong: return .green
        }
    }
}

struct RepositoryForm: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: RepositoryViewModel
    
    @State private var name = ""
    @State private var path: URL?
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingPathPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Repository Details") {
                    MacTextField(text: $name, placeholder: "Repository Name")
                        .frame(height: 24)
                        .onAppear {
                            print("Name field appeared")
                        }
                    
                    pathPicker
                }
                
                Section("Security") {
                    MacSecureTextField(text: $password, placeholder: "Password")
                        .frame(height: 24)
                    
                    if !password.isEmpty {
                        PasswordStrengthIndicator(password: password)
                            .padding(.vertical, 4)
                    }
                    
                    MacSecureTextField(text: $confirmPassword, placeholder: "Confirm Password")
                        .frame(height: 24)
                    
                    if !password.isEmpty && password != confirmPassword {
                        Text("Passwords do not match")
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password Requirements:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        RequirementRow(text: "At least 8 characters", 
                                     isMet: password.count >= 8)
                        RequirementRow(text: "Contains uppercase letter", 
                                     isMet: password.contains(where: { $0.isUppercase }))
                        RequirementRow(text: "Contains number", 
                                     isMet: password.contains(where: { $0.isNumber }))
                        RequirementRow(text: "Contains special character", 
                                     isMet: password.contains(where: { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }))
                    }
                }
            }
            .disabled(viewModel.isCreatingRepository)
            .navigationTitle("Create Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isCreatingRepository)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createRepository()
                    }
                    .disabled(!canCreate || viewModel.isCreatingRepository)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .onAppear {
            print("Form view appeared")
        }
    }
    
    private var canCreate: Bool {
        guard let path = path else { return false }
        return !name.isEmpty &&
        viewModel.validatePath(path) &&
        viewModel.validatePassword(password) &&
        password == confirmPassword
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
                print("Opening file picker...")
                showingPathPicker = true
            }
        }
        .fileImporter(
            isPresented: $showingPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            print("File picker result received")
            switch result {
            case .success(let urls):
                print("Selected URLs: \(urls)")
                guard let selectedPath = urls.first else {
                    print("No path selected")
                    return
                }
                path = selectedPath
                print("Path set to: \(selectedPath)")
            case .failure(let error):
                print("File picker error: \(error)")
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func createRepository() {
        guard let selectedPath = path else {
            print("No path selected for repository creation")
            return
        }
        
        print("Creating repository with name: \(name), path: \(selectedPath)")
        Task {
            do {
                try await viewModel.createRepository(
                    name: name,
                    path: selectedPath,
                    password: password
                )
                print("Repository created successfully")
                dismiss()
            } catch {
                print("Repository creation failed: \(error)")
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

struct RequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .gray)
            
            Text(text)
                .font(.caption)
                .foregroundColor(isMet ? .primary : .secondary)
        }
    }
}

struct RepositoryFormPreview: View {
    var body: some View {
        RepositoryForm(viewModel: RepositoryViewModel(
            resticService: PreviewResticService(),
            commandDisplay: CommandDisplayViewModel()
        ))
    }
}

#if DEBUG
struct RepositoryForm_Previews: PreviewProvider {
    static var previews: some View {
        RepositoryFormPreview()
    }
}
#endif