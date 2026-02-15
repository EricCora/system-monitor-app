import Foundation

public actor TimeSeriesStore {
    private var buffers: [MetricID: RingBuffer<MetricSample>] = [:]
    private let defaultCapacity: Int

    public init(defaultCapacity: Int = 7200) {
        self.defaultCapacity = max(defaultCapacity, 3600)
    }

    public func append(_ samples: [MetricSample]) {
        for sample in samples {
            if buffers[sample.metricID] == nil {
                buffers[sample.metricID] = RingBuffer(capacity: defaultCapacity)
            }
            buffers[sample.metricID]?.append(sample)
        }
    }

    public func series(for metricID: MetricID, window: TimeWindow) -> [MetricSample] {
        guard let buffer = buffers[metricID] else {
            return []
        }

        let cutoff = Date().addingTimeInterval(-window.seconds)
        return buffer
            .allElementsInOrder()
            .filter { $0.timestamp >= cutoff }
    }

    public func latest(for metricID: MetricID) -> MetricSample? {
        buffers[metricID]?.allElementsInOrder().last
    }

    public func latestByMetric() -> [MetricID: MetricSample] {
        var output: [MetricID: MetricSample] = [:]
        for (metricID, buffer) in buffers {
            if let sample = buffer.allElementsInOrder().last {
                output[metricID] = sample
            }
        }
        return output
    }
}
