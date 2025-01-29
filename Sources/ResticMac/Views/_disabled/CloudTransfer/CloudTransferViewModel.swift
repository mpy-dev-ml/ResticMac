import Foundation
import SwiftUI

@MainActor
class CloudTransferViewModel: ObservableObject {
    private let cloudOptimizer: CloudOptimizer
    private var updateTimer: Timer?
    
    @Published private(set) var activeTransfers: [CloudOptimizer.TransferState] = []
    @Published private(set) var error: Error?
    @Published private(set) var totalUploadRate: Double = 0
    @Published private(set) var isLoading = false
    
    init(cloudOptimizer: CloudOptimizer) {
        self.cloudOptimizer = cloudOptimizer
        startMonitoring()
    }
    
    private func startMonitoring() {
        // Update transfers every second
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateTransfers()
            }
        }
    }
    
    private func updateTransfers() async {
        activeTransfers = await cloudOptimizer.getActiveTransfers()
        
        // Calculate total upload rate
        totalUploadRate = activeTransfers
            .filter { $0.status == .inProgress }
            .reduce(0) { $0 + $1.transferRate }
    }
    
    func pauseTransfer(_ transfer: CloudOptimizer.TransferState) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Implementation will depend on ResticService's ability to pause transfers
            // For now, we'll just update the UI
            await updateTransfers()
        } catch {
            self.error = error
        }
    }
    
    func resumeTransfer(_ transfer: CloudOptimizer.TransferState) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Implementation will depend on ResticService's ability to resume transfers
            // For now, we'll just update the UI
            await updateTransfers()
        } catch {
            self.error = error
        }
    }
    
    func retryTransfer(_ transfer: CloudOptimizer.TransferState) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard await cloudOptimizer.shouldRetry(id: transfer.id) else {
                throw TransferError.maxRetriesExceeded
            }
            
            let delay = await cloudOptimizer.getRetryDelay(id: transfer.id)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            // Implementation will depend on ResticService's ability to retry transfers
            // For now, we'll just update the UI
            await updateTransfers()
        } catch {
            self.error = error
        }
    }
    
    func cancelTransfer(_ transfer: CloudOptimizer.TransferState) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Implementation will depend on ResticService's ability to cancel transfers
            // For now, we'll just update the UI
            await updateTransfers()
        } catch {
            self.error = error
        }
    }
    
    var completedTransfers: [CloudOptimizer.TransferState] {
        activeTransfers.filter { $0.status == .completed }
    }
    
    var failedTransfers: [CloudOptimizer.TransferState] {
        activeTransfers.filter {
            if case .failed = $0.status {
                return true
            }
            return false
        }
    }
    
    var inProgressTransfers: [CloudOptimizer.TransferState] {
        activeTransfers.filter { $0.status == .inProgress }
    }
    
    var pausedTransfers: [CloudOptimizer.TransferState] {
        activeTransfers.filter { $0.status == .paused }
    }
    
    var totalProgress: Double {
        let totalBytes = activeTransfers.reduce(0) { $0 + $1.totalBytes }
        let transferredBytes = activeTransfers.reduce(0) { $0 + $1.bytesTransferred }
        
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }
    
    var estimatedTimeRemaining: TimeInterval? {
        guard totalUploadRate > 0 else { return nil }
        
        let remainingBytes = activeTransfers
            .filter { $0.status == .inProgress }
            .reduce(0) { $0 + ($1.totalBytes - $1.bytesTransferred) }
        
        return Double(remainingBytes) / totalUploadRate
    }
    
    deinit {
        updateTimer?.invalidate()
    }
}

// MARK: - Errors

enum TransferError: LocalizedError {
    case maxRetriesExceeded
    case invalidTransferState
    case transferCancelled
    
    var errorDescription: String? {
        switch self {
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded"
        case .invalidTransferState:
            return "Invalid transfer state"
        case .transferCancelled:
            return "Transfer was cancelled"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .maxRetriesExceeded:
            return "Try starting a new transfer"
        case .invalidTransferState:
            return "Try restarting the transfer"
        case .transferCancelled:
            return "Start a new transfer if needed"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let transferStarted = Notification.Name("TransferStarted")
    static let transferCompleted = Notification.Name("TransferCompleted")
    static let transferFailed = Notification.Name("TransferFailed")
    static let transferPaused = Notification.Name("TransferPaused")
    static let transferResumed = Notification.Name("TransferResumed")
    static let transferCancelled = Notification.Name("TransferCancelled")
}
