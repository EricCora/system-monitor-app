import XCTest
@testable import PulseBarApp
import PulseBarCore

@MainActor
final class DashboardRoutingAndTemperatureTests: XCTestCase {
    func testStartupDirectIOHIDProbePopulatesChannelsWithoutPrompting() async throws {
        let defaults = makeDefaults()
        let reading = makeDirectReading()
        let controller = SettingsController(defaults: defaults)
        controller.privilegedTemperatureEnabled = true

        let coordinator = AppCoordinator(
            defaults: defaults,
            directTemperatureDataSource: FixedTemperatureDataSource(reading: reading),
            helperReachabilityProbe: { false }
        )

        let telemetryStore = try XCTUnwrap(mirrorChild(named: "telemetryStore", in: coordinator) as? TelemetryStore)
        let matched = try await conditionMatches(within: 2) {
            let visibleNames = Set(telemetryStore.latestSensorChannels.map(\.displayName))
            return telemetryStore.privilegedTemperatureHealthy
                && telemetryStore.usingPersistedTemperatureSnapshot == false
                && visibleNames == Set(["CPU Die", "GPU Die"])
                && telemetryStore.privilegedSourceDiagnostics.contains(where: { $0.source == "direct-iohid" && $0.healthy })
                && telemetryStore.privilegedTemperatureStatusMessage?.contains("Direct IOHID") == true
        }
        let directRuntimeState = String(describing: mirrorChild(named: "directTemperatureRuntimeState", in: coordinator))
        let failureMessage = "Expected direct IOHID startup parity, got enabled=\(coordinator.privilegedTemperatureEnabled), directRuntimeState=\(directRuntimeState), status=\(telemetryStore.privilegedTemperatureStatusMessage ?? "nil"), healthy=\(telemetryStore.privilegedTemperatureHealthy), snapshot=\(telemetryStore.usingPersistedTemperatureSnapshot), channels=\(telemetryStore.latestSensorChannels.map(\.displayName)), diagnostics=\(telemetryStore.privilegedSourceDiagnostics)"
        XCTAssertTrue(
            matched,
            failureMessage
        )
    }

    func testDashboardSectionDefaultsToOverviewAndCardShortcutsOpenDetailSections() {
        let coordinator = AppCoordinator(defaults: makeDefaults())

        XCTAssertEqual(coordinator.dashboardSection, .overview)

        coordinator.setDashboardSection(.network)
        XCTAssertEqual(coordinator.dashboardSection, .network)

        coordinator.openDashboardDetails(for: .sensors)
        XCTAssertEqual(coordinator.dashboardSection, .temperature)

        coordinator.resetDashboardSectionForPresentation()
        XCTAssertEqual(coordinator.dashboardSection, .overview)
    }

    func testStartupHydratesLatestTemperatureSnapshotWithoutPrompting() async throws {
        let defaults = makeDefaults()
        let snapshot = makeSnapshot()

        try await withUniqueTemporaryDirectory { _ in
            let controller = SettingsController(defaults: defaults)
            controller.privilegedTemperatureEnabled = true
            controller.persistLatestTemperatureSnapshot(snapshot)

            let coordinator = AppCoordinator(
                defaults: defaults,
                directTemperatureDataSource: FailingTemperatureDataSource(),
                helperReachabilityProbe: { false }
            )
            let telemetryStore = try XCTUnwrap(mirrorChild(named: "telemetryStore", in: coordinator) as? TelemetryStore)

            try await waitUntil {
                telemetryStore.usingPersistedTemperatureSnapshot
                    && telemetryStore.latestSensorChannels == snapshot.channels
                    && telemetryStore.privilegedTemperatureStatusMessage?.contains("paused until you retry") == true
            }
        }
    }

    func testDisablingPrivilegedTemperatureClearsHydratedSnapshotState() async throws {
        let defaults = makeDefaults()
        let snapshot = makeSnapshot()

        try await withUniqueTemporaryDirectory { _ in
            let controller = SettingsController(defaults: defaults)
            controller.privilegedTemperatureEnabled = true
            controller.persistLatestTemperatureSnapshot(snapshot)

            let coordinator = AppCoordinator(
                defaults: defaults,
                directTemperatureDataSource: FailingTemperatureDataSource(),
                helperReachabilityProbe: { false }
            )
            let telemetryStore = try XCTUnwrap(mirrorChild(named: "telemetryStore", in: coordinator) as? TelemetryStore)
            let settingsController = try XCTUnwrap(mirrorChild(named: "settingsController", in: coordinator) as? SettingsController)

            try await waitUntil {
                telemetryStore.usingPersistedTemperatureSnapshot
                    && telemetryStore.latestSensorChannels == snapshot.channels
            }

            coordinator.privilegedTemperatureEnabled = false

            try await waitUntil {
                telemetryStore.latestSensorChannels.isEmpty
                    && telemetryStore.latestTemperatureSensors.isEmpty
                    && settingsController.loadLatestTemperatureSnapshot() == nil
            }
        }
    }

