import Foundation
import OSLog
import Compression

actor CloudAnalyticsCompression {
    private let logger = Logger(subsystem: "com.resticmac", category: "CloudAnalyticsCompression")
    private let persistence: CloudAnalyticsPersistence
    private let monitor: CloudAnalyticsMonitor
    
    init(persistence: CloudAnalyticsPersistence, monitor: CloudAnalyticsMonitor) {
        self.persistence = persistence
        self.monitor = monitor
    }
    
    // MARK: - Compression Management
    
    func compressMetrics(
        for repository: Repository,
        timeRange: DateInterval? = nil,
        algorithm: CompressionAlgorithm = .lzfse
    ) async throws -> CompressionReport {
        let tracker = await monitor.trackOperation("compress_metrics")
        defer { tracker.stop() }
        
        do {
            // Gather metrics for compression
            let metrics = try await gatherMetrics(for: repository, timeRange: timeRange)
            
            // Compress each metric type
            let storageCompression = try await compressStorageMetrics(
                metrics.storageHistory,
                algorithm: algorithm
            )
            
            let transferCompression = try await compressTransferMetrics(
                metrics.transferHistory,
                algorithm: algorithm
            )
            
            let costCompression = try await compressCostMetrics(
                metrics.costHistory,
                algorithm: algorithm
            )
            
            // Generate report
            let report = CompressionReport(
                repository: repository,
                timeRange: timeRange,
                storageCompression: storageCompression,
                transferCompression: transferCompression,
                costCompression: costCompression,
                timestamp: Date()
            )
            
            logger.info("Completed metrics compression for repository: \(repository.id)")
            return report
            
        } catch {
            logger.error("Metrics compression failed: \(error.localizedDescription)")
            throw CompressionError.compressionFailed(error: error)
        }
    }
    
    // MARK: - Storage Compression
    
    private func compressStorageMetrics(
        _ metrics: [TimeSeriesPoint<StorageMetrics>],
        algorithm: CompressionAlgorithm
    ) async throws -> CompressionResult {
        let originalSize = MemoryLayout<StorageMetrics>.size * metrics.count
        
        // Prepare data for compression
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metrics)
        
        // Compress data
        let compressedData = try compressData(data, algorithm: algorithm)
        
        return CompressionResult(
            metricType: "Storage",
            originalSize: originalSize,
            compressedSize: compressedData.count,
            algorithm: algorithm,
            compressionRatio: Double(compressedData.count) / Double(originalSize)
        )
    }
    
    // MARK: - Transfer Compression
    
    private func compressTransferMetrics(
        _ metrics: [TimeSeriesPoint<TransferMetrics>],
        algorithm: CompressionAlgorithm
    ) async throws -> CompressionResult {
        let originalSize = MemoryLayout<TransferMetrics>.size * metrics.count
        
        // Prepare data for compression
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metrics)
        
        // Compress data
        let compressedData = try compressData(data, algorithm: algorithm)
        
        return CompressionResult(
            metricType: "Transfer",
            originalSize: originalSize,
            compressedSize: compressedData.count,
            algorithm: algorithm,
            compressionRatio: Double(compressedData.count) / Double(originalSize)
        )
    }
    
    // MARK: - Cost Compression
    
    private func compressCostMetrics(
        _ metrics: [TimeSeriesPoint<CostMetrics>],
        algorithm: CompressionAlgorithm
    ) async throws -> CompressionResult {
        let originalSize = MemoryLayout<CostMetrics>.size * metrics.count
        
        // Prepare data for compression
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metrics)
        
        // Compress data
        let compressedData = try compressData(data, algorithm: algorithm)
        
        return CompressionResult(
            metricType: "Cost",
            originalSize: originalSize,
            compressedSize: compressedData.count,
            algorithm: algorithm,
            compressionRatio: Double(compressedData.count) / Double(originalSize)
        )
    }
    
    // MARK: - Compression Utilities
    
    private func compressData(_ data: Data, algorithm: CompressionAlgorithm) throws -> Data {
        let destinationBufferSize = data.count
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }
        
        let compressedSize = data.withUnsafeBytes { sourceBuffer in
            compression_encode_buffer(
                destinationBuffer,
                destinationBufferSize,
                sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                algorithm.compressionAlgorithm
            )
        }
        
        guard compressedSize > 0 else {
            throw CompressionError.compressionFailed(error: NSError(domain: "Compression", code: -1))
        }
        
        return Data(bytes: destinationBuffer, count: compressedSize)
    }
    
    private func decompressData(_ data: Data, algorithm: CompressionAlgorithm) throws -> Data {
        let destinationBufferSize = data.count * 4 // Estimate decompressed size
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }
        
        let decompressedSize = data.withUnsafeBytes { sourceBuffer in
            compression_decode_buffer(
                destinationBuffer,
                destinationBufferSize,
                sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                algorithm.compressionAlgorithm
            )
        }
        
        guard decompressedSize > 0 else {
            throw CompressionError.decompressionFailed(error: NSError(domain: "Compression", code: -1))
        }
        
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
    
    // MARK: - Delta Compression
    
    private func deltaCompress<T: Numeric>(_ values: [T]) -> [T] {
        guard !values.isEmpty else { return [] }
        
        var deltas: [T] = [values[0]] // Keep first value as reference
        var previous = values[0]
        
        for i in 1..<values.count {
            let delta = values[i] - previous
            deltas.append(delta)
            previous = values[i]
        }
        
        return deltas
    }
    
    private func deltaDecompress<T: Numeric>(_ deltas: [T]) -> [T] {
        guard !deltas.isEmpty else { return [] }
        
        var values: [T] = [deltas[0]] // First value is the reference
        var current = deltas[0]
        
        for i in 1..<deltas.count {
            current = current + deltas[i]
            values.append(current)
        }
        
        return values
    }
    
    // MARK: - Helper Methods
    
    private func gatherMetrics(
        for repository: Repository,
        timeRange: DateInterval?
    ) async throws -> AnalyticsMetrics {
        let storageHistory = try await persistence.getStorageMetricsHistory(for: repository)
        let transferHistory = try await persistence.getTransferMetricsHistory(for: repository)
        let costHistory = try await persistence.getCostMetricsHistory(for: repository)
        
        // Filter by time range if specified
        let filteredStorage = timeRange.map { range in
            storageHistory.filter { range.contains($0.timestamp) }
        } ?? storageHistory
        
        let filteredTransfer = timeRange.map { range in
            transferHistory.filter { range.contains($0.timestamp) }
        } ?? transferHistory
        
        let filteredCost = timeRange.map { range in
            costHistory.filter { range.contains($0.timestamp) }
        } ?? costHistory
        
        return AnalyticsMetrics(
            storageHistory: filteredStorage,
            transferHistory: filteredTransfer,
            costHistory: filteredCost
        )
    }
}

