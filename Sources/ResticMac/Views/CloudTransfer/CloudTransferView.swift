import SwiftUI

struct CloudTransferView: View {
    @StateObject private var viewModel: CloudTransferViewModel
    @State private var selectedTransfer: CloudOptimizer.TransferState?
    @State private var showErrorAlert = false
    @State private var errorMessage: String?
    
    init(cloudOptimizer: CloudOptimizer) {
        _viewModel = StateObject(wrappedValue: CloudTransferViewModel(cloudOptimizer: cloudOptimizer))
    }
    
    var body: some View {
        NavigationSplitView {
            List(viewModel.activeTransfers, id: \.id, selection: $selectedTransfer) { transfer in
                TransferRow(transfer: transfer)
                    .contextMenu {
                        if transfer.status == .inProgress {
                            Button("Pause", role: .cancel) {
                                Task {
                                    await viewModel.pauseTransfer(transfer)
                                }
                            }
                        } else if transfer.status == .paused {
                            Button("Resume") {
                                Task {
                                    await viewModel.resumeTransfer(transfer)
                                }
                            }
                        }
                        
                        if case .failed = transfer.status {
                            Button("Retry") {
                                Task {
                                    await viewModel.retryTransfer(transfer)
                                }
                            }
                        }
                        
                        Button("Cancel", role: .destructive) {
                            Task {
                                await viewModel.cancelTransfer(transfer)
                            }
                        }
                    }
            }
            .navigationTitle("Cloud Transfers")
            .toolbar {
                ToolbarItem(placement: .status) {
                    TransferStatusView(viewModel: viewModel)
                }
            }
        } detail: {
            if let transfer = selectedTransfer {
                TransferDetailView(transfer: transfer)
            } else {
                ContentUnavailableView(
                    "No Transfer Selected",
                    systemImage: "icloud.and.arrow.up",
                    description: Text("Select a transfer to view its details")
                )
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: viewModel.error) { error in
            if let error = error {
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

struct TransferRow: View {
    let transfer: CloudOptimizer.TransferState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ProviderIcon(provider: transfer.provider)
                
                Text(transfer.id)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                TransferStatusBadge(status: transfer.status)
            }
            
            if transfer.status == .inProgress {
                ProgressView(value: Double(transfer.bytesTransferred), total: Double(transfer.totalBytes))
                    .progressViewStyle(.linear)
                
                HStack {
                    Text(formatBytes(transfer.bytesTransferred))
                    Text("of")
                    Text(formatBytes(transfer.totalBytes))
                    
                    Spacer()
                    
                    if let timeRemaining = transfer.estimatedTimeRemaining {
                        Text(formatTimeRemaining(timeRemaining))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Text("Transfer Rate: \(formatTransferRate(transfer.transferRate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "Less than a minute"
        } else if seconds < 3600 {
            let minutes = Int(ceil(seconds / 60))
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = Int(ceil(seconds / 3600))
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
    }
    
    private func formatTransferRate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}

struct ProviderIcon: View {
    let provider: CloudProvider
    
    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
    }
    
    private var iconName: String {
        switch provider {
        case .s3: "aws"
        case .b2: "externaldrive.badge.icloud"
        case .azure: "cloud"
        case .gcs: "g.circle"
        case .sftp: "network"
        case .rest: "server.rack"
        }
    }
    
    private var iconColor: Color {
        switch provider {
        case .s3: .orange
        case .b2: .blue
        case .azure: .blue
        case .gcs: .green
        case .sftp: .purple
        case .rest: .gray
        }
    }
}

struct TransferStatusBadge: View {
    let status: CloudOptimizer.TransferState.TransferStatus
    
    var body: some View {
        Text(statusText)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.2))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }
    
    private var statusText: String {
        switch status {
        case .inProgress: "In Progress"
        case .paused: "Paused"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .inProgress: .blue
        case .paused: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}

struct TransferDetailView: View {
    let transfer: CloudOptimizer.TransferState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Transfer Info
                GroupBox("Transfer Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "ID", value: transfer.id)
                        DetailRow(label: "Provider", value: transfer.provider.displayName)
                        DetailRow(label: "Status", value: statusText)
                        DetailRow(label: "Started", value: transfer.startTime.formatted())
                        DetailRow(label: "Last Updated", value: transfer.lastUpdateTime.formatted())
                        
                        if case .failed(let error) = transfer.status {
                            DetailRow(label: "Error", value: error.localizedDescription)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                }
                
                // Progress Info
                if transfer.status == .inProgress {
                    GroupBox("Progress") {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: Double(transfer.bytesTransferred), total: Double(transfer.totalBytes))
                                .progressViewStyle(.linear)
                            
                            DetailRow(
                                label: "Transferred",
                                value: "\(formatBytes(transfer.bytesTransferred)) of \(formatBytes(transfer.totalBytes))"
                            )
                            
                            DetailRow(
                                label: "Transfer Rate",
                                value: formatTransferRate(transfer.transferRate)
                            )
                            
                            if let timeRemaining = transfer.estimatedTimeRemaining {
                                DetailRow(
                                    label: "Time Remaining",
                                    value: formatTimeRemaining(timeRemaining)
                                )
                            }
                        }
                        .padding()
                    }
                }
                
                // Retry Info
                if transfer.retryCount > 0 {
                    GroupBox("Retry Information") {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(
                                label: "Retry Count",
                                value: "\(transfer.retryCount)"
                            )
                        }
                        .padding()
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Transfer Details")
    }
    
    private var statusText: String {
        switch transfer.status {
        case .inProgress: "In Progress"
        case .paused: "Paused"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private func formatTransferRate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
    
    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "Less than a minute"
        } else if seconds < 3600 {
            let minutes = Int(ceil(seconds / 60))
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = Int(ceil(seconds / 3600))
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .textSelection(.enabled)
        }
    }
}

struct TransferStatusView: View {
    @ObservedObject var viewModel: CloudTransferViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            if !viewModel.activeTransfers.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                    
                    Text("\(viewModel.activeTransfers.count) Active")
                        .foregroundStyle(.secondary)
                }
            }
            
            if viewModel.totalUploadRate > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .foregroundStyle(.green)
                    
                    Text(formatTransferRate(viewModel.totalUploadRate))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func formatTransferRate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}
