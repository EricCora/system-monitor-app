import XCTest
@testable import PulseBarCore

private struct StubMetricProvider: MetricProvider {
    let providerID: String
    private let result: Result<[MetricSample], Error>

    init(providerID: String, result: Result<[MetricSample], Error>) {
        self.providerID = providerID
        self.result = result
    }

    func sample(at date: Date) async throws -> [MetricSample] {
        try result.get()
    }
}

private actor SamplingBatchRecorder {
    private(set) var batch: SamplingBatch?

    func record(_ batch: SamplingBatch) {
        self.batch = batch
    }
}

final class SamplingEngineTests: XCTestCase {
    func testCollectRetainsFailuresAlongsideSuccessfulSamples() async {
        let store = TimeSeriesStore(defaultCapacity: 16)
        let date = Date(timeIntervalSince1970: 100)
        let successProvider = StubMetricProvider(
            providerID: "success",
            result: .success([
                MetricSample(metricID: .cpuTotalPercent, timestamp: date, value: 42, unit: .percent)
            ])
        )
        let failureProvider = StubMetricProvider(
            providerID: "failure",
            result: .failure(ProviderError.unavailable("simulated outage"))
        )

        let engine = SamplingEngine(
            providers: [successProvider, failureProvider],
            store: store,
            intervalSeconds: 60
        )

        let batch = await engine.testCollect(at: date)

        XCTAssertEqual(batch.samples.count, 1)
        XCTAssertEqual(batch.failures.count, 1)
        XCTAssertEqual(batch.failures.first?.providerID, "failure")
        XCTAssertEqual(batch.failures.first?.message, "simulated outage")
    }

    func testSampleNowPersistsAndPublishesImmediateBatch() async {
        let store = TimeSeriesStore(defaultCapacity: 16)
        let date = Date(timeIntervalSince1970: 100)
        let provider = StubMetricProvider(
            providerID: "battery",
            result: .success([
                MetricSample(metricID: .batteryPowerWatts, timestamp: date, value: -12.5, unit: .watts)
            ])
        )

        let engine = SamplingEngine(
            providers: [provider],
            store: store,
            intervalSeconds: 60
        )

        let recorder = SamplingBatchRecorder()
        await engine.setOnBatch { batch in
            await recorder.record(batch)
        }

        await engine.sampleNow()

        let latest = await store.latest(for: .batteryPowerWatts)
        XCTAssertEqual(latest?.value, -12.5)
        let publishedBatch = await recorder.batch
        XCTAssertEqual(publishedBatch?.samples.first?.value, -12.5)
    }
}
