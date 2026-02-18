import XCTest
@testable import PulseBarCore

final class CompositeTemperatureDataSourceTests: XCTestCase {
    private enum FixtureError: Error {
        case primaryFailed
        case fallbackFailed
    }

    private actor SourceState {
        private let result: Result<PowermetricsTemperatureReading, Error>
        private(set) var callCount = 0

        init(result: Result<PowermetricsTemperatureReading, Error>) {
            self.result = result
        }

        func read() throws -> PowermetricsTemperatureReading {
            callCount += 1
            return try result.get()
        }

        func calls() -> Int {
            callCount
        }
    }

    private struct StubSource: TemperatureDataSource {
        let state: SourceState

        func readTemperatures() async throws -> PowermetricsTemperatureReading {
            try await state.read()
        }
    }

    func testPrimarySuccessSkipsFallback() async throws {
        let primaryState = SourceState(result: .success(
            PowermetricsTemperatureReading(
                primaryCelsius: 53.4,
                maxCelsius: 60.2,
                sensorCount: 8,
                source: "iohid"
            )
        ))
        let fallbackState = SourceState(result: .failure(FixtureError.fallbackFailed))

        let dataSource = CompositeTemperatureDataSource(
            primary: StubSource(state: primaryState),
            fallback: StubSource(state: fallbackState)
        )

        let reading = try await dataSource.readTemperatures()
        XCTAssertEqual(reading.source, "iohid")
        XCTAssertEqual(reading.primaryCelsius, 53.4, accuracy: 0.01)
        let primaryCalls = await primaryState.calls()
        let fallbackCalls = await fallbackState.calls()
        XCTAssertEqual(primaryCalls, 1)
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testFallsBackWhenPrimaryFails() async throws {
        let primaryState = SourceState(result: .failure(FixtureError.primaryFailed))
        let fallbackState = SourceState(result: .success(
            PowermetricsTemperatureReading(
                primaryCelsius: 49.1,
                maxCelsius: 57.8,
                sensorCount: 5,
                source: "powermetrics"
            )
        ))

        let dataSource = CompositeTemperatureDataSource(
            primary: StubSource(state: primaryState),
            fallback: StubSource(state: fallbackState)
        )

        let reading = try await dataSource.readTemperatures()
        XCTAssertEqual(reading.source, "powermetrics")
        XCTAssertEqual(reading.maxCelsius, 57.8, accuracy: 0.01)
        let primaryCalls = await primaryState.calls()
        let fallbackCalls = await fallbackState.calls()
        XCTAssertEqual(primaryCalls, 1)
        XCTAssertEqual(fallbackCalls, 1)
    }

    func testReturnsCombinedErrorWhenAllSourcesFail() async {
        let primaryState = SourceState(result: .failure(FixtureError.primaryFailed))
        let fallbackState = SourceState(result: .failure(FixtureError.fallbackFailed))

        let dataSource = CompositeTemperatureDataSource(
            primary: StubSource(state: primaryState),
            fallback: StubSource(state: fallbackState)
        )

        do {
            _ = try await dataSource.readTemperatures()
            XCTFail("Expected all sources to fail")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("all privileged temperature sources failed")
            )
        }
    }
}
