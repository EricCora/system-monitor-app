import Foundation

public actor SamplingEngine {
    private let providers: [any MetricProvider]
    private let store: TimeSeriesStore
    private var intervalSeconds: Double
    private var loopTask: Task<Void, Never>?
    private var onBatch: (@Sendable ([MetricSample]) async -> Void)?

    public init(
        providers: [any MetricProvider],
        store: TimeSeriesStore,
        intervalSeconds: Double = 2.0,
        onBatch: (@Sendable ([MetricSample]) async -> Void)? = nil
    ) {
        self.providers = providers
        self.store = store
        self.intervalSeconds = intervalSeconds
        self.onBatch = onBatch
    }

    public func setOnBatch(_ onBatch: (@Sendable ([MetricSample]) async -> Void)?) {
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

    public func updateInterval(seconds: Double) async {
        intervalSeconds = min(max(seconds, 1.0), 10.0)
        for provider in providers {
            await provider.updateInterval(seconds: intervalSeconds)
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let tickStart = Date()
            let samples = await collect(at: tickStart)

            if !samples.isEmpty {
                await store.append(samples)
                if let onBatch {
                    await onBatch(samples)
                }
            }

            let elapsed = Date().timeIntervalSince(tickStart)
            let wait = max(0.0, intervalSeconds - elapsed)
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private func collect(at date: Date) async -> [MetricSample] {
        await withTaskGroup(of: [MetricSample].self, returning: [MetricSample].self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.sample(at: date)
                    } catch {
                        return []
                    }
                }
            }

            var allSamples: [MetricSample] = []
            for await providerSamples in group {
                allSamples.append(contentsOf: providerSamples)
            }
            return allSamples
        }
    }
}
