import Foundation
import os.log

actor MountService {
    private let logger = Logger(subsystem: "com.resticmac", category: "MountService")
    private let resticService: ResticService
    private var activeMounts: [String: MountPoint] = [:]
    
    init(resticService: ResticService) {
        self.resticService = resticService
    }
    
    struct MountPoint: Identifiable {
        let id: String
        let repository: Repository
        let snapshot: String?
        let path: URL
        let process: Process
        let startTime: Date
        
        var isSnapshotMount: Bool {
            snapshot != nil
        }
    }
    
    enum MountError: LocalizedError {
        case mountPointInUse(URL)
        case mountFailed(String)
        case unmountFailed(String)
        case mountPointNotFound(URL)
        case resticNotInstalled
        case fuseMissing
        
        var errorDescription: String? {
            switch self {
            case .mountPointInUse(let url):
                return "Mount point is already in use: \(url.path)"
            case .mountFailed(let reason):
                return "Failed to mount repository: \(reason)"
            case .unmountFailed(let reason):
                return "Failed to unmount repository: \(reason)"
            case .mountPointNotFound(let url):
                return "Mount point not found: \(url.path)"
            case .resticNotInstalled:
                return "Restic is not installed"
            case .fuseMissing:
                return "FUSE is not installed"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .mountPointInUse:
                return "Choose a different mount point or unmount the existing one"
            case .mountFailed:
                return "Check repository access and try again"
            case .unmountFailed:
                return "Try force unmounting or restart your computer"
            case .mountPointNotFound:
                return "Verify the mount point path exists"
            case .resticNotInstalled:
                return "Install Restic using Homebrew: brew install restic"
            case .fuseMissing:
                return "Install macFUSE from https://osxfuse.github.io"
            }
        }
    }
    
    func mountRepository(_ repository: Repository, at mountPoint: URL, snapshot: String? = nil) async throws -> MountPoint {
        // Check if FUSE is installed
        guard FileManager.default.fileExists(atPath: "/usr/local/lib/libfuse.dylib") else {
            throw MountError.fuseMissing
        }
        
        // Check if mount point is already in use
        if activeMounts.values.contains(where: { $0.path == mountPoint }) {
            throw MountError.mountPointInUse(mountPoint)
        }
        
        // Create mount point directory if it doesn't exist
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        
        // Prepare mount command
        var arguments = ["mount"]
        if let snapshot = snapshot {
            arguments.append("--snapshot")
            arguments.append(snapshot)
        }
        arguments.append(mountPoint.path)
        
        let command = ResticCommand(
            repository: repository.path,
            arguments: arguments
        )
        
        do {
            let process = try await resticService.startLongRunningCommand(command)
            
            // Wait a bit to ensure mount is successful
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            guard process.isRunning else {
                throw MountError.mountFailed("Mount process terminated unexpectedly")
            }
            
            let mountPoint = MountPoint(
                id: UUID().uuidString,
                repository: repository,
                snapshot: snapshot,
                path: mountPoint,
                process: process,
                startTime: Date()
            )
            
            activeMounts[mountPoint.id] = mountPoint
            
            logger.info("Successfully mounted repository at \(mountPoint.path.path, privacy: .public)")
            return mountPoint
            
        } catch {
            // Clean up mount point if it was created
            try? FileManager.default.removeItem(at: mountPoint)
            
            if let resticError = error as? ResticError {
                throw MountError.mountFailed(resticError.localizedDescription)
            }
            throw MountError.mountFailed(error.localizedDescription)
        }
    }
    
    func unmountRepository(at mountPoint: URL) async throws {
        guard let mount = activeMounts.values.first(where: { $0.path == mountPoint }) else {
            throw MountError.mountPointNotFound(mountPoint)
        }
        
        // First try graceful unmount
        do {
            mount.process.terminate()
            
            // Wait for process to terminate
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            if mount.process.isRunning {
                // If still running, try force unmount
                let unmountProcess = Process()
                unmountProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                unmountProcess.arguments = ["unmount", "force", mountPoint.path]
                
                try unmountProcess.run()
                unmountProcess.waitUntilExit()
                
                if unmountProcess.terminationStatus != 0 {
                    throw MountError.unmountFailed("Force unmount failed")
                }
            }
            
            // Clean up mount point
            try? FileManager.default.removeItem(at: mountPoint)
            
            activeMounts.removeValue(forKey: mount.id)
            logger.info("Successfully unmounted repository from \(mountPoint.path, privacy: .public)")
            
        } catch {
            throw MountError.unmountFailed(error.localizedDescription)
        }
    }
    
    func unmountAll() async {
        for mount in activeMounts.values {
            do {
                try await unmountRepository(at: mount.path)
            } catch {
                logger.error("Failed to unmount repository at \(mount.path.path): \(error.localizedDescription)")
            }
        }
    }
    
    func getActiveMounts() -> [MountPoint] {
        Array(activeMounts.values)
    }
    
    func getMountPoint(for id: String) -> MountPoint? {
        activeMounts[id]
    }
    
    func isValidMountPoint(_ url: URL) -> Bool {
        // Check if directory exists and is writable
        guard let resources = try? url.resourceValues(forKeys: [.isDirectoryKey, .isWritableKey]),
              let isDirectory = resources.isDirectory,
              let isWritable = resources.isWritable else {
            return false
        }
        
        return isDirectory && isWritable
    }
    
    deinit {
        // Ensure all mounts are cleaned up
        Task {
            await unmountAll()
        }
    }
}

// MARK: - ResticService Extensions

extension ResticService {
    func startLongRunningCommand(_ command: ResticCommand) throws -> Process {
        let process = Process()
        process.executableURL = resticPath
        
        var arguments = command.arguments
        if let repo = command.repository {
            arguments.insert(contentsOf: ["-r", repo], at: 0)
        }
        process.arguments = arguments
        
        if let env = command.environment {
            process.environment = env
        }
        
        // Set up pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Start process
        try process.run()
        
        return process
    }
}
