import XCTest
import IOKit.ps
@testable import PulseBarCore

final class BatteryProviderTests: XCTestCase {
    func testParseBatterySnapshotFromDescription() {
        let description: [String: Any] = [
            kIOPSTypeKey as String: "InternalBattery",
            kIOPSCurrentCapacityKey as String: 75,
            kIOPSMaxCapacityKey as String: 100,
            kIOPSIsChargingKey as String: true,
            kIOPSCurrentKey as String: 1200,
            kIOPSVoltageKey as String: 12000,
            kIOPSTimeToFullChargeKey as String: 45,
            "DesignCapacity": 110,
            "Cycle Count": 330
        ]

        let snapshot = BatteryProvider.parseBatterySnapshot(from: description)
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.chargePercent, 75)
        XCTAssertEqual(snapshot?.signedCurrentMilliAmps, 1200)
        XCTAssertEqual(snapshot?.voltageMilliVolts, 12000)
        XCTAssertEqual(snapshot?.signedPowerWatts, 14.4)
        XCTAssertEqual(snapshot?.timeRemainingMinutes, 45)
        XCTAssertEqual(snapshot?.cycleCount, 330)
        XCTAssertEqual(snapshot?.isCharging, true)
    }

    func testMetricSampleMappingIncludesRequiredFields() {
        let snapshot = BatterySnapshot(
            chargePercent: 55,
            currentMilliAmps: nil,
            voltageMilliVolts: nil,
            timeRemainingMinutes: nil,
            healthPercent: nil,
            cycleCount: nil,
            isCharging: false
        )

        let samples = BatteryProvider.metricSamples(from: snapshot, date: Date())
        XCTAssertTrue(samples.contains(where: { $0.metricID == .batteryChargePercent }))
        XCTAssertTrue(samples.contains(where: { $0.metricID == .batteryIsCharging && $0.value == 0 }))
    }

    func testParsesRegistrySupplementForHealthAndCycle() {
        let properties: [String: Any] = [
            "AppleRawMaxCapacity": 4415,
            "DesignCapacity": 5103,
            "CycleCount": 247,
            "Voltage": 11876
        ]

        let supplemental = BatteryProvider.parseRegistrySupplement(from: properties)
        XCTAssertEqual(supplemental.cycleCount, 247)
        XCTAssertNotNil(supplemental.healthPercent)
        XCTAssertEqual(round((supplemental.healthPercent ?? 0) * 10) / 10, 86.5)
        XCTAssertEqual(supplemental.voltageMilliVolts, 11876)
    }

    func testMetricSampleMappingIncludesPowerWhenCurrentAndVoltageAvailable() {
        let snapshot = BatterySnapshot(
            chargePercent: 80,
            currentMilliAmps: 1500,
            voltageMilliVolts: 12000,
            timeRemainingMinutes: nil,
            healthPercent: nil,
            cycleCount: nil,
            isCharging: false
        )

        let samples = BatteryProvider.metricSamples(from: snapshot, date: Date())

        XCTAssertTrue(samples.contains(where: {
            $0.metricID == .batteryPowerWatts && $0.unit == .watts && $0.value == -18
        }))
    }

    func testDischargingSnapshotProducesNegativeCurrentAndPower() {
        let snapshot = BatterySnapshot(
            chargePercent: 42,
            currentMilliAmps: 1750,
            voltageMilliVolts: 11800,
            timeRemainingMinutes: 120,
            healthPercent: nil,
            cycleCount: nil,
            isCharging: false
        )

        XCTAssertEqual(snapshot.signedCurrentMilliAmps, -1750)
        XCTAssertEqual(round((snapshot.signedPowerWatts ?? 0) * 100) / 100, -20.65)
    }
}
