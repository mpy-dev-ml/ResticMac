import SwiftUI

struct CloudAnalyticsErrorView: View {
    let error: CloudAnalyticsError
    let onRetry: () -> Void
    @State private var selectedOption: RecoveryOption?
    @State private var showingRecoveryProgress = false
    @State private var recoveryProgress: Double = 0
    @State private var recoveryStatus: String = ""
    @State private var showingDestructiveWarning = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Error Icon and Title
            VStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                
                Text("Analytics Error")
                    .font(.title2)
                    .bold()
            }
            
            // Error Description
            VStack(alignment: .leading, spacing: 12) {
                Text(error.localizedDescription)
                    .font(.body)
                
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Recovery Options
            if !error.recoveryOptions.isEmpty {
                Divider()
                
                Text("Recovery Options")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ForEach(error.recoveryOptions) { option in
                    RecoveryOptionButton(
                        option: option,
                        isSelected: selectedOption?.id == option.id,
                        onSelect: {
                            if option.isDestructive {
                                showingDestructiveWarning = true
                            } else {
                                selectedOption = option
                                startRecovery(option)
                            }
                        }
                    )
                }
            }
            
            // Retry Button
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(showingRecoveryProgress)
        }
        .padding()
        .sheet(isPresented: $showingRecoveryProgress) {
            RecoveryProgressView(
                option: selectedOption!,
                progress: $recoveryProgress,
                status: $recoveryStatus
            )
        }
        .alert("Warning", isPresented: $showingDestructiveWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                if let option = selectedOption {
                    startRecovery(option)
                }
            }
        } message: {
            Text("This action will delete existing data. Are you sure you want to continue?")
        }
    }
    
    private func startRecovery(_ option: RecoveryOption) {
        showingRecoveryProgress = true
        recoveryProgress = 0
        recoveryStatus = "Initialising..."
        
        Task {
            do {
                // Simulate progress updates
                for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
                    try await Task.sleep(nanoseconds: UInt64(option.estimatedTime * 1_000_000_000 / 10))
                    await MainActor.run {
                        recoveryProgress = progress
                        recoveryStatus = "Processing... \(Int(progress * 100))%"
                    }
                }
                
                try await option.action()
                
                await MainActor.run {
                    recoveryProgress = 1.0
                    recoveryStatus = "Recovery complete"
                    
                    // Close progress view after a delay
                    Task {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                        showingRecoveryProgress = false
                        onRetry()
                    }
                }
            } catch {
                await MainActor.run {
                    recoveryStatus = "Recovery failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct RecoveryOptionButton: View {
    let option: RecoveryOption
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.headline)
                    
                    Text("Estimated time: \(formatDuration(option.estimatedTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !option.requirements.isEmpty {
                        Text("Requires: \(option.requirements.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if option.isDestructive {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }
}

struct RecoveryProgressView: View {
    let option: RecoveryOption
    @Binding var progress: Double
    @Binding var status: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress) {
                Text(option.title)
                    .font(.headline)
            } currentValueLabel: {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if progress < 1.0 {
                Text("Please wait...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
