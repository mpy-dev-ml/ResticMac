import SwiftUI
import LocalAuthentication

struct CloudSettingsView: View {
    @StateObject private var viewModel: CloudSettingsViewModel
    @State private var showingProviderSheet = false
    @State private var showingDeleteAlert = false
    @State private var selectedProvider: CloudProvider?
    
    init(repository: Repository) {
        _viewModel = StateObject(wrappedValue: CloudSettingsViewModel(repository: repository))
    }
    
    var body: some View {
        List {
            // Provider Configuration
            Section {
                if let provider = viewModel.currentProvider {
                    HStack {
                        ProviderIcon(provider: provider)
                        VStack(alignment: .leading) {
                            Text(provider.displayName)
                                .font(.headline)
                            Text(viewModel.formattedEndpoint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            selectedProvider = provider
                            showingProviderSheet = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                } else {
                    Button {
                        showingProviderSheet = true
                    } label: {
                        Label("Add Cloud Provider", systemImage: "plus.circle.fill")
                    }
                }
            } header: {
                Text("Cloud Provider")
            } footer: {
                if viewModel.currentProvider != nil {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Remove Provider", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Connection Settings
            Section("Connection Settings") {
                Toggle("Use Compression", isOn: $viewModel.useCompression)
                    .onChange(of: viewModel.useCompression) { _ in
                        Task {
                            await viewModel.saveSettings()
                        }
                    }
                
                Picker("Compression Level", selection: $viewModel.compressionLevel) {
                    ForEach(CompressionLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .disabled(!viewModel.useCompression)
                
                Stepper("Concurrent Operations: \(viewModel.maxConcurrentOperations)", 
                        value: $viewModel.maxConcurrentOperations, in: 1...10)
                    .onChange(of: viewModel.maxConcurrentOperations) { _ in
                        Task {
                            await viewModel.saveSettings()
                        }
                    }
                
                Toggle("Use Network Rate Limiting", isOn: $viewModel.useRateLimiting)
                    .onChange(of: viewModel.useRateLimiting) { _ in
                        Task {
                            await viewModel.saveSettings()
                        }
                    }
                
                if viewModel.useRateLimiting {
                    HStack {
                        Text("Upload Limit")
                        Spacer()
                        TextField("MB/s", value: $viewModel.uploadRateLimit, format: .number)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("MB/s")
                    }
                    
                    HStack {
                        Text("Download Limit")
                        Spacer()
                        TextField("MB/s", value: $viewModel.downloadRateLimit, format: .number)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("MB/s")
                    }
                }
            }
            
            // Security Settings
            Section("Security") {
                Toggle("Use Keychain", isOn: $viewModel.useKeychain)
                    .onChange(of: viewModel.useKeychain) { _ in
                        Task {
                            await viewModel.saveSettings()
                        }
                    }
                
                if viewModel.useKeychain {
                    Toggle("Require Authentication", isOn: $viewModel.requireAuthentication)
                        .onChange(of: viewModel.requireAuthentication) { _ in
                            Task {
                                await viewModel.saveSettings()
                            }
                        }
                    
                    if viewModel.requireAuthentication {
                        Picker("Authentication Method", selection: $viewModel.authMethod) {
                            ForEach(AuthenticationMethod.allCases) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                    }
                }
                
                Toggle("Encrypt Transfers", isOn: $viewModel.encryptTransfers)
                    .onChange(of: viewModel.encryptTransfers) { _ in
                        Task {
                            await viewModel.saveSettings()
                        }
                    }
            }
            
            // Advanced Settings
            Section("Advanced") {
                Toggle("Auto-Retry Failed Transfers", isOn: $viewModel.autoRetry)
                    .onChange(of: viewModel.autoRetry) { _ in
                        Task {
                            await viewModel.saveSettings()
                        }
                    }
                
                if viewModel.autoRetry {
                    Stepper("Max Retries: \(viewModel.maxRetries)", 
                            value: $viewModel.maxRetries, in: 1...5)
                        .onChange(of: viewModel.maxRetries) { _ in
                            Task {
                                await viewModel.saveSettings()
                            }
                        }
                }
                
                Toggle("Show Transfer Notifications", isOn: $viewModel.showNotifications)
                    .onChange(of: viewModel.showNotifications) { _ in
                        Task {
                            await viewModel.saveSettings()
                        }
                    }
                
                Toggle("Background Transfers", isOn: $viewModel.allowBackgroundTransfers)
                    .onChange(of: viewModel.allowBackgroundTransfers) { _ in
                        Task {
                            await viewModel.saveSettings()
                        }
                    }
            }
            
            // Cache Settings
            Section("Cache") {
                HStack {
                    Text("Cache Size")
                    Spacer()
                    Text(viewModel.formattedCacheSize)
                        .foregroundColor(.secondary)
                }
                
                Button {
                    Task {
                        await viewModel.clearCache()
                    }
                } label: {
                    Label("Clear Cache", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Cloud Settings")
        .sheet(isPresented: $showingProviderSheet) {
            if let provider = selectedProvider {
                ProviderConfigurationView(provider: provider, viewModel: viewModel)
            } else {
                ProviderSelectionView(viewModel: viewModel)
            }
        }
        .alert("Remove Provider", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.removeProvider()
                }
            }
        } message: {
            Text("Are you sure you want to remove this cloud provider? This will not delete any backed up data but will prevent future backups until a new provider is configured.")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error occurred")
        }
    }
}

// MARK: - Supporting Views

struct ProviderIcon: View {
    let provider: CloudProvider
    
    var body: some View {
        Image(systemName: provider.iconName)
            .font(.title2)
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(provider.color)
            .cornerRadius(8)
    }
}

struct ProviderSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CloudSettingsViewModel
    
    var body: some View {
        NavigationView {
            List(CloudProvider.allCases) { provider in
                Button {
                    viewModel.selectedProvider = provider
                    dismiss()
                } label: {
                    HStack {
                        ProviderIcon(provider: provider)
                        VStack(alignment: .leading) {
                            Text(provider.displayName)
                                .font(.headline)
                            Text(provider.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Select Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProviderConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    let provider: CloudProvider
    @ObservedObject var viewModel: CloudSettingsViewModel
    @State private var endpoint = ""
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var region = ""
    @State private var bucket = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Connection Details") {
                    TextField("Endpoint", text: $endpoint)
                    TextField("Access Key", text: $accessKey)
                    SecureField("Secret Key", text: $secretKey)
                    TextField("Region", text: $region)
                    TextField("Bucket", text: $bucket)
                }
                
                Section {
                    Button("Test Connection") {
                        Task {
                            await viewModel.testConnection(
                                endpoint: endpoint,
                                accessKey: accessKey,
                                secretKey: secretKey,
                                region: region,
                                bucket: bucket
                            )
                        }
                    }
                }
            }
            .navigationTitle("Configure \(provider.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.saveProviderConfiguration(
                                endpoint: endpoint,
                                accessKey: accessKey,
                                secretKey: secretKey,
                                region: region,
                                bucket: bucket
                            )
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Enums

enum CompressionLevel: Int, CaseIterable, Identifiable {
    case none = 0
    case fast = 1
    case default = 6
    case best = 9
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .fast: return "Fast"
        case .default: return "Default"
        case .best: return "Best"
        }
    }
}

enum AuthenticationMethod: String, CaseIterable, Identifiable {
    case touchID = "Touch ID"
    case password = "Password"
    case both = "Both"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
}

// MARK: - Preview

struct CloudSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CloudSettingsView(repository: Repository.preview)
        }
    }
}
