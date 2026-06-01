import XCTest
@testable import PulseBarApp
import PulseBarCore

final class ChartPresentationPolicyTests: XCTestCase {
    func testEmptySamplesUseZeroBaselineWithoutThermalAxis() {
        let resolved = ChartPresentationPolicy.resolve(for: [])

        XCTAssertEqual(resolved.baseline, .zero())
        XCTAssertNil(resolved.areaOpacityMultiplier)
        XCTAssertFalse(resolved.usesThermalYAxis)
    }

    func testThermalStateUsesFixedDomainAndThermalAxis() {
        let samples = [
            MetricSample(metricID: .thermalStateLevel, timestamp: Date(), value: 1, unit: .scalar)
        ]

        let resolved = ChartPresentationPolicy.resolve(for: samples)

        XCTAssertEqual(resolved.baseline, .fixed(0 ... 3))
        XCTAssertNil(resolved.areaOpacityMultiplier)
        XCTAssertTrue(resolved.usesThermalYAxis)
    }

    func testNearConstantBatteryChargeReducesAreaOpacity() {
        let samples = [
            MetricSample(metricID: .batteryChargePercent, timestamp: Date(timeIntervalSince1970: 100), value: 80, unit: .percent),
            MetricSample(metricID: .batteryChargePercent, timestamp: Date(timeIntervalSince1970: 200), value: 80.5, unit: .percent)
        ]

        let resolved = ChartPresentationPolicy.resolve(for: samples)

        XCTAssertEqual(resolved.baseline, .fixed(0 ... 100))
        XCTAssertEqual(resolved.areaOpacityMultiplier, 0.32)
        XCTAssertFalse(resolved.usesThermalYAxis)
    }

    func testVaryingBatteryChargeLeavesAreaOpacityUnchanged() {
        let samples = [
            MetricSample(metricID: .batteryChargePercent, timestamp: Date(timeIntervalSince1970: 100), value: 80, unit: .percent),
            MetricSample(metricID: .batteryChargePercent, timestamp: Date(timeIntervalSince1970: 200), value: 75, unit: .percent)
        ]

        let resolved = ChartPresentationPolicy.resolve(for: samples)

        XCTAssertEqual(resolved.baseline, .fixed(0 ... 100))
        XCTAssertNil(resolved.areaOpacityMultiplier)
    }

    func testTemperaturePrimaryUsesDataMinBaseline() {
        let samples = [
            MetricSample(metricID: .temperaturePrimaryCelsius, timestamp: Date(), value: 42, unit: .celsius)
        ]

        let resolved = ChartPresentationPolicy.resolve(for: samples)

        XCTAssertEqual(resolved.baseline, .dataMin(minimumSpan: 1, paddingFraction: 0.1))
        XCTAssertFalse(resolved.usesThermalYAxis)
    }

    func testGenericPercentMetricUsesZeroBaseline() {
        let samples = [
            MetricSample(metricID: .cpuTotalPercent, timestamp: Date(), value: 42, unit: .percent)
        ]

        let resolved = ChartPresentationPolicy.resolve(for: samples)

        XCTAssertEqual(resolved.baseline, .zero(minimumSpan: 1, paddingFraction: 0.1))
        XCTAssertNil(resolved.areaOpacityMultiplier)
    }

    func testDisplayOptionsAppliesBatteryOpacityMultiplierFromEnvironment() {
        let samples = [
            MetricSample(metricID: .batteryChargePercent, timestamp: Date(timeIntervalSince1970: 100), value: 90, unit: .percent),
            MetricSample(metricID: .batteryChargePercent, timestamp: Date(timeIntervalSince1970: 200), value: 90.2, unit: .percent)
        ]
        let environment = ChartDisplayOptions(areaOpacity: 0.5)

        let options = ChartPresentationPolicy.displayOptions(
            base: ChartDisplayOptions(),
            environment: environment,
            for: samples
        )

        XCTAssertEqual(options.areaOpacity ?? -1, 0.16, accuracy: 0.0001)
    }

    func testDisplayOptionsPreservesExplicitBaseOpacity() {
        let samples = [
            MetricSample(metricID: .batteryChargePercent, timestamp: Date(timeIntervalSince1970: 100), value: 90, unit: .percent),
            MetricSample(metricID: .batteryChargePercent, timestamp: Date(timeIntervalSince1970: 200), value: 90.2, unit: .percent)
        ]
        let base = ChartDisplayOptions(areaOpacity: 0.4)
        let environment = ChartDisplayOptions(areaOpacity: 0.5)

        let options = ChartPresentationPolicy.displayOptions(
            base: base,
            environment: environment,
            for: samples
        )

        XCTAssertEqual(options.areaOpacity ?? -1, 0.128, accuracy: 0.0001)
    }

    func testDisplayOptionsLeavesUnmodifiedMetricsAlone() {
        let samples = [
            MetricSample(metricID: .cpuTotalPercent, timestamp: Date(), value: 50, unit: .percent)
        ]
        let base = ChartDisplayOptions(areaOpacity: 0.4)

        let options = ChartPresentationPolicy.displayOptions(
            base: base,
            environment: ChartDisplayOptions(),
            for: samples
        )

        XCTAssertEqual(options.areaOpacity, 0.4)
    }
}
