import XCTest
@testable import PulseBarCore

final class PrivilegedTelemetryIPCTests: XCTestCase {
    func testRequestEncodingRoundTrip() throws {
        let request = PrivilegedTemperatureRequest(command: .sample)
        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(PrivilegedTemperatureRequest.self, from: encoded)
        XCTAssertEqual(decoded, request)
    }

    func testResponseSuccessRoundTrip() throws {
        let reading = PowermetricsTemperatureReading(
            primaryCelsius: 51.5,
            maxCelsius: 63.0,
            sensorCount: 12,
            sensors: [
                TemperatureSensorReading(name: "CPU Performance Cores", celsius: 51.5),
                TemperatureSensorReading(name: "Power Manager SOC", celsius: 63.0)
            ]
        )
        let response = PrivilegedTemperatureResponse.success(reading, source: "powermetrics")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PrivilegedTemperatureResponse.self, from: data)

        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.reading, reading)
        XCTAssertEqual(decoded.source, "powermetrics")
        XCTAssertNil(decoded.error)
    }

    func testLegacyReadingPayloadWithoutSensorsDecodes() throws {
        let payload = """
        {
          "primaryCelsius": 44.5,
          "maxCelsius": 48.0,
          "sensorCount": 2,
          "source": "iohid"
        }
        """
        let data = Data(payload.utf8)
        let decoded = try JSONDecoder().decode(PowermetricsTemperatureReading.self, from: data)

        XCTAssertEqual(decoded.primaryCelsius, 44.5, accuracy: 0.001)
        XCTAssertEqual(decoded.maxCelsius, 48.0, accuracy: 0.001)
        XCTAssertEqual(decoded.sensorCount, 2)
        XCTAssertEqual(decoded.source, "iohid")
        XCTAssertTrue(decoded.sensors.isEmpty)
    }

    func testResponseFailureFactory() {
        let response = PrivilegedTemperatureResponse.failure("No data")
        XCTAssertFalse(response.ok)
        XCTAssertNil(response.reading)
        XCTAssertEqual(response.error, "No data")
    }

    func testLegacyResponseWithoutNewDiagnosticFieldsDecodes() throws {
        let payload = """
        {
          "ok": true,
          "source": "iohid",
          "timestamp": "2026-02-18T00:00:00Z",
          "reading": {
            "primaryCelsius": 44.5,
            "maxCelsius": 48.0,
            "sensorCount": 2,
            "source": "iohid"
          }
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PrivilegedTemperatureResponse.self, from: Data(payload.utf8))

        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.source, "iohid")
        XCTAssertTrue(decoded.activeSourceChain.isEmpty)
        XCTAssertTrue(decoded.sourceDiagnostics.isEmpty)
    }

    func testDefaultConnectionConfigBuildsUserScopedPaths() {
        let temporaryDirectory = URL(fileURLWithPath: "/tmp/codex-tests", isDirectory: true)
        let config = PrivilegedHelperConnectionConfig.default(
            temporaryDirectory: temporaryDirectory,
            expectedUID: 501
        )

        XCTAssertEqual(config.runtimeDirectoryPath, "/tmp/codex-tests/PulseBar")
        XCTAssertEqual(config.socketPath, "/tmp/codex-tests/PulseBar/privileged-helper.sock")
        XCTAssertEqual(config.helperLogPath, "/tmp/codex-tests/PulseBar/privileged-helper.log")
        XCTAssertEqual(config.helperPIDPath, "/tmp/codex-tests/PulseBar/privileged-helper.pid")
        XCTAssertEqual(config.expectedUID, 501)
    }
}
