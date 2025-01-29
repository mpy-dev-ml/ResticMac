import Foundation

actor CloudAnalyticsCache {
    private var cache: [UUID: CacheEntry] = [:]
    private let maxEntries: Int
    private let expirationInterval: TimeInterval
    
    init(maxEntries: Int = 1000, expirationInterval: TimeInterval = 3600) {
        self.maxEntries = maxEntries
        self.expirationInterval = expirationInterval
    }
    
    func cacheResult(
        _ result: FilterResult,
        for chainId: UUID,
        data: AnalyticsData
    ) {
        // Remove expired entries
        removeExpiredEntries()
        
        // Remove oldest entries if cache is full
        if cache.count >= maxEntries {
            removeOldestEntries()
        }
        
        // Add new entry
        cache[chainId] = CacheEntry(
            result: result,
            data: data,
            timestamp: Date()
        )
    }
    
    func getCachedResult(
        for chainId: UUID,
        data: AnalyticsData
    ) -> FilterResult? {
        guard let entry = cache[chainId],
              !isExpired(entry),
              isDataEqual(entry.data, data) else {
            return nil
        }
        return entry.result
    }
    
    func clearCachedResults(for chainId: UUID) {
        cache[chainId] = nil
    }
    
    func clearAllCachedResults() {
        cache.removeAll()
    }
    
    private func removeExpiredEntries() {
        let now = Date()
        cache = cache.filter { !isExpired($0.value, relativeTo: now) }
    }
    
    private func removeOldestEntries() {
        while cache.count >= maxEntries {
            guard let oldestEntry = cache.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
                break
            }
            cache.removeValue(forKey: oldestEntry.key)
        }
    }
    
    private func isExpired(_ entry: CacheEntry, relativeTo date: Date = Date()) -> Bool {
        date.timeIntervalSince(entry.timestamp) > expirationInterval
    }
    
    private func isDataEqual(_ data1: AnalyticsData, _ data2: AnalyticsData) -> Bool {
        // Compare relevant fields for cache invalidation
        return data1.storageMetrics == data2.storageMetrics &&
               data1.transferMetrics == data2.transferMetrics &&
               data1.costMetrics == data2.costMetrics &&
               data1.snapshotMetrics == data2.snapshotMetrics
    }
}

private struct CacheEntry {
    let result: FilterResult
    let data: AnalyticsData
    let timestamp: Date
}
