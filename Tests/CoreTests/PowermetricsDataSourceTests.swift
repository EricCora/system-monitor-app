import XCTest
@testable import PulseBarCore

final class PowermetricsDataSourceTests: XCTestCase {
    private actor RunnerState {
        struct Reply {
            let output: String
            let error: Error?
        }

        private(set) var calls: [[String]] = []
        private var repliesByArguments: [String: Reply]

        init(repliesByArguments: [String: Reply]) {
            self.repliesByArguments = repliesByArguments
        }

        func run(arguments: [String]) throws -> String {
            calls.append(arguments)
            let key = arguments.joined(separator: " ")
            guard let reply = repliesByArguments[key] else {
                throw ProviderError.unavailable("unexpected arguments: \(key)")
            }
            if let error = reply.error {
                throw error
            }
            return reply.output
        }

        func capturedCalls() -> [[String]] {
            calls
        }
    }

    private struct MockRunner: PrivilegedCommandRunner {
        let state: RunnerState

        func run(command: String, arguments: [String], timeoutSeconds: TimeInterval) async throws -> String {
            XCTAssertEqual(command, "/usr/bin/powermetrics")
            return try await state.run(arguments: arguments)
        }
    }

    func testFallsBackFromPowerSamplersToThermalWhenPowerOutputHasNoCelsius() async throws {
        let help = """
        The following samplers are supported by --samplers:

            cpu_power
            gpu_power
            ane_power
            thermal
        """

        let state = RunnerState(repliesByArguments: [
            "--help": .init(output: help, error: nil),
            "--samplers cpu_power,gpu_power,ane_power -n 1 -i 1000": .init(
                output: "power summary without temperature lines",
                error: nil
            ),
            "--samplers cpu_power,gpu_power -n 1 -i 1000": .init(
                output: "still no temperature lines",
                error: nil
            ),
            "--samplers cpu_power -n 1 -i 1000": .init(
                output: "no celsius yet",
                error: nil
            ),
            "--samplers thermal -n 1 -i 1000": .init(
                output: "CPU die temperature: 56.25 C\nGPU die temperature: 53.00 C",
                error: nil
            )
        ])

        let dataSource = PowermetricsTemperatureDataSource(
            runner: MockRunner(state: state)
        )
        let reading = try await dataSource.readTemperatures()

        XCTAssertEqual(reading.primaryCelsius, 56.25, accuracy: 0.01)
        XCTAssertEqual(reading.maxCelsius, 56.25, accuracy: 0.01)

        let calls = await state.capturedCalls()
        XCTAssertEqual(calls.first, ["--help"])
        XCTAssertEqual(calls.last, ["--samplers", "thermal", "-n", "1", "-i", "1000"])
    }

    func testStopsImmediatelyOnPermissionError() async {
        let help = """
        The following samplers are supported by --samplers:

            cpu_power
            thermal
        """

        let state = RunnerState(repliesByArguments: [
            "--help": .init(output: help, error: nil),
            "--samplers cpu_power -n 1 -i 1000": .init(
                output: "",
                error: ProviderError.unavailable("powermetrics requires superuser privileges")
            ),
            "--samplers thermal -n 1 -i 1000": .init(
                output: "CPU die temperature: 51.00 C",
                error: nil
            )
        ])

        let dataSource = PowermetricsTemperatureDataSource(
            runner: MockRunner(state: state)
        )

        do {
            _ = try await dataSource.readTemperatures()
            XCTFail("Expected permission error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("superuser"))
        }

        let calls = await state.capturedCalls()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0], ["--help"])
        XCTAssertEqual(calls[1], ["--samplers", "cpu_power", "-n", "1", "-i", "1000"])
    }
}
