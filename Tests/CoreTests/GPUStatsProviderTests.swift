import XCTest
@testable import PulseBarCore

final class GPUStatsProviderTests: XCTestCase {
    func testSnapshotParsesDeviceUtilizationAndMemoryPercent() {
        let snapshot = GPUStatsProvider.snapshot(
            from: [
                "model": "Apple M1",
                "PerformanceStatistics": [
                    "Device Utilization %": 16,
                    "In use system memory": 522_240_000,
                    "Alloc system memory": 1_848_770_560
                ]
            ]
        )

        XCTAssertEqual(snapshot.deviceName, "Apple M1")
        XCTAssertEqual(snapshot.processorPercent ?? -1, 16, accuracy: 0.001)
        XCTAssertEqual(snapshot.memoryPercent ?? -1, 28.2466, accuracy: 0.01)
        XCTAssertTrue(snapshot.available)
        XCTAssertNil(snapshot.statusMessage)
    }

    func testSnapshotFallsBackToRendererAndTilerUtilization() {
        let snapshot = GPUStatsProvider.snapshot(
            from: [
                "model": "Apple M2",
                "PerformanceStatistics": [
                    "Renderer Utilization %": 11,
                    "Tiler Utilization %": 23
                ]
            ]
        )

        XCTAssertEqual(snapshot.processorPercent ?? -1, 23, accuracy: 0.001)
        XCTAssertNil(snapshot.memoryPercent)
        XCTAssertTrue(snapshot.available)
    }

    func testSampleEmitsOnlyAvailableMetrics() async throws {
        let provider = GPUStatsProvider(
            snapshotReader: {
                GPUSummarySnapshot(
                    processorPercent: 42,
                    memoryPercent: nil,
                    deviceName: "Apple M3",
                    available: true
                )
            }
        )

        let samples = try await provider.sample(at: Date())

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.metricID, .gpuProcessorPercent)
        XCTAssertEqual(samples.first?.value ?? -1, 42, accuracy: 0.001)
    }
}
