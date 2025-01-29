import Foundation
import IOKit.ps
import Network
import SystemConfiguration
import os.log

actor SystemMonitor: ObservableObject {
    private let logger = Logger(subsystem: "com.resticmac", category: "SystemMonitor")
    private var powerSourceMonitor: PowerSourceMonitor?
    private var networkMonitor: NetworkMonitor?
    private var diskMonitor: DiskMonitor?
    private var cpuMonitor: CPUMonitor?
    
    @MainActor @Published private(set) var systemState: SystemState
    private var updateTimer: Timer?
    
    init() {
        self.systemState = SystemState()
        setupMonitors()
    }
    
    private func setupMonitors() {
        Task { @MainActor in
            powerSourceMonitor = PowerSourceMonitor { [weak self] state in
                self?.systemState.powerState = state
            }
            
            networkMonitor = NetworkMonitor { [weak self] state in
                self?.systemState.networkState = state
            }
            
            diskMonitor = DiskMonitor { [weak self] state in
                self?.systemState.diskState = state
            }
            
            cpuMonitor = CPUMonitor { [weak self] state in
                self?.systemState.cpuState = state
            }
            
            startMonitoring()
        }
    }
    
    func startMonitoring() {
        powerSourceMonitor?.startMonitoring()
        networkMonitor?.startMonitoring()
        diskMonitor?.startMonitoring()
        cpuMonitor?.startMonitoring()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task {
                await self?.updateSystemState()
            }
        }
    }
    
    func stopMonitoring() {
        powerSourceMonitor?.stopMonitoring()
        networkMonitor?.stopMonitoring()
        diskMonitor?.stopMonitoring()
        cpuMonitor?.stopMonitoring()
        updateTimer?.invalidate()
    }
    
    private func updateSystemState() async {
        await MainActor.run {
            systemState.lastUpdated = Date()
        }
    }
    
    func canStartBackup() -> BackupCondition {
        let conditions = systemState.checkBackupConditions()
        return conditions
    }
    
    deinit {
        stopMonitoring()
    }
}

// MARK: - System State

struct SystemState {
    var powerState: PowerState = .unknown
    var networkState: NetworkState = .unknown
    var diskState: DiskState = .unknown
    var cpuState: CPUState = .unknown
    var lastUpdated: Date = Date()
    
    func checkBackupConditions() -> BackupCondition {
        var conditions = BackupCondition()
        
        // Check power conditions
        switch powerState {
        case .battery(let percentage) where percentage < 20:
            conditions.issues.append(.lowBattery(percentage))
        case .unknown:
            conditions.issues.append(.unknownPowerState)
        default:
            break
        }
        
        // Check network conditions
        switch networkState {
        case .disconnected:
            conditions.issues.append(.noNetwork)
        case .cellular:
            conditions.issues.append(.cellularNetwork)
        case .unknown:
            conditions.issues.append(.unknownNetworkState)
        default:
            break
        }
        
        // Check disk space
        switch diskState {
        case .low(let available):
            conditions.issues.append(.lowDiskSpace(available))
        case .unknown:
            conditions.issues.append(.unknownDiskState)
        default:
            break
        }
        
        // Check CPU usage
        switch cpuState {
        case .high(let usage):
            conditions.issues.append(.highCPUUsage(usage))
        case .unknown:
            conditions.issues.append(.unknownCPUState)
        default:
            break
        }
        
        return conditions
    }
}

// MARK: - Power Source Monitor

class PowerSourceMonitor {
    private var callback: (PowerState) -> Void
    private var timer: Timer?
    
    init(callback: @escaping (PowerState) -> Void) {
        self.callback = callback
    }
    
    func startMonitoring() {
        updatePowerState()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updatePowerState()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updatePowerState() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            callback(.unknown)
            return
        }
        
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            if let isCharging = description[kIOPSIsChargingKey] as? Bool,
               let percentage = description[kIOPSCurrentCapacityKey] as? Int {
                if isCharging {
                    callback(.charging(percentage))
                } else {
                    callback(.battery(percentage))
                }
                return
            }
        }
        
        callback(.unknown)
    }
}

// MARK: - Network Monitor

class NetworkMonitor {
    private let monitor: NWPathMonitor
    private let callback: (NetworkState) -> Void
    
    init(callback: @escaping (NetworkState) -> Void) {
        self.monitor = NWPathMonitor()
        self.callback = callback
    }
    
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            switch path.status {
            case .satisfied:
                if path.usesInterfaceType(.cellular) {
                    self?.callback(.cellular)
                } else if path.usesInterfaceType(.wifi) {
                    self?.callback(.wifi)
                } else {
                    self?.callback(.wired)
                }
            case .unsatisfied:
                self?.callback(.disconnected)
            case .requiresConnection:
                self?.callback(.unknown)
            @unknown default:
                self?.callback(.unknown)
            }
        }
        
        monitor.start(queue: DispatchQueue.main)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
}

// MARK: - Disk Monitor

class DiskMonitor {
    private var callback: (DiskState) -> Void
    private var timer: Timer?
    