    func testFallbackTemperatureRowsUseAggregateMetricsWhenSensorChannelsAreUnavailable() throws {
        let coordinator = AppCoordinator(defaults: makeDefaults())
        let telemetryStore = try XCTUnwrap(mirrorChild(named: "telemetryStore", in: coordinator) as? TelemetryStore)
        let timestamp = Date(timeIntervalSince1970: 1_700_001_234)

        telemetryStore.latestSamples[.temperaturePrimaryCelsius] = MetricSample(
            metricID: .temperaturePrimaryCelsius,
            timestamp: timestamp,
            value: 54,
            unit: .celsius
        )
        telemetryStore.latestSamples[.temperatureMaxCelsius] = MetricSample(
            metricID: .temperatureMaxCelsius,
            timestamp: timestamp,
            value: 63,
            unit: .celsius
        )

        XCTAssertEqual(
            coordinator.fallbackTemperatureRows(),
            [
                TemperatureSensorReading(name: "Primary", celsius: 54),
                TemperatureSensorReading(name: "Maximum", celsius: 63)
            ]
        )
    }

    func testFallbackTemperatureRowsIgnoreInvalidAggregateMetrics() throws {
        let coordinator = AppCoordinator(defaults: makeDefaults())
        let telemetryStore = try XCTUnwrap(mirrorChild(named: "telemetryStore", in: coordinator) as? TelemetryStore)
        let timestamp = Date(timeIntervalSince1970: 1_700_001_567)

        telemetryStore.latestSamples[.temperaturePrimaryCelsius] = MetricSample(
            metricID: .temperaturePrimaryCelsius,
            timestamp: timestamp,
            value: .nan,
            unit: .celsius
        )
        telemetryStore.latestSamples[.temperatureMaxCelsius] = MetricSample(
            metricID: .temperatureMaxCelsius,
            timestamp: timestamp,
            value: 61,
            unit: .celsius
        )

        XCTAssertEqual(
            coordinator.fallbackTemperatureRows(),
            [TemperatureSensorReading(name: "Maximum", celsius: 61)]
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DashboardRoutingAndTemperatureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeSnapshot() -> LatestTemperatureSnapshot {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_987)
        return LatestTemperatureSnapshot(
            channels: [
                SensorReading(
                    id: "cpu-die",
                    rawName: "CPU Die",
                    displayName: "CPU Die",
                    category: .cpu,
                    channelType: .temperatureCelsius,
                    value: 67,
                    source: "snapshot",
                    timestamp: capturedAt
                )
            ],
            temperatureSensors: [
                TemperatureSensorReading(name: "CPU Die", celsius: 67)
            ],
            lastSuccessMessage: "Last successful privileged sample: 10:15 AM.",
            sourceDiagnostics: [
                SensorSourceDiagnostic(source: "snapshot", healthy: true, message: "restored")
            ],
            fanHealthy: false,
            channelsAvailable: [.temperatureCelsius],
            activeSourceChain: ["snapshot"],
            fanParityGateBlocked: false,
            fanParityGateMessage: nil,
            capturedAt: capturedAt
        )
    }

    private func makeDirectReading() -> PowermetricsTemperatureReading {
        let timestamp = Date(timeIntervalSince1970: 1_700_010_123)
        return PowermetricsTemperatureReading(
            primaryCelsius: 61,
            maxCelsius: 67,
            sensorCount: 2,
            sensors: [
                TemperatureSensorReading(name: "CPU Die", celsius: 61),
                TemperatureSensorReading(name: "GPU Die", celsius: 67)
            ],
            channels: [
                SensorReading(
                    id: "cpu-die",
                    rawName: "CPU Die",
                    displayName: "CPU Die",
                    category: .cpu,
                    channelType: .temperatureCelsius,
                    value: 61,
                    source: "iohid",
                    timestamp: timestamp
                ),
                SensorReading(
                    id: "gpu-die",
                    rawName: "GPU Die",
                    displayName: "GPU Die",
                    category: .gpu,
                    channelType: .temperatureCelsius,
                    value: 67,
                    source: "iohid",
                    timestamp: timestamp
                )
            ],
            source: "iohid"
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        XCTFail("Condition not satisfied before timeout")
    }

    private func conditionMatches(
        within timeout: TimeInterval = 2,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        return condition()
    }

    private func withUniqueTemporaryDirectory(
        _ body: (URL) async throws -> Void
    ) async throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let previousTMPDIR = getenv("TMPDIR").flatMap { pointer in
            String(validatingUTF8: pointer)
        }
        setenv("TMPDIR", temporaryRoot.path + "/", 1)
        defer {
            if let previousTMPDIR {
                setenv("TMPDIR", previousTMPDIR, 1)
            } else {
                unsetenv("TMPDIR")
            }
            try? fileManager.removeItem(at: temporaryRoot)
        }

        try await body(temporaryRoot)
    }

    private func mirrorChild(named name: String, in value: Any) -> Any? {
        Mirror(reflecting: value).children.first(where: { $0.label == name })?.value
    }
}

private struct FixedTemperatureDataSource: TemperatureDataSource {
    let reading: PowermetricsTemperatureReading

    func readTemperatures() async throws -> PowermetricsTemperatureReading {
        reading
    }
}

private struct FailingTemperatureDataSource: TemperatureDataSource {
    func readTemperatures() async throws -> PowermetricsTemperatureReading {
        throw ProviderError.unavailable("stubbed direct IOHID failure")
    }
}
