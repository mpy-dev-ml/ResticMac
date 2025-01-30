import Foundation

struct SnapshotProgress: Codable {
    let messageType: String
    let percentDone: Double
    let totalFiles: Int
    let totalBytes: UInt64
    let currentFiles: Int
    let currentBytes: UInt64
    let currentFile: String?
    
    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case percentDone = "percent_done"
        case totalFiles = "total_files"
        case totalBytes = "total_bytes"
        case currentFiles = "files_done"
        case currentBytes = "bytes_done"
        case currentFile = "current_file"
    }
    
    init(messageType: String = "status",
         percentDone: Double = 0.0,
         totalFiles: Int = 0,
         totalBytes: UInt64 = 0,
         currentFiles: Int = 0,
         currentBytes: UInt64 = 0,
         currentFile: String? = nil) {
        self.messageType = messageType
        self.percentDone = percentDone
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.currentFiles = currentFiles
        self.currentBytes = currentBytes
        self.currentFile = currentFile
    }
}

struct RestoreProgress: Codable {
    let messageType: String
    let percentDone: Double
    let totalFiles: Int
    let totalBytes: UInt64
    let restoredFiles: Int
    let restoredBytes: UInt64
    let currentFile: String?
    
    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case percentDone = "percent_done"
        case totalFiles = "total_files"
        case totalBytes = "total_bytes"
        case restoredFiles = "restored_files"
        case restoredBytes = "restored_bytes"
        case currentFile = "current_file"
    }
    
    init(messageType: String = "status",
         percentDone: Double = 0.0,
         totalFiles: Int = 0,
         totalBytes: UInt64 = 0,
         restoredFiles: Int = 0,
         restoredBytes: UInt64 = 0,
         currentFile: String? = nil) {
        self.messageType = messageType
        self.percentDone = percentDone
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.restoredFiles = restoredFiles
        self.restoredBytes = restoredBytes
        self.currentFile = currentFile
    }
}
