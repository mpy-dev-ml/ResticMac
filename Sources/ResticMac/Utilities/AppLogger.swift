import Foundation
import os

enum LogCategory {
    case app
    case network
    case ui
    case process
    
    var logger: Logger {
        switch self {
        case .app:
            return Logger(subsystem: "com.resticmac", category: "app")
        case .network:
            return Logger(subsystem: "com.resticmac", category: "network")
        case .ui:
            return Logger(subsystem: "com.resticmac", category: "ui")
        case .process:
            return Logger(subsystem: "com.resticmac", category: "process")
        }
    }
}

enum AppLogger {
    static func debug(_ message: String, category: LogCategory = .app) {
        category.logger.debug("\(message, privacy: .public)")
    }
    
    static func info(_ message: String, category: LogCategory = .app) {
        category.logger.info("\(message, privacy: .public)")
    }
    
    static func error(_ message: String, category: LogCategory = .app) {
        category.logger.error("\(message, privacy: .public)")
    }
    
    static func warning(_ message: String, category: LogCategory = .app) {
        category.logger.warning("\(message, privacy: .public)")
    }
}
