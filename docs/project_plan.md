# ResticMac - macOS Restic Client Project Plan

## Overview
ResticMac is a native macOS client for the Restic backup utility, focusing on providing a user-friendly GUI wrapper around Restic's command-line functionality. The app executes Restic commands in the background while displaying them to users for transparency.

Core features:
1. Repository initialization
2. Snapshot creation
3. Daily backup scheduling
4. Command execution display and monitoring

## Project Structure

```
ResticMac/
├── Sources/
│   └── ResticMac/
│       ├── App/
│       │   ├── ResticMacApp.swift
│       │   └── AppDelegate.swift
│       ├── Services/
│       │   ├── ResticService/
│       │   │   ├── ResticService.swift          # Core restic operations
│       │   │   ├── ResticCommand.swift          # Command structures
│       │   │   └── ResticError.swift            # Error definitions
│       │   ├── SchedulerService/
│       │   │   ├── SchedulerService.swift        # Daily scheduling
│       │   │   └── SchedulerError.swift          # Scheduler errors
│       │   ├── AsyncCommandExecutor/
│       │   │   ├── AsyncCommandExecutor.swift    # Background command execution
│       │   │   └── CommandResult.swift           # Command result
│       │   └── CommandDisplayManager/
│       │       ├── CommandDisplayManager.swift    # Command display
│       │       └── CommandFormatter.swift        # Command formatting
│       ├── Models/
│       │   ├── Repository.swift                  # Repository model
│       │   ├── Snapshot.swift                    # Snapshot model
│       │   └── Schedule.swift                    # Schedule model
│       ├── Views/
│       │   ├── Main/
│       │   │   ├── MainView.swift               # Tab container
│       │   │   └── ComingSoonView.swift         # Placeholder
│       │   ├── Repository/
│       │   │   ├── RepositoryView.swift         # Repository tab
│       │   │   └── RepositoryForm.swift         # Creation form
│       │   ├── Backup/
│       │   │   ├── BackupView.swift             # Backup tab
│       │   │   └── PathSelector.swift           # Path selection
│       │   ├── Schedule/
│       │   │   ├── ScheduleView.swift           # Schedule tab
│       │   │   └── TimeSelector.swift           # Time picker
│       │   └── CommandDisplay/
│       │       ├── CommandDisplayView.swift     # Command display window
│       │       └── CommandOutputView.swift      # Command output
│       └── Utilities/
│           ├── ProcessExecutor.swift             # Command execution
│           └── Logger.swift                      # Basic logging
└── Package.swift
```

## Development Timeline

| Day | Category | Task | Est. Hours | Details |
|-----|----------|------|------------|----------|
| **Day 1 - Foundation** |
| | Setup | Create Xcode project | 0.5 | Initialize SwiftUI project |
| | | Configure SwiftPackage | 0.5 | Set up package structure |
| | Core | ProcessExecutor | 2 | Command execution utility |
| | | ResticCommand | 2 | Command structure |
| | | ResticService base | 3 | Basic service setup |
| **Day 2 - Repository** |
| | Service | Repository init | 2 | Implementation |
| | | Error handling | 2 | Basic error types |
| | UI | MainView tabs | 1 | Tab structure |
| | | RepositoryForm | 3 | Creation form |
| **Day 3 - Backup** |
| | Service | Snapshot creation | 3 | Implementation |
| | | Progress handling | 2 | Basic progress |
| | UI | BackupView | 2 | Backup interface |
| | | PathSelector | 1 | Path selection |
| **Day 4 - Scheduling** |
| | Service | SchedulerService | 3 | Basic scheduler |
| | | Background tasks | 2 | Task handling |
| | UI | ScheduleView | 2 | Schedule interface |
| | | TimeSelector | 1 | Time selection |
| **Day 5 - Command Display** |
| | Service | AsyncCommandExecutor | 3 | Background command execution |
| | | CommandDisplayManager | 2 | Command display |
| | UI | CommandDisplayView | 2 | Command display window |
| | | CommandOutputView | 1 | Command output |
| **Day 6 - Polish** |
| | UI | Error messages | 2 | User feedback |
| | | Progress indicators | 2 | Status display |
| | | ComingSoonView | 2 | Placeholders |
| | Testing | Core workflow | 2 | Basic testing |
| **Day 7 - Testing** |
| | Testing | Repository tests | 3 | Creation testing |
| | | Backup tests | 3 | Snapshot testing |
| | | Schedule tests | 2 | Scheduler testing |
| | | Command display tests | 2 | Command display testing |
| **Day 8 - Finalization** |
| | Polish | Bug fixes | 4 | Known issues |
| | | UI refinements | 2 | Visual polish |
| | | Documentation | 2 | Basic docs |

## Core Feature Details

### 1. Repository Management
```swift
// ResticService.swift
func initializeRepository(at path: URL, password: String) async throws -> Repository {
    // Validate path
    // Execute restic init command
    // Save password securely
    // Return repository info
}
```

### 2. Snapshot Creation
```swift
// ResticService.swift
func createSnapshot(repo: Repository, paths: [URL]) async throws -> Snapshot {
    // Validate paths
    // Execute restic backup command
    // Monitor progress
    // Return snapshot info
}
```

### 3. Daily Scheduling
```swift
// SchedulerService.swift
func scheduleDaily(repository: Repository, at time: Date) throws {
    // Validate time
    // Create background task
    // Save schedule
    // Enable monitoring
}
```

### 4. Command Display and Execution
```swift
// AsyncCommandExecutor.swift
func executeCommand(_ command: ResticCommand) async throws -> CommandResult {
    // Execute command asynchronously
    // Stream output to UI
    // Monitor progress
    // Return result
}

// CommandDisplayManager.swift
func displayCommand(_ command: ResticCommand) {
    // Format command for display
    // Show in UI
    // Update with real-time output
}
```

## Coming Soon Features

1. Repository Features:
   - Repository health check
   - Password change
   - Repository cleanup

2. Backup Features:
   - Browse snapshots
   - Restore files
   - Backup tags
   - Exclude patterns

3. Advanced Features:
   - Cloud storage
   - Touch ID
   - Advanced scheduling
   - Statistics

## Implementation Guidelines

1. Core Services:
   - Async/await for operations
   - Background command execution
   - Real-time output streaming
   - Basic logging

2. UI Components:
   - SwiftUI views
   - Command display window
   - Progress indicators
   - Output formatting

3. Data Flow:
   - Service-based architecture
   - Simple state management
   - Basic persistence
   - Error propagation

4. Testing Strategy:
   - Core workflow testing
   - Basic error cases
   - Schedule verification
   - UI interaction tests

## Success Criteria

1. Must Work:
   - Repository creation
   - Snapshot creation
   - Daily scheduling
   - Background command execution
   - Command display and monitoring

2. Should Have:
   - Clear progress indication
   - Basic error handling
   - Simple status reporting

3. Nice to Have:
   - Password storage
   - Multiple repositories
   - Schedule modification
