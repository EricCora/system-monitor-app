import XCTest
@testable import PulseBarCore

final class FPSProviderTests: XCTestCase {
    func testWindowEstimatorReportsTrailingFramesPerSecond() {
        var estimator = FPSWindowEstimator(windowLength: 1.0)
        estimator.recordFrame(at: 0.10)
        estimator.recordFrame(at: 0.30)
        estimator.recordFrame(at: 0.90)

        XCTAssertEqual(estimator.fps(at: 1.00), 3.0, accuracy: 0.001)
    }

    func testWindowEstimatorPrunesFramesOutsideWindow() {
        var estimator = FPSWindowEstimator(windowLength: 1.0)
        estimator.recordFrame(at: 0.10)
        estimator.recordFrame(at: 0.19)
        estimator.recordFrame(at: 1.10)

        XCTAssertEqual(estimator.fps(at: 1.20), 1.0, accuracy: 0.001)
    }

    func testProviderSampleUsesInjectedReaderAndStatus() async throws {
        let provider = FPSProvider(
            fpsReader: { 47.5 },
            statusReader: { "Using output refresh fallback." }
        )

        let samples = try await provider.sample(at: Date())
        let status = await provider.currentStatusMessage()

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.metricID, .framesPerSecond)
        XCTAssertEqual(samples.first?.value ?? -1, 47.5, accuracy: 0.001)
        XCTAssertEqual(status, "Using output refresh fallback.")
    }

    func testProviderFallsBackWithoutLiveCaptureWhenDisabled() async throws {
        let provider = FPSProvider(
            liveCaptureEnabled: false,
            fallbackReader: { 59.94 }
        )

        let samples = try await provider.sample(at: Date())
        let status = await provider.currentStatusMessage()

        XCTAssertEqual(samples.first?.value ?? -1, 59.94, accuracy: 0.001)
        XCTAssertNil(status)
    }
}
