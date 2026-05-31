import Foundation

public enum Downsampler {
    public static func downsample(
        _ samples: [MetricSample],
        maxPoints: Int,
        bucketSeconds: Int = 1
    ) -> [MetricSample] {
        guard maxPoints > 0, !samples.isEmpty else {
            return samples
        }

        let effectiveBucketSeconds = widenBucketSeconds(
            initial: bucketSeconds,
            maxPoints: maxPoints
        ) { bucketSeconds in
            bucketSamples(samples, bucketSeconds: bucketSeconds).count
        }
        return bucketSamples(samples, bucketSeconds: effectiveBucketSeconds)
    }

    public static func downsampleHistory(
        _ points: [MetricHistoryPoint],
        maxPoints: Int,
        bucketSeconds: Int = 1
    ) -> [MetricHistoryPoint] {
        guard maxPoints > 0, !points.isEmpty else {
            return points
        }

        let effectiveBucketSeconds = widenBucketSeconds(
            initial: bucketSeconds,
            maxPoints: maxPoints
        ) { bucketSeconds in
            bucketHistory(points, bucketSeconds: bucketSeconds).count
        }
        return bucketHistory(points, bucketSeconds: effectiveBucketSeconds)
    }

    public static func bucketTimestamp(_ timestamp: Date, bucketSeconds: Int) -> Date {
        guard bucketSeconds > 1 else { return timestamp }
        let bucket = TimeInterval(bucketSeconds)
        let aligned = floor(timestamp.timeIntervalSince1970 / bucket) * bucket
        return Date(timeIntervalSince1970: aligned)
    }

    public static func widenBucketSeconds(
        initial: Int,
        maxPoints: Int,
        count: (Int) -> Int
    ) -> Int {
        var effectiveBucketSeconds = max(1, initial)
        while count(effectiveBucketSeconds) > maxPoints {
            effectiveBucketSeconds *= 2
        }
        return effectiveBucketSeconds
    }

    private static func bucketSamples(_ samples: [MetricSample], bucketSeconds: Int) -> [MetricSample] {
        guard !samples.isEmpty else { return [] }

        var buckets: [Int64: (MetricID, MetricUnit, [Double], Date)] = [:]
        for sample in samples {
            let alignedTimestamp = bucketTimestamp(sample.timestamp, bucketSeconds: bucketSeconds)
            let key = Int64(alignedTimestamp.timeIntervalSince1970)
            if var existing = buckets[key] {
                existing.2.append(sample.value)
                buckets[key] = existing
            } else {
                buckets[key] = (sample.metricID, sample.unit, [sample.value], alignedTimestamp)
            }
        }

        return buckets.keys.sorted().map { key in
            let bucket = buckets[key]!
            let average = bucket.2.reduce(0, +) / Double(bucket.2.count)
            return MetricSample(metricID: bucket.0, timestamp: bucket.3, value: average, unit: bucket.1)
        }
    }

    private static func bucketHistory(_ points: [MetricHistoryPoint], bucketSeconds: Int) -> [MetricHistoryPoint] {
        guard !points.isEmpty else { return [] }

        var buckets: [Int64: (MetricUnit, [Double], Date)] = [:]
        for point in points {
            let alignedTimestamp = bucketTimestamp(point.timestamp, bucketSeconds: bucketSeconds)
            let key = Int64(alignedTimestamp.timeIntervalSince1970)
            if var existing = buckets[key] {
                existing.1.append(point.value)
                buckets[key] = existing
            } else {
                buckets[key] = (point.unit, [point.value], alignedTimestamp)
            }
        }

        return buckets.keys.sorted().map { key in
            let bucket = buckets[key]!
            let average = bucket.1.reduce(0, +) / Double(bucket.1.count)
            return MetricHistoryPoint(timestamp: bucket.2, value: average, unit: bucket.0)
        }
    }
}
