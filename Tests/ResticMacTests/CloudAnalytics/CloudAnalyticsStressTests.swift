import XCTest
@testable import ResticMac

final class CloudAnalyticsStressTests: XCTestCase {
    var analytics: CloudAnalytics!
    var persistence: CloudAnalyticsPersistence!
    var testDataDirectory: URL!
    var repositories: [Repository] = []
    
    override func setUp() async throws {
        testDataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ResticMacStressTests")
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
        
        persistence = CloudAnalyticsPersistence(storageURL: testDataDirectory)
        analytics = CloudAnalytics(persistence: persistence)
        
        // Create multiple test repositories
        for i in 0..<10 {
            let repo = Repository(
                path: testDataDirectory.appendingPathComponent("repo-\(i)"),
                password: "test-password-\(i)",
                provider: .local
            )
            repositories.append(repo)
        }
    }
    
    override func tearDown() async throws {
        analytics = nil
        persistence = nil
        repositories.removeAll()
        
        try? FileManager.default.removeItem(at: testDataDirectory)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentRepositoryAccess() async throws {
        let expectations = repositories.map { _ in expectation(description: "Repository processed") }
        let queue = DispatchQueue(label: "com.resticmac.stresstest", attributes: .concurrent)
        
        // Process multiple repositories concurrently
        for (index, repository) in repositories.enumerated() {
            queue.async {
                Task {
                    do {
                        // Generate and process data
                        try await self.generateTestData(for: repository)
                        let metrics = try await self.analytics.getStorageMetrics(for: repository)
                        let trend = try await self.analytics.analyzeStorageTrend(for: repository)
                        
                        XCTAssertNotNil(metrics)
                        XCTAssertNotNil(trend)
                        
                        expectations[index].fulfill()
                    } catch {
                        XCTFail("Repository \(index) failed: \(error)")
                    }
                }
            }
        }
        
        await fulfillment(of: expectations, timeout: 30.0)
    }
    
    func testHighFrequencyUpdates() async throws {
        let repository = repositories[0]
        let updateCount = 1000
        let expectations = [expectation(description: "Updates completed")]
        
        // Perform rapid updates
        Task {
            do {
                for i in 0..<updateCount {
                    let metrics = StorageMetrics(
                        totalBytes: Int64(i * 1000),
                        compressedBytes: Int64(i * 800),
                        deduplicatedBytes: Int64(i * 600)
                    )
                    try await persistence.saveStorageMetrics(metrics, for: repository)
                }
                expectations[0].fulfill()
            } catch {
                XCTFail("High frequency updates failed: \(error)")
            }
        }
        
        await fulfillment(of: expectations, timeout: 30.0)
        
        // Verify data integrity
        let finalMetrics = try await analytics.getStorageMetrics(for: repository)
        XCTAssertEqual(finalMetrics.totalBytes, Int64((updateCount - 1) * 1000))
    }
    
    // MARK: - Memory Pressure Tests
    
    func testMemoryPressure() async throws {
        let repository = repositories[0]
        var largeDataSets: [Data] = []
        
        // Create memory pressure
        measure {
            for _ in 0..<100 {
                let size = 1024 * 1024 // 1MB
                let data = Data(count: size)
                largeDataSets.append(data)
                
                Task {
                    do {
                        try await self.generateTestData(for: repository)
                        let _ = try await self.analytics.getStorageMetrics(for: repository)
                    } catch {
                        XCTFail("Memory pressure test failed: \(error)")
                    }
                }
            }
        }
        
        // Clean up
        largeDataSets.removeAll()
    }
    
    // MARK: - Load Tests
    
    func testContinuousDataProcessing() async throws {
        let duration: TimeInterval = 60 // 1 minute
        let startTime = Date()
        var operationCount = 0
        
        while Date().timeIntervalSince(startTime) < duration {
            do {
                let repository = repositories[operationCount % repositories.count]
                try await generateTestData(for: repository)
                let _ = try await analytics.getStorageMetrics(for: repository)
                operationCount += 1
            } catch {
                XCTFail("Continuous processing failed at operation \(operationCount): \(error)")
            }
        }
        
        XCTAssertGreaterThan(operationCount, 0)
        print("Completed \(operationCount) operations in \(duration) seconds")
    }
    
    func testBurstOperations() async throws {
        let burstSize = 100
        let expectations = [expectation(description: "Burst completed")]
        
        Task {
            do {
                await withThrowingTaskGroup(of: Void.self) { group in
                    for i in 0..<burstSize {
                        group.addTask {
                            let repository = self.repositories[i % self.repositories.count]
                            try await self.generateTestData(for: repository)
                            let _ = try await self.analytics.getStorageMetrics(for: repository)
                        }
                    }
                }
                expectations[0].fulfill()
            } catch {
                XCTFail("Burst operations failed: \(error)")
            }
        }
        
        await fulfillment(of: expectations, timeout: 30.0)
    }
    
    // MARK: - Resource Contention Tests
    
    func testDiskIOContention() async throws {
        let expectations = [expectation(description: "IO contention test completed")]
        let fileCount = 1000
        
        Task {
            do {
                // Create disk IO pressure
                await withThrowingTaskGroup(of: Void.self) { group in
                    // Task 1: Heavy disk writes
                    group.addTask {
                        for i in 0..<fileCount {
                            let fileURL = self.testDataDirectory.appendingPathComponent("test_\(i).dat")
                            let data = Data(count: 1024 * 1024) // 1MB
                            try data.write(to: fileURL)
                        }
                    }
                    
                    // Task 2: Analytics operations
                    group.addTask {
                        for repository in self.repositories {
                            try await self.generateTestData(for: repository)
                            let _ = try await self.analytics.getStorageMetrics(for: repository)
                        }
                    }
                    
                    // Task 3: File deletions
                    group.addTask {
                        for i in 0..<fileCount {
                            let fileURL = self.testDataDirectory.appendingPathComponent("test_\(i).dat")
                            try? FileManager.default.removeItem(at: fileURL)
                        }
                    }
                }
                
                expectations[0].fulfill()
            } catch {
                XCTFail("IO contention test failed: \(error)")
            }
        }
        
        await fulfillment(of: expectations, timeout: 60.0)
    }
    
    func testCPUContention() async throws {
        let expectations = [expectation(description: "CPU contention test completed")]
        
        Task {
            do {
                await withThrowingTaskGroup(of: Void.self) { group in
                    // Task 1: CPU-intensive calculations
                    group.addTask {
                        for _ in 0..<1_000_000 {
                            _ = sqrt(Double.random(in: 0...10000))
                        }
                    }
                    
                    // Task 2: Analytics operations
                    group.addTask {
                        for repository in self.repositories {
                            try await self.generateTestData(for: repository)
                            let _ = try await self.analytics.analyzeStorageTrend(for: repository)
                        }
                    }
                }
                
                expectations[0].fulfill()
            } catch {
                XCTFail("CPU contention test failed: \(error)")
            }
        }
        
        await fulfillment(of: expectations, timeout: 30.0)
    }
    
    // MARK: - Recovery Tests
    
    func testSystemRecovery() async throws {
        let repository = repositories[0]
        let expectations = [expectation(description: "Recovery test completed")]
        
        Task {
            do {
                // 1. Generate initial data
                try await generateTestData(for: repository)
                
                // 2. Simulate system pressure
                await withThrowingTaskGroup(of: Void.self) { group in
                    // Add memory pressure
                    group.addTask {
                        var data: [Data] = []
                        for _ in 0..<100 {
                            data.append(Data(count: 1024 * 1024))
                        }
                        _ = data.count
                    }
                    
                    // Add disk pressure
                    group.addTask {
                        for i in 0..<1000 {
                            let fileURL = self.testDataDirectory.appendingPathComponent("pressure_\(i).dat")
                            try Data(count: 1024 * 1024).write(to: fileURL)
                            try? FileManager.default.removeItem(at: fileURL)
                        }
                    }
                    
                    // Add CPU pressure
                    group.addTask {
                        for _ in 0..<1_000_000 {
                            _ = sqrt(Double.random(in: 0...10000))
                        }
                    }
                    
                    // Perform analytics operations
                    group.addTask {
                        let metrics = try await self.analytics.getStorageMetrics(for: repository)
                        XCTAssertNotNil(metrics)
                    }
                }
                
                // 3. Verify system recovery
                let finalMetrics = try await analytics.getStorageMetrics(for: repository)
                XCTAssertNotNil(finalMetrics)
                
                expectations[0].fulfill()
            } catch {
                XCTFail("System recovery test failed: \(error)")
            }
        }
        
        await fulfillment(of: expectations, timeout: 60.0)
    }
    
    // MARK: - Helper Methods
    
    private func generateTestData(for repository: Repository) async throws {
        let metrics = StorageMetrics(
            totalBytes: Int64.random(in: 1000...1000000),
            compressedBytes: Int64.random(in: 800...800000),
            deduplicatedBytes: Int64.random(in: 600...600000)
        )
        try await persistence.saveStorageMetrics(metrics, for: repository)
    }
}
