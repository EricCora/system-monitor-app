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
}
