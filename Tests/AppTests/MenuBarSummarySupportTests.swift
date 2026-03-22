import XCTest
@testable import PulseBarApp
import PulseBarCore

final class MenuBarSummarySupportTests: XCTestCase {
    func testCPUTextIncludesLoadAverageWhenAvailable() {
        let samples: [MetricID: MetricSample] = [
            .cpuTotalPercent: MetricSample(metricID: .cpuTotalPercent, timestamp: Date(), value: 62, unit: .percent),
            .cpuLoadAverage1: MetricSample(metricID: .cpuLoadAverage1, timestamp: Date(), value: 4.25, unit: .scalar)
        ]

        let text = MenuBarMetricSummaryFormatter.text(
            for: .cpu,
            latestSamples: samples,
            thermalState: .nominal,
            throughputUnit: .bytesPerSecond
        )

        XCTAssertEqual(text, "CPU 62% L4.25")
    }

    func testTemperatureValueFallsBackToThermalStateLabel() {
        let text = MenuBarMetricSummaryFormatter.valueText(
            for: .temperature,
            latestSamples: [:],
            thermalState: .serious,
            throughputUnit: .bytesPerSecond
        )

        XCTAssertEqual(text, "Hot")
    }

    func testNetworkValueTextUsesCombinedThroughput() {
        let samples: [MetricID: MetricSample] = [
            .networkInBytesPerSec: MetricSample(metricID: .networkInBytesPerSec, timestamp: Date(), value: 2_048, unit: .bytesPerSecond),
            .networkOutBytesPerSec: MetricSample(metricID: .networkOutBytesPerSec, timestamp: Date(), value: 1_024, unit: .bytesPerSecond)
        ]

        let text = MenuBarMetricSummaryFormatter.valueText(
            for: .network,
            latestSamples: samples,
            thermalState: .nominal,
            throughputUnit: .bytesPerSecond
        )

        XCTAssertEqual(text, "3 KB/s")
    }
}
