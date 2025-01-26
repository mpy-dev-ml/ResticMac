import Foundation

enum Constants {
    // Environment Variables
    enum Environment {
        static let resticPassword = "RESTIC_PASSWORD"
        static let resticRepository = "RESTIC_REPOSITORY"
        static let resticPasswordFile = "RESTIC_PASSWORD_FILE"
        static let resticCacheDir = "RESTIC_CACHE_DIR"
        static let resticCompression = "RESTIC_COMPRESSION"
        static let resticPackSize = "RESTIC_PACK_SIZE"
    }
    
    // Command Names
    enum Commands {
        static let restic = "restic"
        static let find = "find"
    }
    
    // Logger Names
    enum Loggers {
        static let resticService = "com.resticmac.ResticService"
        static let processExecutor = "com.resticmac.ProcessExecutor"
    }
    
    // Exit Codes
    enum ExitCodes {
        static let success = 0
        static let generalError = 1
        static let incompleteBackup = 3
        static let repositoryNotExist = 10
        static let repositoryLocked = 11
        static let wrongPassword = 12
    }
    
    // Common Command Arguments
    enum Arguments {
        static let json = "--json"
        static let quiet = "--quiet"
        static let verbose = "--verbose"
        static let dryRun = "--dry-run"
        static let tag = "--tag"
    }
    
    // Process Configuration
    enum Process {
        static let outputBufferSize = 4096
        static let defaultEncoding = String.Encoding.utf8
    }
}