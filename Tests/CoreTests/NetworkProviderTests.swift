import XCTest
@testable import PulseBarCore

final class NetworkProviderTests: XCTestCase {
    func testCounterResetProducesZeroRateInsteadOfUnsignedWraparoundSpike() {
        let rate = NetworkProvider.bytesPerSecond(
            current: 100,
            previous: 1_000,
            elapsed: 1
        )

        XCTAssertEqual(rate, 0)
    }

    func testIncreasingCounterProducesRate() {
        let rate = NetworkProvider.bytesPerSecond(
            current: 2_500,
            previous: 1_000,
            elapsed: 3
        )

        XCTAssertEqual(rate, 500)
    }
}
