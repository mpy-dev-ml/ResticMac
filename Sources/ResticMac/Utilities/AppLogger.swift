import Foundation
import Logging

@MainActor
final class AppLogger: Sendable {
    static let shared = AppLogger()
    private let logger: Logger
    
    private init() {
        self.logger = Logger(label: "com.resticmac.app")
    }
    
    nonisolated func debug(_ message: String) {
        Task { @MainActor in
            logger.debug("\(message)")
        }
    }
    
    nonisolated func info(_ message: String) {
        Task { @MainActor in
            logger.info("\(message)")
        }
    }
    
    nonisolated func warning(_ message: String) {
        Task { @MainActor in
            logger.warning("\(message)")
        }
    }
    
    nonisolated func error(_ message: String) {
        Task { @MainActor in
            logger.error("\(message)")
        }
    }
}
