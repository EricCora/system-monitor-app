import Foundation

public actor SamplingEngine {
    private let providers: [any MetricProvider]
    private let store: TimeSeriesStore
    private var intervalSeconds: Double
    private var loopTask: Task<Void, Never>?
    private var onBatch: (@Sendable (SamplingBatch) async -> Void)?

    public init(
        providers: [any MetricProvider],
        store: TimeSeriesStore,
        intervalSeconds: Double = 2.0,
        onBatch: (@Sendable (SamplingBatch) async -> Void)? = nil
    ) {
        self.providers = providers
        self.store = store
        self.intervalSeconds = intervalSeconds
        self.onBatch = onBatch
    }

    public func setOnBatch(_ onBatch: (@Sendable (SamplingBatch) async -> Void)?) {
        self.onBatch = onBatch
    }

    public func start() {
        guard loopTask == nil else { return }

        loopTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    public func sampleNow() async {
        let batch = await collect(at: Date())

        if !batch.samples.isEmpty {
            await store.append(batch.samples)
        }

        if !batch.isEmpty, let onBatch {
            await onBatch(batch)
        }
    }

    public func updateInterval(seconds: Double) async {
        intervalSeconds = min(max(seconds, 1.0), 10.0)
        for provider in providers {
            await provider.updateInterval(seconds: intervalSeconds)
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let tickStart = Date()
            let batch = await collect(at: tickStart)

            if !batch.samples.isEmpty {
                await store.append(batch.samples)
            }

            if !batch.isEmpty, let onBatch {
                await onBatch(batch)
            }

            let elapsed = Date().timeIntervalSince(tickStart)
            let wait = max(0.0, intervalSeconds - elapsed)
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private func collect(at date: Date) async -> SamplingBatch {
        await withTaskGroup(
            of: Result<[MetricSample], ProviderFailure>.self,
            returning: SamplingBatch.self
        ) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return .success(try await provider.sample(at: date))
                    } catch {
                        return .failure(
                            ProviderFailure(
                                providerID: provider.providerID,
                                timestamp: date,
                                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            )
                        )
                    }
                }
            }

            var allSamples: [MetricSample] = []
            var failures: [ProviderFailure] = []

            for await result in group {
                switch result {
                case .success(let providerSamples):
                    allSamples.append(contentsOf: providerSamples)
                case .failure(let failure):
                    failures.append(failure)
                }
            }
            return SamplingBatch(timestamp: date, samples: allSamples, failures: failures)
        }
    }
}

#if DEBUG
public extension SamplingEngine {
    func testCollect(at date: Date) async -> SamplingBatch {
        await collect(at: date)
    }
}
#endif