    init(callback: @escaping (DiskState) -> Void) {
        self.callback = callback
    }
    
    func startMonitoring() {
        updateDiskSpace()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.updateDiskSpace()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateDiskSpace() {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            callback(.unknown)
            return
        }
        
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            if let available = values.volumeAvailableCapacity,
               let total = values.volumeTotalCapacity {
                let percentage = Double(available) / Double(total) * 100
                if percentage < 10 {
                    callback(.low(available))
                } else {
                    callback(.normal(available))
                }
            } else {
                callback(.unknown)
            }
        } catch {
            callback(.unknown)
        }
    }
}

// MARK: - CPU Monitor

class CPUMonitor {
    private var callback: (CPUState) -> Void
    private var timer: Timer?
    
    init(callback: @escaping (CPUState) -> Void) {
        self.callback = callback
    }
    
    func startMonitoring() {
        updateCPUUsage()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateCPUUsage()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateCPUUsage() {
        var kr: kern_return_t
        var task_info_count: mach_msg_type_number_t
        
        task_info_count = mach_msg_type_number_t(TASK_INFO_MAX)
        var tinfo = [integer_t](repeating: 0, count: Int(task_info_count))
        
        kr = task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), &tinfo, &task_info_count)
        guard kr == KERN_SUCCESS else {
            callback(.unknown)
            return
        }
        
        var thread_list: thread_act_array_t?
        var thread_count: mach_msg_type_number_t = 0
        
        kr = task_threads(mach_task_self_, &thread_list, &thread_count)
        guard kr == KERN_SUCCESS else {
            callback(.unknown)
            return
        }
        
        var total_cpu: Float = 0
        
        for i in 0..<Int(thread_count) {
            var thread_info_count = mach_msg_type_number_t(THREAD_INFO_MAX)
            var thinfo = [integer_t](repeating: 0, count: Int(thread_info_count))
            
            kr = thread_info(thread_list![i], thread_flavor_t(THREAD_BASIC_INFO),
                           &thinfo, &thread_info_count)
            
            guard kr == KERN_SUCCESS else {
                continue
            }
            
            let threadBasicInfo = convertToThreadBasicInfo(thinfo)
            total_cpu += Float(threadBasicInfo.cpu_usage) / Float(TH_USAGE_SCALE)
        }
        
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: thread_list)),
                     vm_size_t(Int(thread_count) * MemoryLayout<thread_t>.stride))
        
        let usage = total_cpu * 100
        if usage > 80 {
            callback(.high(usage))
        } else {
            callback(.normal(usage))
        }
    }
    
    private func convertToThreadBasicInfo(_ data: [integer_t]) -> thread_basic_info {
        return withUnsafeBytes(of: data) { pointer in
            pointer.load(as: thread_basic_info.self)
        }
    }
}

// MARK: - State Enums

enum PowerState: Equatable {
    case charging(Int)  // Percentage
    case battery(Int)   // Percentage
    case unknown
}

enum NetworkState: Equatable {
    case wifi
    case cellular
    case wired
    case disconnected
    case unknown
}

enum DiskState: Equatable {
    case normal(Int64)  // Available bytes
    case low(Int64)     // Available bytes
    case unknown
}

enum CPUState: Equatable {
    case normal(Float)  // Usage percentage
    case high(Float)    // Usage percentage
    case unknown
}

// MARK: - Backup Conditions

struct BackupCondition {
    var issues: [BackupIssue] = []
    
    var canProceed: Bool {
        issues.allSatisfy { !$0.isCritical }
    }
    
    var recommendations: [String] {
        issues.map { $0.recommendation }
    }
}

enum BackupIssue {
    case lowBattery(Int)
    case noNetwork
    case cellularNetwork
    case lowDiskSpace(Int64)
    case highCPUUsage(Float)
    case unknownPowerState
    case unknownNetworkState
    case unknownDiskState
    case unknownCPUState
    
    var isCritical: Bool {
        switch self {
        case .lowBattery, .noNetwork, .lowDiskSpace:
            return true
        case .cellularNetwork, .highCPUUsage, .unknownPowerState,
             .unknownNetworkState, .unknownDiskState, .unknownCPUState:
            return false
        }
    }
    
    var recommendation: String {
        switch self {
        case .lowBattery(let percentage):
            return "Battery is low (\(percentage)%). Connect to power source."
        case .noNetwork:
            return "No network connection available."
        case .cellularNetwork:
            return "Connected to cellular network. Consider switching to Wi-Fi."
        case .lowDiskSpace(let bytes):
            let formatter = ByteCountFormatter()
            return "Low disk space (\(formatter.string(fromByteCount: bytes)) available)."
        case .highCPUUsage(let usage):
            return String(format: "High CPU usage (%.1f%%). Consider waiting.", usage)
        case .unknownPowerState:
            return "Unable to determine power state."
        case .unknownNetworkState:
            return "Unable to determine network state."
        case .unknownDiskState:
            return "Unable to determine disk space."
        case .unknownCPUState:
            return "Unable to determine CPU usage."
        }
    }
}