// MARK: - Supporting Types

enum CompressionAlgorithm {
    case lzfse
    case lz4
    case lzma
    case zlib
    
    var compressionAlgorithm: compression_algorithm {
        switch self {
        case .lzfse: return COMPRESSION_LZFSE
        case .lz4: return COMPRESSION_LZ4
        case .lzma: return COMPRESSION_LZMA
        case .zlib: return COMPRESSION_ZLIB
        }
    }
}

struct CompressionReport: Codable {
    let repository: Repository
    let timeRange: DateInterval?
    let storageCompression: CompressionResult
    let transferCompression: CompressionResult
    let costCompression: CompressionResult
    let timestamp: Date
    
    var totalCompressionRatio: Double {
        let totalOriginal = storageCompression.originalSize +
                          transferCompression.originalSize +
                          costCompression.originalSize
        
        let totalCompressed = storageCompression.compressedSize +
                            transferCompression.compressedSize +
                            costCompression.compressedSize
        
        return Double(totalCompressed) / Double(totalOriginal)
    }
}

struct CompressionResult: Codable {
    let metricType: String
    let originalSize: Int
    let compressedSize: Int
    let algorithm: CompressionAlgorithm
    let compressionRatio: Double
}

enum CompressionError: Error {
    case compressionFailed(error: Error)
    case decompressionFailed(error: Error)
    case invalidData
    case insufficientMemory
}

// MARK: - Codable Extensions

extension CompressionAlgorithm: Codable {
    enum CodingKeys: String, CodingKey {
        case rawValue
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rawValue, forKey: .rawValue)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .rawValue)
        switch rawValue {
        case "lzfse": self = .lzfse
        case "lz4": self = .lz4
        case "lzma": self = .lzma
        case "zlib": self = .zlib
        default: throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: container.codingPath,
            debugDescription: "Invalid compression algorithm"
        ))
        }
    }
    
    var rawValue: String {
        switch self {
        case .lzfse: return "lzfse"
        case .lz4: return "lz4"
        case .lzma: return "lzma"
        case .zlib: return "zlib"
        }
    }
}
