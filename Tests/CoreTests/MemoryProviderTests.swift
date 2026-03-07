import Foundation
import XCTest
@testable import PulseBarCore

final class MemoryProviderTests: XCTestCase {
    func testEmitsExpandedMemoryMetrics() async throws {
        let snapshot = MemoryVMStatsSnapshot(
            pageSizeBytes: 4_096,
            totalMemoryBytes: 16 * 1_073_741_824,
            freePages: 100,
            activePages: 400,
            inactivePages: 300,
            wiredPages: 200,
            compressedPages: 50,
            cachePages: 120,
            pageIns: 1_000,
            pageOuts: 500
        )
        let provider = MemoryProvider(
            vmStatsReader: { snapshot },
            swapUsageReader: { MemorySwapUsageSnapshot(totalBytes: 2_048, usedBytes: 1_024) }
        )

        let samples = try await provider.sample(at: Date())
        let metricIDs = Set(samples.map(\.metricID))

        XCTAssertTrue(metricIDs.contains(.memoryUsedBytes))
        XCTAssertTrue(metricIDs.contains(.memoryFreeBytes))
        XCTAssertTrue(metricIDs.contains(.memoryCompressedBytes))
        XCTAssertTrue(metricIDs.contains(.memorySwapUsedBytes))
        XCTAssertTrue(metricIDs.contains(.memorySwapTotalBytes))
        XCTAssertTrue(metricIDs.contains(.memoryActiveBytes))
        XCTAssertTrue(metricIDs.contains(.memoryWiredBytes))
        XCTAssertTrue(metricIDs.contains(.memoryCacheBytes))
        XCTAssertTrue(metricIDs.contains(.memoryAppBytes))
        XCTAssertTrue(metricIDs.contains(.memoryPressureLevel))
        XCTAssertTrue(metricIDs.contains(.memoryPageInsBytesPerSec))
        XCTAssertTrue(metricIDs.contains(.memoryPageOutsBytesPerSec))
    }

    func testPageRateDeltaIsZeroOnBootstrapAndComputedOnNextSample() async throws {
        let first = MemoryVMStatsSnapshot(
            pageSizeBytes: 4_096,
            totalMemoryBytes: 8 * 1_073_741_824,
            freePages: 80,
            activePages: 200,
            inactivePages: 160,
            wiredPages: 90,
            compressedPages: 40,
            cachePages: 60,
            pageIns: 100,
            pageOuts: 200
        )
        let second = MemoryVMStatsSnapshot(
            pageSizeBytes: 4_096,
            totalMemoryBytes: 8 * 1_073_741_824,
            freePages: 70,
            activePages: 210,
            inactivePages: 170,
            wiredPages: 95,
            compressedPages: 42,
            cachePages: 62,
            pageIns: 130,
            pageOuts: 260
        )

        let sequence = SnapshotSequence([first, second])
        let provider = MemoryProvider(
            vmStatsReader: { sequence.next() },
            swapUsageReader: { nil }
        )

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let bootstrap = try await provider.sample(at: start)
        let next = try await provider.sample(at: start.addingTimeInterval(2))

        XCTAssertEqual(metricValue(.memoryPageInsBytesPerSec, in: bootstrap), 0, accuracy: 0.001)
        XCTAssertEqual(metricValue(.memoryPageOutsBytesPerSec, in: bootstrap), 0, accuracy: 0.001)

        XCTAssertEqual(metricValue(.memoryPageInsBytesPerSec, in: next), 61_440, accuracy: 0.001)
        XCTAssertEqual(metricValue(.memoryPageOutsBytesPerSec, in: next), 122_880, accuracy: 0.001)
    }

    func testSwapFallbackDefaultsToZeroWhenUnavailable() async throws {
        let snapshot = MemoryVMStatsSnapshot(
            pageSizeBytes: 4_096,
            totalMemoryBytes: 4 * 1_073_741_824,
            freePages: 90,
            activePages: 180,
            inactivePages: 120,
            wiredPages: 80,
            compressedPages: 20,
            cachePages: 40,
            pageIns: 10,
            pageOuts: 5
        )
        let provider = MemoryProvider(
            vmStatsReader: { snapshot },
            swapUsageReader: { nil }
        )

        let samples = try await provider.sample(at: Date())

        XCTAssertEqual(metricValue(.memorySwapUsedBytes, in: samples), 0, accuracy: 0.001)
        XCTAssertEqual(metricValue(.memorySwapTotalBytes, in: samples), 0, accuracy: 0.001)
    }

    private func metricValue(_ metricID: MetricID, in samples: [MetricSample]) -> Double {
        samples.first(where: { $0.metricID == metricID })?.value ?? -1
    }
}

private final class SnapshotSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [MemoryVMStatsSnapshot]
    private var index = 0

    init(_ snapshots: [MemoryVMStatsSnapshot]) {
        self.snapshots = snapshots
    }

    func next() -> MemoryVMStatsSnapshot {
        lock.lock()
        defer { lock.unlock() }

        guard !snapshots.isEmpty else {
            return MemoryVMStatsSnapshot(
                pageSizeBytes: 4_096,
                totalMemoryBytes: 0,
                freePages: 0,
                activePages: 0,
                inactivePages: 0,
                wiredPages: 0,
                compressedPages: 0,
                cachePages: 0,
                pageIns: 0,
                pageOuts: 0
            )
        }

        let safeIndex = min(index, snapshots.count - 1)
        let snapshot = snapshots[safeIndex]
        if index < snapshots.count - 1 {
            index += 1
        }
        return snapshot
    }
}
