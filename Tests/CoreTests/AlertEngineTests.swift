import Foundation
import XCTest
@testable import PulseBarCore

final class AlertEngineTests: XCTestCase {
    actor Recorder {
        var count: Int = 0

        func hit() {
            count += 1
        }

        func value() -> Int {
            count
        }
    }

    func testAlertTriggersAfterDurationThreshold() async {
        let recorder = Recorder()
        let engine = AlertEngine(
            rule: AlertRule(metricID: .cpuTotalPercent, threshold: 80, durationSeconds: 10, isEnabled: true),
            cooldownSeconds: 1
        ) { _, _ in
            await recorder.hit()
        }

        let start = Date()

        await engine.process(samples: [
            MetricSample(metricID: .cpuTotalPercent, timestamp: start, value: 81, unit: .percent)
        ])

        await engine.process(samples: [
            MetricSample(metricID: .cpuTotalPercent, timestamp: start.addingTimeInterval(11), value: 82, unit: .percent)
        ])

        let count = await recorder.value()
        XCTAssertEqual(count, 1)
    }

    func testAlertResetsWhenValueDropsBelowThreshold() async {
        let recorder = Recorder()
        let engine = AlertEngine(
            rule: AlertRule(metricID: .cpuTotalPercent, threshold: 80, durationSeconds: 10, isEnabled: true),
            cooldownSeconds: 1
        ) { _, _ in
            await recorder.hit()
        }

        let start = Date()

        await engine.process(samples: [
            MetricSample(metricID: .cpuTotalPercent, timestamp: start, value: 90, unit: .percent)
        ])

        await engine.process(samples: [
            MetricSample(metricID: .cpuTotalPercent, timestamp: start.addingTimeInterval(5), value: 50, unit: .percent)
        ])

        await engine.process(samples: [
            MetricSample(metricID: .cpuTotalPercent, timestamp: start.addingTimeInterval(11), value: 90, unit: .percent)
        ])

        let count = await recorder.value()
        XCTAssertEqual(count, 0)
    }

    func testMultipleRulesCanTriggerIndependently() async {
        let recorder = Recorder()
        let engine = AlertEngine(
            rules: [
                AlertRule(metricID: .cpuTotalPercent, threshold: 80, durationSeconds: 5, isEnabled: true),
                AlertRule(metricID: .temperatureMaxCelsius, threshold: 90, durationSeconds: 5, isEnabled: true)
            ],
            cooldownSeconds: 1
        ) { _, _ in
            await recorder.hit()
        }

        let start = Date()
        await engine.process(samples: [
            MetricSample(metricID: .cpuTotalPercent, timestamp: start, value: 85, unit: .percent),
            MetricSample(metricID: .temperatureMaxCelsius, timestamp: start, value: 95, unit: .celsius)
        ])

        await engine.process(samples: [
            MetricSample(metricID: .cpuTotalPercent, timestamp: start.addingTimeInterval(6), value: 85, unit: .percent),
            MetricSample(metricID: .temperatureMaxCelsius, timestamp: start.addingTimeInterval(6), value: 95, unit: .celsius)
        ])

        let count = await recorder.value()
        XCTAssertEqual(count, 2)
    }
}
