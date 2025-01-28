import Foundation
import Logging
import os

@globalActor
actor AppLoggerActor {
    static let shared = AppLoggerActor()
}

@AppLoggerActor
final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()
    private let logger: Logger
    private let osLog: OSLog
    
    private init() {
        self.logger = Logger(label: "com.resticmac.app")
        self.osLog = OSLog(subsystem: "com.resticmac.app", category: "default")
    }
    
    // Type-safe logging methods with metadata support
    nonisolated func debug<T: Sendable>(
        _ message: String,
        metadata: T? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) where T: Encodable {
        Task { @AppLoggerActor in
            var logMetadata: Logger.Metadata = [
                "file": "\(file)",
                "function": "\(function)",
                "line": "\(line)"
            ] as [String: Logger.MetadataValue]
            
            if let metadata = metadata {
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(metadata)
                    if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        dict.forEach { logMetadata[$0.key] = .string("\($0.value)") }
                    }
                } catch {
                    logMetadata["metadata_error"] = .string("Failed to encode metadata: \(error)")
                }
            }
            
            logger.debug(
                "\(message)",
                metadata: logMetadata
            )
        }
    }
    
    nonisolated func info<T: Sendable>(
        _ message: String,
        metadata: T? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) where T: Encodable {
        Task { @AppLoggerActor in
            var logMetadata: Logger.Metadata = [
                "file": "\(file)",
                "function": "\(function)",
                "line": "\(line)"
            ] as [String: Logger.MetadataValue]
            
            if let metadata = metadata {
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(metadata)
                    if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        dict.forEach { logMetadata[$0.key] = .string("\($0.value)") }
                    }
                } catch {
                    logMetadata["metadata_error"] = .string("Failed to encode metadata: \(error)")
                }
            }
            
            logger.info(
                "\(message)",
                metadata: logMetadata
            )
        }
    }
    
    nonisolated func warning<T: Sendable>(
        _ message: String,
        metadata: T? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) where T: Encodable {
        Task { @AppLoggerActor in
            var logMetadata: Logger.Metadata = [
                "file": "\(file)",
                "function": "\(function)",
                "line": "\(line)"
            ] as [String: Logger.MetadataValue]
            
            if let metadata = metadata {
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(metadata)
                    if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        dict.forEach { logMetadata[$0.key] = .string("\($0.value)") }
                    }
                } catch {
                    logMetadata["metadata_error"] = .string("Failed to encode metadata: \(error)")
                }
            }
            
            logger.warning(
                "\(message)",
                metadata: logMetadata
            )
        }
    }
    
    nonisolated func error<T: Sendable>(
        _ message: String,
        metadata: T? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) where T: Encodable {
        Task { @AppLoggerActor in
            var logMetadata: Logger.Metadata = [
                "file": "\(file)",
                "function": "\(function)",
                "line": "\(line)"
            ] as [String: Logger.MetadataValue]
            
            if let metadata = metadata {
                do {
                    let encoder = JSONEncoder()
                    let data = try encoder.encode(metadata)
                    if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        dict.forEach { logMetadata[$0.key] = .string("\($0.value)") }
                    }
                } catch {
                    logMetadata["metadata_error"] = .string("Failed to encode metadata: \(error)")
                }
            }
            
            logger.error(
                "\(message)",
                metadata: logMetadata
            )
        }
    }
    
    // Signpost support for performance monitoring
    nonisolated func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.begin, log: osLog, name: name, signpostID: id)
    }
    
    nonisolated func endInterval(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.end, log: osLog, name: name, signpostID: id)
    }
}
