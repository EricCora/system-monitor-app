import XCTest
@testable import PulseBarCore

final class MetricIDTests: XCTestCase {
    func testCodableRoundTripForNewStaticCases() throws {
        let metricIDs: [MetricID] = [
            .batteryChargePercent,
            .batteryCurrentMilliAmps,
            .batteryTimeRemainingMinutes,
            .batteryHealthPercent,
            .batteryCycleCount,
            .batteryIsCharging,
            .memoryCompressedBytes,
            .memorySwapUsedBytes,
            .cpuLoadAverage1,
            .cpuLoadAverage5,
            .cpuLoadAverage15,
            .diskReadBytesPerSec,
            .diskWriteBytesPerSec,
            .diskSMARTStatusCode
        ]

        let data = try JSONEncoder().encode(metricIDs)
        let decoded = try JSONDecoder().decode([MetricID].self, from: data)
        XCTAssertEqual(decoded, metricIDs)
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
