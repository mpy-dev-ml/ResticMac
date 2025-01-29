import Foundation

struct SnapshotProgress: Codable {
    let totalFiles: Int
    let processedFiles: Int
    let totalBytes: Int64
    let processedBytes: Int64
    let currentFile: String?
    
    init(output: String) {
        self.totalFiles = 0
        self.processedFiles = 0
        self.totalBytes = 0
        self.processedBytes = 0
        self.currentFile = nil
    }
    
    init(totalFiles: Int, processedFiles: Int, totalBytes: Int64, processedBytes: Int64, currentFile: String?) {
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.currentFile = currentFile
    }
}

struct RestoreProgress: Codable {
    let totalFiles: Int
    let processedFiles: Int
    let totalBytes: Int64
    let processedBytes: Int64
    let currentFile: String?
    
    init(output: String) {
        self.totalFiles = 0
        self.processedFiles = 0
        self.totalBytes = 0
        self.processedBytes = 0
        self.currentFile = nil
    }
    
    init(totalFiles: Int, processedFiles: Int, totalBytes: Int64, processedBytes: Int64, currentFile: String?) {
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.currentFile = currentFile
    }
}
