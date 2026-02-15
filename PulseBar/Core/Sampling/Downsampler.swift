import Foundation

public enum Downsampler {
    public static func downsample(_ samples: [MetricSample], maxPoints: Int) -> [MetricSample] {
        guard maxPoints > 0, samples.count > maxPoints else {
            return samples
        }

        let bucketSize = Int(ceil(Double(samples.count) / Double(maxPoints)))
        var output: [MetricSample] = []
        output.reserveCapacity(maxPoints)

        var index = 0
        while index < samples.count {
            let end = min(index + bucketSize, samples.count)
            let bucket = samples[index..<end]
            guard let first = bucket.first, let last = bucket.last else {
                index = end
                continue
            }

            let sum = bucket.reduce(0.0) { $0 + $1.value }
            let avg = sum / Double(bucket.count)
            output.append(
                MetricSample(
                    metricID: first.metricID,
                    timestamp: last.timestamp,
                    value: avg,
                    unit: first.unit
                )
            )
            index = end
        }

        return output
    }
}
