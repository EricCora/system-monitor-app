import XCTest
@testable import PulseBarCore

final class CPUProviderTests: XCTestCase {
    func testSampleIncludesLoadAverages() async throws {
        let provider = CPUProvider()
        let samples = try await provider.sample(at: Date())

        XCTAssertTrue(samples.contains(where: { $0.metricID == .cpuLoadAverage1 }))
        XCTAssertTrue(samples.contains(where: { $0.metricID == .cpuLoadAverage5 }))
        XCTAssertTrue(samples.contains(where: { $0.metricID == .cpuLoadAverage15 }))
    }

    func testSubsequentSampleIncludesUserSystemIdleAndUptime() async throws {
        let provider = CPUProvider()
        _ = try await provider.sample(at: Date())
        let samples = try await provider.sample(at: Date().addingTimeInterval(1))

        XCTAssertTrue(samples.contains(where: { $0.metricID == .cpuUserPercent }))
        XCTAssertTrue(samples.contains(where: { $0.metricID == .cpuSystemPercent }))
        XCTAssertTrue(samples.contains(where: { $0.metricID == .cpuIdlePercent }))
        XCTAssertTrue(samples.contains(where: { $0.metricID == .uptimeSeconds }))

        let user = samples.first(where: { $0.metricID == .cpuUserPercent })?.value ?? -1
        let system = samples.first(where: { $0.metricID == .cpuSystemPercent })?.value ?? -1
        let idle = samples.first(where: { $0.metricID == .cpuIdlePercent })?.value ?? -1

        XCTAssertGreaterThanOrEqual(user, 0)
        XCTAssertGreaterThanOrEqual(system, 0)
        XCTAssertGreaterThanOrEqual(idle, 0)
        XCTAssertLessThanOrEqual(user + system + idle, 100.5)
    }
}
