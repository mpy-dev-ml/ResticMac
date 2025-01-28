import Foundation
import Logging

@globalActor
public actor AppLoggerActor {
    public static let shared = AppLoggerActor()
}

final class AppLogger: @unchecked Sendable {
    @AppLoggerActor
    static let shared = AppLogger()
    
    private let logger: Logger
    
    private init() {
        logger = Logger(label: "com.resticmac.app")
    }
    
    @AppLoggerActor
    func debug(_ message: String) async {
        logger.debug("\(message)")
    }
    
    @AppLoggerActor
    func info(_ message: String) async {
        logger.info("\(message)")
    }
    
    @AppLoggerActor
    func warning(_ message: String) async {
        logger.warning("\(message)")
    }
    
    @AppLoggerActor
    func error(_ message: String) async {
        logger.error("\(message)")
    }
}
