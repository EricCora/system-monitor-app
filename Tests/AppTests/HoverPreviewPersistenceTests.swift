import XCTest
@testable import PulseBarApp
import PulseBarCore

@MainActor
final class HoverPreviewPersistenceTests: XCTestCase {
    func testCPUPreviewDoesNotMutatePersistedDefaultSelection() {
        let coordinator = AppCoordinator(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let controller = DetachedMetricsPaneController()

        coordinator.selectedCPUPaneChart = .usage
        controller.setPreviewTargetForTesting(.cpu(chart: .loadAverage))

        XCTAssertEqual(coordinator.selectedCPUPaneChart, .usage)
        XCTAssertEqual(controller.activeTarget, .cpu(chart: .loadAverage))
    }

    func testMemoryPreviewDoesNotMutatePersistedDefaultSelection() {
        let coordinator = AppCoordinator(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let controller = DetachedMetricsPaneController()

        coordinator.selectedMemoryPaneChart = .composition
        controller.setPreviewTargetForTesting(.memory(chart: .swap))

        XCTAssertEqual(coordinator.selectedMemoryPaneChart, .composition)
        XCTAssertEqual(controller.activeTarget, .memory(chart: .swap))
    }

    func testMetricHistorySeriesFallsBackToInMemoryStoreWhenPersistentHistoryUnavailable() async throws {
        let coordinator = AppCoordinator(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let telemetryStore = try XCTUnwrap(mirrorChild(named: "telemetryStore", in: coordinator) as? TelemetryStore)
        let timeSeriesStore = try XCTUnwrap(mirrorChild(named: "store", in: coordinator) as? TimeSeriesStore)
        let metricID = MetricID.networkInterfaceInBytesPerSec("codex-test0")
        let timestamp = Date().addingTimeInterval(30)

        await timeSeriesStore.append([
            MetricSample(metricID: metricID, timestamp: timestamp, value: 4.2, unit: .bytesPerSecond)
        ])

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            telemetryStore.setHistoryStartupStatus(metric: "History unavailable", memory: nil, temperature: nil)
            let history = await coordinator.metricHistorySeries(for: metricID, window: .oneHour, maxPoints: 10_000)
            if history.contains(where: {
                abs($0.timestamp.timeIntervalSince(timestamp)) < 0.001
                    && abs($0.value - 4.2) < 0.001
                    && $0.unit == .bytesPerSecond
            }) {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Expected fallback metric history to include the injected in-memory sample")
    }

    private func mirrorChild(named name: String, in value: Any) -> Any? {
        Mirror(reflecting: value).children.first(where: { $0.label == name })?.value
    }
}
