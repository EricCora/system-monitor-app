import XCTest
@testable import PulseBarCore

final class MetricIDTests: XCTestCase {
    func testCodableRoundTripForNewStaticCases() throws {
        let metricIDs: [MetricID] = [
            .cpuUserPercent,
            .cpuSystemPercent,
            .cpuIdlePercent,
            .batteryChargePercent,
            .batteryCurrentMilliAmps,
            .batteryPowerWatts,
            .batteryTimeRemainingMinutes,
            .batteryHealthPercent,
            .batteryCycleCount,
            .batteryIsCharging,
            .memoryCompressedBytes,
            .memorySwapUsedBytes,
            .memorySwapTotalBytes,
            .memoryActiveBytes,
            .memoryWiredBytes,
            .memoryCacheBytes,
            .memoryAppBytes,
            .memoryPageInsBytesPerSec,
            .memoryPageOutsBytesPerSec,
            .cpuLoadAverage1,
            .cpuLoadAverage5,
            .cpuLoadAverage15,
            .gpuProcessorPercent,
            .gpuMemoryPercent,
            .framesPerSecond,
            .uptimeSeconds,
            .diskReadBytesPerSec,
            .diskWriteBytesPerSec,
            .diskSMARTStatusCode
        ]

        let data = try JSONEncoder().encode(metricIDs)
        let decoded = try JSONDecoder().decode([MetricID].self, from: data)
        XCTAssertEqual(decoded, metricIDs)
    }

    func testStorageKeyRoundTripForStaticAndAssociatedCases() {
        let metricIDs: [MetricID] = [
            .cpuUserPercent,
            .batteryPowerWatts,
            .cpuCorePercent(3),
            .networkInterfaceInBytesPerSec("en0"),
            .networkInterfaceOutBytesPerSec("bridge100"),
            .gpuProcessorPercent
        ]

        for metricID in metricIDs {
            XCTAssertEqual(MetricID(storageKey: metricID.storageKey), metricID)
        }
    }

    func testCodableRoundTripForAssociatedInterfaceCases() throws {
        let metricIDs: [MetricID] = [
            .networkInterfaceInBytesPerSec("en0"),
            .networkInterfaceOutBytesPerSec("en7")
        ]

        let data = try JSONEncoder().encode(metricIDs)
        let decoded = try JSONDecoder().decode([MetricID].self, from: data)
        XCTAssertEqual(decoded, metricIDs)
    }
}
