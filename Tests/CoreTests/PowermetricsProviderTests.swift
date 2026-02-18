import XCTest
@testable import PulseBarCore

final class PowermetricsProviderTests: XCTestCase {
    private enum FixtureError: Error {
        case unavailable
    }

    private actor MockState {
        private var queue: [Result<PowermetricsTemperatureReading, Error>]
        private(set) var calls: Int = 0

        init(_ queue: [Result<PowermetricsTemperatureReading, Error>]) {
            self.queue = queue
        }

        func next() throws -> PowermetricsTemperatureReading {
            calls += 1
            guard !queue.isEmpty else {
                throw FixtureError.unavailable
            }
            return try queue.removeFirst().get()
        }

        func callCount() -> Int {
            calls
        }
    }

    private struct MockDataSource: TemperatureDataSource {
        let state: MockState

        func readTemperatures() async throws -> PowermetricsTemperatureReading {
            try await state.next()
        }
    }

    func testEnabledProviderReturnsCelsiusSamples() async {
        let reading = PowermetricsTemperatureReading(
            primaryCelsius: 54.2,
            maxCelsius: 61.8,
            sensorCount: 9,
            source: "iohid"
        )
        let state = MockState([.success(reading)])
        let provider = PowermetricsProvider(
            dataSource: MockDataSource(state: state),
            minCollectionInterval: 5
        )

        await provider.updateEnabled(true)
        let samples = try? await provider.sample(at: Date())

        XCTAssertEqual(samples?.count, 2)
        XCTAssertEqual(samples?.first(where: { $0.metricID == .temperaturePrimaryCelsius })?.value ?? -1, 54.2, accuracy: 0.01)
        XCTAssertEqual(samples?.first(where: { $0.metricID == .temperatureMaxCelsius })?.value ?? -1, 61.8, accuracy: 0.01)

        let status = await provider.currentStatus()
        XCTAssertTrue(status.healthy)
        XCTAssertEqual(status.sourceDescription, "privileged helper (iohid)")
        let calls = await state.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testUsesCachedReadingInsideMinInterval() async {
        let reading = PowermetricsTemperatureReading(primaryCelsius: 50, maxCelsius: 58, sensorCount: 4)
        let state = MockState([.success(reading)])
        let provider = PowermetricsProvider(
            dataSource: MockDataSource(state: state),
            minCollectionInterval: 5
        )

        let start = Date()
        await provider.updateEnabled(true)
        let first = try? await provider.sample(at: start)
        let second = try? await provider.sample(at: start.addingTimeInterval(1))

        XCTAssertEqual(first?.count, 2)
        XCTAssertEqual(second?.count, 2)
        let calls = await state.callCount()
        XCTAssertEqual(calls, 1)
    }

    func testFailureSetsDegradedStatusAndBackoff() async {
        let state = MockState([.failure(FixtureError.unavailable)])
        let provider = PowermetricsProvider(
            dataSource: MockDataSource(state: state),
            minCollectionInterval: 5
        )

        await provider.updateEnabled(true)
        let samples = try? await provider.sample(at: Date())
        XCTAssertEqual(samples?.count, 0)

        let status = await provider.currentStatus()
        XCTAssertFalse(status.healthy)
        XCTAssertNotNil(status.lastErrorMessage)
        XCTAssertNotNil(status.nextRetryAt)
    }

    func testProbeNowUpdatesStateImmediatelyOnSuccess() async {
        let reading = PowermetricsTemperatureReading(primaryCelsius: 47.5, maxCelsius: 55.1, sensorCount: 5)
        let state = MockState([.success(reading)])
        let provider = PowermetricsProvider(
            dataSource: MockDataSource(state: state),
            minCollectionInterval: 5
        )

        await provider.updateEnabled(true)
        let samples = await provider.probeNow(at: Date())
        let status = await provider.currentStatus()

        XCTAssertEqual(samples.count, 2)
        XCTAssertTrue(status.healthy)
        XCTAssertNil(status.lastErrorMessage)
    }

    func testProbeNowSetsErrorAndRetryOnFailure() async {
        let state = MockState([.failure(FixtureError.unavailable)])
        let provider = PowermetricsProvider(
            dataSource: MockDataSource(state: state),
            minCollectionInterval: 5
        )

        await provider.updateEnabled(true)
        let samples = await provider.probeNow(at: Date())
        let status = await provider.currentStatus()

        XCTAssertEqual(samples.count, 0)
        XCTAssertFalse(status.healthy)
        XCTAssertNotNil(status.lastErrorMessage)
        XCTAssertNotNil(status.nextRetryAt)
    }

    func testStatusIncludesChannelAndSourceChainMetadata() async {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let reading = PowermetricsTemperatureReading(
            primaryCelsius: 48,
            maxCelsius: 60,
            sensorCount: 3,
            channels: [
                SensorReading(
                    id: "iohid:temperatureCelsius:cpu",
                    rawName: "CPU",
                    displayName: "CPU",
                    category: .cpu,
                    channelType: .temperatureCelsius,
                    value: 48,
                    source: "iohid",
                    timestamp: now
                ),
                SensorReading(
                    id: "smc:fanRPM:fan0",
                    rawName: "F0Ac",
                    displayName: "System Fan 1",
                    category: .fan,
                    channelType: .fanRPM,
                    value: 1120,
                    source: "smc",
                    timestamp: now
                )
            ],
            source: "iohid",
            sourceChain: ["iohid", "smc"],
            sourceDiagnostics: [
                SensorSourceDiagnostic(source: "iohid", healthy: true, message: nil),
                SensorSourceDiagnostic(source: "smc", healthy: true, message: nil)
            ],
            fanTelemetryAvailable: true,
            fanCount: 1
        )
        let state = MockState([.success(reading)])
        let provider = PowermetricsProvider(
            dataSource: MockDataSource(state: state),
            minCollectionInterval: 5
        )

        await provider.updateEnabled(true)
        _ = await provider.probeNow(at: now)
        let status = await provider.currentStatus()

        XCTAssertTrue(status.fanTelemetryHealthy)
        XCTAssertEqual(status.activeSourceChain, ["iohid", "smc"])
        XCTAssertTrue(status.channelsAvailable.contains(.temperatureCelsius))
        XCTAssertTrue(status.channelsAvailable.contains(.fanRPM))
        XCTAssertEqual(status.sourceDiagnostics.count, 2)
    }
}
