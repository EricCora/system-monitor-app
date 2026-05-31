import Foundation
import PulseBarCore
import SwiftUI

enum ChartSeriesPipeline {
    static func metricSamples(
        _ samples: [MetricSample],
        key: String,
        label: String,
        color: Color
    ) -> [TimeSeriesChartPoint] {
        metricSamples(series: [
            ChartMetricSeriesDescriptor(key: key, label: label, color: color, samples: samples)
        ])
    }

    static func metricSamples(
        series: [ChartMetricSeriesDescriptor<MetricSample>]
    ) -> [TimeSeriesChartPoint] {
        seriesPoints(series: series, timestamp: \.timestamp) { sample, entry, continuityKey in
            TimeSeriesChartPoint(
                timestamp: sample.timestamp,
                value: sample.value,
                seriesKey: entry.key,
                seriesLabel: entry.label,
                continuityKey: continuityKey,
                color: entry.color
            )
        }
    }

    static func metricHistory(
        series: [ChartMetricSeriesDescriptor<MetricHistoryPoint>]
    ) -> [TimeSeriesChartPoint] {
        seriesPoints(series: series, timestamp: \.timestamp) { point, entry, continuityKey in
            TimeSeriesChartPoint(
                timestamp: point.timestamp,
                value: point.value,
                seriesKey: entry.key,
                seriesLabel: entry.label,
                continuityKey: continuityKey,
                color: entry.color
            )
        }
    }

    static func temperatureHistory(
        _ points: [TemperatureHistoryPoint],
        key: String,
        label: String,
        color: Color
    ) -> [TimeSeriesChartPoint] {
        temperatureHistory(series: [
            ChartMetricSeriesDescriptor(key: key, label: label, color: color, samples: points)
        ])
    }

    static func temperatureHistory(
        series: [ChartMetricSeriesDescriptor<TemperatureHistoryPoint>]
    ) -> [TimeSeriesChartPoint] {
        seriesPoints(series: series, timestamp: \.timestamp) { point, entry, continuityKey in
            TimeSeriesChartPoint(
                timestamp: point.timestamp,
                value: point.value,
                seriesKey: entry.key,
                seriesLabel: entry.label,
                continuityKey: continuityKey,
                color: entry.color
            )
        }
    }

    static func compactCPUUsagePoints(renderModel: CompactCPUUsageRenderModel) -> [TimeSeriesChartPoint] {
        var points: [TimeSeriesChartPoint] = []
        for segment in renderModel.segments {
            let segmentIndices = timelineSegmentIndices(for: segment.points.map(\.timestamp))
            for index in segment.points.indices {
                let point = segment.points[index]
                let segmentSuffix = segmentIndices[index]
                points.append(
                    TimeSeriesChartPoint(
                        timestamp: point.timestamp,
                        value: point.systemValue,
                        seriesKey: "cpu.system",
                        seriesLabel: "System",
                        continuityKey: "cpu.system#\(segmentSuffix)",
                        color: DashboardPalette.cpuSystemAccent
                    )
                )
                points.append(
                    TimeSeriesChartPoint(
                        timestamp: point.timestamp,
                        value: point.userValue,
                        seriesKey: "cpu.user",
                        seriesLabel: "User",
                        continuityKey: "cpu.user#\(segmentSuffix)",
                        color: DashboardPalette.cpuUserAccent
                    )
                )
            }
        }
        return points.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.seriesKey < $1.seriesKey
            }
            return $0.timestamp < $1.timestamp
        }
    }

    static func prepareMetricSamples(
        _ samples: [MetricSample],
        maxPoints: Int? = nil,
        smoothingAlpha: Double = 1.0
    ) -> [MetricSample] {
        var output = sanitize(samples, timestamp: \.timestamp)
        if let maxPoints, maxPoints > 0, output.count > maxPoints {
            output = downsample(output, maxPoints: maxPoints)
        }
        return lowPass(output, alpha: smoothingAlpha)
    }

    static func prepareMetricHistory(
        _ points: [MetricHistoryPoint],
        maxPoints: Int? = nil,
        bucketSeconds: Int = 1,
        smoothingAlpha: Double = 1.0
    ) -> [MetricHistoryPoint] {
        let output = sanitize(points, timestamp: \.timestamp)
        let downsampled: [MetricHistoryPoint]
        if let maxPoints, maxPoints > 0, output.count > maxPoints {
            downsampled = downsampleHistory(output, maxPoints: maxPoints, bucketSeconds: bucketSeconds)
        } else {
            downsampled = output
        }
        return lowPass(downsampled, alpha: smoothingAlpha)
    }

    static func prepareCPUUsageHistory(
        userHistory: [MetricHistoryPoint],
        systemHistory: [MetricHistoryPoint],
        maxPoints: Int? = nil,
        bucketSeconds: Int = 1,
        smoothingAlpha: Double = 1.0
    ) -> (user: [MetricHistoryPoint], system: [MetricHistoryPoint]) {
        let user = sanitize(userHistory, timestamp: \.timestamp)
        let system = sanitize(systemHistory, timestamp: \.timestamp)
        var aligned = alignMetricHistoryOnSharedBuckets(
            user: user,
            system: system,
            maxPoints: maxPoints,
            bucketSeconds: bucketSeconds
        )
        aligned.user = lowPass(aligned.user, alpha: smoothingAlpha)
        aligned.system = lowPass(aligned.system, alpha: smoothingAlpha)
        return aligned
    }

    static func prepareTemperatureHistory(
        _ points: [TemperatureHistoryPoint],
        maxPoints: Int? = nil,
        bucketSeconds: Int = 1,
        smoothingAlpha: Double = 1.0
    ) -> [TemperatureHistoryPoint] {
        var output = sanitize(points, timestamp: \.timestamp)
        if let maxPoints, maxPoints > 0, output.count > maxPoints {
            output = downsampleTemperature(output, maxPoints: maxPoints, bucketSeconds: bucketSeconds)
        }
        return lowPass(output, alpha: smoothingAlpha)
    }

    static func downsample(_ samples: [MetricSample], maxPoints: Int) -> [MetricSample] {
        Downsampler.downsample(samples, maxPoints: maxPoints)
    }

    static func downsampleHistory(
        _ points: [MetricHistoryPoint],
        maxPoints: Int,
        bucketSeconds: Int = 1
    ) -> [MetricHistoryPoint] {
        Downsampler.downsampleHistory(points, maxPoints: maxPoints, bucketSeconds: bucketSeconds)
    }

    static func downsampleTemperature(
        _ points: [TemperatureHistoryPoint],
        maxPoints: Int,
        bucketSeconds: Int = 1
    ) -> [TemperatureHistoryPoint] {
        downsampleTemperatureByTime(points, maxPoints: maxPoints, bucketSeconds: bucketSeconds)
    }

    static func targetPointCount(for window: ChartWindow?, budget: ChartSampleBudget) -> Int {
        if let window {
            switch window {
            case .fifteenMinutes: return budget == .compactChart ? 80 : 120
            case .oneHour: return budget == .compactChart ? 100 : 180
            case .sixHours: return budget == .compactChart ? 120 : 240
            case .oneDay: return budget == .compactChart ? 140 : 320
            case .oneWeek: return budget == .compactChart ? 160 : 420
            case .oneMonth: return budget == .compactChart ? 180 : 480
            }
        }

        switch budget {
        case .sparkline, .bidirectionalBars: return 36
        case .menuBarHistory: return 28
        case .menuBarBars: return 18
        case .compactChart: return 120
        case .compareLine, .fullChart: return 480
        }
    }

    static func presentationIndexedPoints(
        values: [Double],
        key: String,
        label: String,
        color: Color,
        maxPoints: Int
    ) -> [TimeSeriesChartPoint] {
        let clamped = Array(values.suffix(max(1, maxPoints)))
        guard !clamped.isEmpty else { return [] }
        return clamped.enumerated().map { index, value in
            TimeSeriesChartPoint(
                timestamp: Date(timeIntervalSince1970: Double(index)),
                value: value,
                seriesKey: key,
                seriesLabel: label,
                continuityKey: "\(key).\(index)",
                color: color
            )
        }
    }

    static func memoryCompositionPoints(
        history: [MemoryHistoryPoint],
        smoothingAlpha: Double = 1.0
    ) -> [TimeSeriesChartPoint] {
        let sanitized = sanitize(history, timestamp: \.timestamp)
        let smoothed = lowPass(sanitized, alpha: smoothingAlpha)
        let continuityKeys = continuityKeys(
            for: smoothed,
            seriesKey: "memory.composition",
            timestamp: \.timestamp
        )

        var output: [TimeSeriesChartPoint] = []
        output.reserveCapacity(smoothed.count * 4)

        for (point, continuityKey) in zip(smoothed, continuityKeys) {
            let total = max(1, point.totalBytes)
            let components: [(String, String, Color, Double)] = [
                ("memory.wired", "Wired", DashboardPalette.networkChartAccent, point.wiredBytes),
                ("memory.active", "Active", DashboardPalette.memoryChartAccent, point.activeBytes),
                ("memory.compressed", "Compressed", DashboardPalette.temperatureChartAccent, point.compressedBytes),
                ("memory.free", "Free", DashboardPalette.tertiaryText.opacity(0.7), point.freeBytes)
            ]
            for (key, label, color, bytes) in components {
                let percent = min(max((bytes / total) * 100, 0), 100)
                output.append(
                    TimeSeriesChartPoint(
                        timestamp: point.timestamp,
                        value: percent,
                        seriesKey: key,
                        seriesLabel: label,
                        continuityKey: continuityKey,
                        color: color
                    )
                )
            }
        }

        return output.sorted { $0.timestamp < $1.timestamp }
    }

    static func sanitize<T>(_ values: [T], timestamp: KeyPath<T, Date>) -> [T] {
        var latestByTimestamp: [Date: T] = [:]
        for value in values {
            latestByTimestamp[value[keyPath: timestamp]] = value
        }
        return latestByTimestamp.values.sorted {
            $0[keyPath: timestamp] < $1[keyPath: timestamp]
        }
    }

    static func lowPass(_ samples: [MetricSample], alpha: Double) -> [MetricSample] {
        let normalizedAlpha = normalizedAlpha(alpha)
        guard normalizedAlpha < 0.999, samples.count > 1 else { return samples }

        var previousByMetric: [MetricID: Double] = [:]
        return samples.map { sample in
            let previous = previousByMetric[sample.metricID] ?? sample.value
            let smoothed = (normalizedAlpha * sample.value) + ((1 - normalizedAlpha) * previous)
            previousByMetric[sample.metricID] = smoothed
            return MetricSample(metricID: sample.metricID, timestamp: sample.timestamp, value: smoothed, unit: sample.unit)
        }
    }

    static func lowPass(_ points: [MetricHistoryPoint], alpha: Double) -> [MetricHistoryPoint] {
        let normalizedAlpha = normalizedAlpha(alpha)
        guard normalizedAlpha < 0.999, points.count > 1 else { return points }

        var previous = points.first?.value ?? 0
        return points.map { point in
            let smoothed = (normalizedAlpha * point.value) + ((1 - normalizedAlpha) * previous)
            previous = smoothed
            return MetricHistoryPoint(timestamp: point.timestamp, value: smoothed, unit: point.unit)
        }
    }

    static func lowPass(_ points: [MemoryHistoryPoint], alpha: Double) -> [MemoryHistoryPoint] {
        let normalizedAlpha = normalizedAlpha(alpha)
        guard normalizedAlpha < 0.999, points.count > 1 else { return points }

        var previous = points[0]
        return points.map { point in
            let smoothed = MemoryHistoryPoint(
                timestamp: point.timestamp,
                appBytes: (normalizedAlpha * point.appBytes) + ((1 - normalizedAlpha) * previous.appBytes),
                wiredBytes: (normalizedAlpha * point.wiredBytes) + ((1 - normalizedAlpha) * previous.wiredBytes),
                activeBytes: (normalizedAlpha * point.activeBytes) + ((1 - normalizedAlpha) * previous.activeBytes),
                compressedBytes: (normalizedAlpha * point.compressedBytes) + ((1 - normalizedAlpha) * previous.compressedBytes),
                cacheBytes: (normalizedAlpha * point.cacheBytes) + ((1 - normalizedAlpha) * previous.cacheBytes),
                freeBytes: (normalizedAlpha * point.freeBytes) + ((1 - normalizedAlpha) * previous.freeBytes),
                totalBytes: (normalizedAlpha * point.totalBytes) + ((1 - normalizedAlpha) * previous.totalBytes),
                pressurePercent: (normalizedAlpha * point.pressurePercent) + ((1 - normalizedAlpha) * previous.pressurePercent)
            )
            previous = smoothed
            return smoothed
        }
    }

    static func lowPass(_ points: [TemperatureHistoryPoint], alpha: Double) -> [TemperatureHistoryPoint] {
        let normalizedAlpha = normalizedAlpha(alpha)
        guard normalizedAlpha < 0.999, points.count > 1 else { return points }

        var previousBySensor: [String: Double] = [:]
        return points.map { point in
            let previous = previousBySensor[point.sensorID] ?? point.value
            let smoothed = (normalizedAlpha * point.value) + ((1 - normalizedAlpha) * previous)
            previousBySensor[point.sensorID] = smoothed
            return TemperatureHistoryPoint(sensorID: point.sensorID, timestamp: point.timestamp, value: smoothed, channelType: point.channelType)
        }
    }

    static func continuityKeys<Sample>(
        for values: [Sample],
        seriesKey: String,
        timestamp: KeyPath<Sample, Date>
    ) -> [String] {
        guard !values.isEmpty else { return [] }

        let segmentIndices = timelineSegmentIndices(
            for: values.map { $0[keyPath: timestamp] }
        )

        return segmentIndices.map { "\(seriesKey)#\($0)" }
    }

    /// Assigns a shared segment index per timestamp so stacked charts break all series at the same gap.
    static func timelineSegmentIndices(for timestamps: [Date]) -> [Int] {
        guard !timestamps.isEmpty else { return [] }

        let sortedUnique = Array(Set(timestamps)).sorted()
        let cadence = inferredCadence(for: sortedUnique)
        let gapThreshold = gapThreshold(forCadence: cadence)

        var segmentIndex = 0
        var previousTimestamp: Date?
        var indexByTimestamp: [Date: Int] = [:]

        for timestamp in sortedUnique {
            if let previousTimestamp,
               timestamp.timeIntervalSince(previousTimestamp) > gapThreshold {
                segmentIndex += 1
            }
            indexByTimestamp[timestamp] = segmentIndex
            previousTimestamp = timestamp
        }

        return timestamps.map { indexByTimestamp[$0] ?? 0 }
    }

    private static func inferredCadence(for timestamps: [Date]) -> TimeInterval {
        let deltas = zip(timestamps, timestamps.dropFirst()).compactMap { previous, current -> TimeInterval? in
            let delta = current.timeIntervalSince(previous)
            return delta > 0 ? delta : nil
        }
        guard !deltas.isEmpty else { return 1 }
        let sorted = deltas.sorted()
        return sorted[sorted.count / 2]
    }

    private static func gapThreshold(forCadence cadence: TimeInterval) -> TimeInterval {
        max(cadence * 1.9, cadence + 1)
    }

    static func scale(
        for points: [TimeSeriesChartPoint],
        baseline: ChartBaselinePolicy
    ) -> ChartScale {
        switch baseline {
        case .fixed(let range):
            return ChartScale(
                xDomain: xDomain(for: points),
                yDomain: range,
                areaBaseline: range.lowerBound
            )
        case .zero(let minimumSpan, let paddingFraction):
            let domain = paddedDomain(
                for: points.map(\.value),
                minimumSpan: minimumSpan,
                paddingFraction: paddingFraction,
                includeZero: true
            )
            return ChartScale(
                xDomain: xDomain(for: points),
                yDomain: domain,
                areaBaseline: 0
            )
        case .dataMin(let minimumSpan, let paddingFraction):
            let domain = paddedDomain(
                for: points.map(\.value),
                minimumSpan: minimumSpan,
                paddingFraction: paddingFraction,
                includeZero: false
            )
            return ChartScale(
                xDomain: xDomain(for: points),
                yDomain: domain,
                areaBaseline: domain.lowerBound
            )
        }
    }

    static func colorScaleDomain(for points: [TimeSeriesChartPoint]) -> [String] {
        orderedSeriesValues(for: points, value: \.seriesKey)
    }

    static func colorScaleRange(for points: [TimeSeriesChartPoint]) -> [Color] {
        var colors: [Color] = []
        var seen = Set<String>()
        for point in points {
            if seen.insert(point.seriesKey).inserted {
                colors.append(point.color)
            }
        }
        return colors
    }

    private static func seriesPoints<Sample>(
        series: [ChartMetricSeriesDescriptor<Sample>],
        timestamp: KeyPath<Sample, Date>,
        map: (Sample, ChartMetricSeriesDescriptor<Sample>, String) -> TimeSeriesChartPoint
    ) -> [TimeSeriesChartPoint] {
        flatten(series: series) { entry in
            segmented(
                sanitize(entry.samples, timestamp: timestamp),
                seriesKey: entry.key,
                timestamp: timestamp
            ) { sample, continuityKey in
                map(sample, entry, continuityKey)
            }
        }
    }

    private static func alignMetricHistoryOnSharedBuckets(
        user: [MetricHistoryPoint],
        system: [MetricHistoryPoint],
        maxPoints: Int?,
        bucketSeconds: Int
    ) -> (user: [MetricHistoryPoint], system: [MetricHistoryPoint]) {
        struct Bucket {
            var userValues: [Double] = []
            var systemValues: [Double] = []
            var unit: MetricUnit = .percent
            var timestamp: Date = .distantPast
        }

        var buckets: [Int64: Bucket] = [:]

        for point in user {
            let alignedTimestamp = Downsampler.bucketTimestamp(point.timestamp, bucketSeconds: bucketSeconds)
            let key = Int64(alignedTimestamp.timeIntervalSince1970)
            var bucket = buckets[key] ?? Bucket(unit: point.unit, timestamp: alignedTimestamp)
            bucket.userValues.append(point.value)
            bucket.unit = point.unit
            buckets[key] = bucket
        }

        for point in system {
            let alignedTimestamp = Downsampler.bucketTimestamp(point.timestamp, bucketSeconds: bucketSeconds)
            let key = Int64(alignedTimestamp.timeIntervalSince1970)
            var bucket = buckets[key] ?? Bucket(unit: point.unit, timestamp: alignedTimestamp)
            bucket.systemValues.append(point.value)
            bucket.unit = point.unit
            buckets[key] = bucket
        }

        var userOutput: [MetricHistoryPoint] = []
        var systemOutput: [MetricHistoryPoint] = []
        userOutput.reserveCapacity(buckets.count)
        systemOutput.reserveCapacity(buckets.count)

        for key in buckets.keys.sorted() {
            let bucket = buckets[key]!
            let userAverage = bucket.userValues.isEmpty
                ? 0
                : bucket.userValues.reduce(0, +) / Double(bucket.userValues.count)
            let systemAverage = bucket.systemValues.isEmpty
                ? 0
                : bucket.systemValues.reduce(0, +) / Double(bucket.systemValues.count)
            userOutput.append(MetricHistoryPoint(timestamp: bucket.timestamp, value: userAverage, unit: bucket.unit))
            systemOutput.append(MetricHistoryPoint(timestamp: bucket.timestamp, value: systemAverage, unit: bucket.unit))
        }

        guard let maxPoints, maxPoints > 0, userOutput.count > maxPoints else {
            return (userOutput, systemOutput)
        }

        let effectiveBucketSeconds = Downsampler.widenBucketSeconds(
            initial: bucketSeconds,
            maxPoints: maxPoints
        ) { seconds in
            alignMetricHistoryOnSharedBuckets(
                user: user,
                system: system,
                maxPoints: nil,
                bucketSeconds: seconds
            ).user.count
        }
        return alignMetricHistoryOnSharedBuckets(
            user: user,
            system: system,
            maxPoints: nil,
            bucketSeconds: effectiveBucketSeconds
        )
    }

    private static func downsampleTemperatureByTime(
        _ points: [TemperatureHistoryPoint],
        maxPoints: Int,
        bucketSeconds: Int
    ) -> [TemperatureHistoryPoint] {
        guard maxPoints > 0, !points.isEmpty else { return points }

        let effectiveBucketSeconds = Downsampler.widenBucketSeconds(
            initial: bucketSeconds,
            maxPoints: maxPoints
        ) { seconds in
            bucketTemperature(points, bucketSeconds: seconds).count
        }
        return bucketTemperature(points, bucketSeconds: effectiveBucketSeconds)
    }

    private static func bucketTemperature(
        _ points: [TemperatureHistoryPoint],
        bucketSeconds: Int
    ) -> [TemperatureHistoryPoint] {
        var buckets: [Int64: (sensorID: String, channelType: SensorChannelType, values: [Double], timestamp: Date)] = [:]
        for point in points {
            let alignedTimestamp = Downsampler.bucketTimestamp(point.timestamp, bucketSeconds: bucketSeconds)
            let key = Int64(alignedTimestamp.timeIntervalSince1970)
            if var existing = buckets[key] {
                existing.values.append(point.value)
                buckets[key] = existing
            } else {
                buckets[key] = (
                    sensorID: point.sensorID,
                    channelType: point.channelType,
                    values: [point.value],
                    timestamp: alignedTimestamp
                )
            }
        }

        return buckets.keys.sorted().map { key in
            let bucket = buckets[key]!
            let average = bucket.values.reduce(0, +) / Double(bucket.values.count)
            return TemperatureHistoryPoint(
                sensorID: bucket.sensorID,
                timestamp: bucket.timestamp,
                value: average,
                channelType: bucket.channelType
            )
        }
    }

    private static func flatten<Input>(
        series: [Input],
        transform: (Input) -> [TimeSeriesChartPoint]
    ) -> [TimeSeriesChartPoint] {
        series
            .flatMap(transform)
            .sorted {
                if $0.timestamp == $1.timestamp {
                    return $0.seriesKey < $1.seriesKey
                }
                return $0.timestamp < $1.timestamp
            }
    }

    private static func orderedSeriesValues<Value: Hashable>(
        for points: [TimeSeriesChartPoint],
        value: KeyPath<TimeSeriesChartPoint, Value>
    ) -> [Value] {
        var output: [Value] = []
        var seen = Set<Value>()
        for point in points {
            let item = point[keyPath: value]
            if seen.insert(item).inserted {
                output.append(item)
            }
        }
        return output
    }

    private static func segmented<Sample>(
        _ values: [Sample],
        seriesKey: String,
        timestamp: KeyPath<Sample, Date>,
        map: (Sample, String) -> TimeSeriesChartPoint
    ) -> [TimeSeriesChartPoint] {
        guard !values.isEmpty else { return [] }
        let continuityKeys = continuityKeys(for: values, seriesKey: seriesKey, timestamp: timestamp)
        return zip(values, continuityKeys).map(map)
    }

    private static func paddedDomain(
        for values: [Double],
        minimumSpan: Double,
        paddingFraction: Double,
        includeZero: Bool
    ) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        let lowerBound: Double
        let upperBound: Double

        if minValue == maxValue {
            let delta = max(minimumSpan, abs(minValue * 0.1))
            lowerBound = minValue - delta
            upperBound = maxValue + delta
        } else {
            let padding = max(minimumSpan * 0.1, (maxValue - minValue) * paddingFraction)
            lowerBound = minValue - padding
            upperBound = maxValue + padding
        }

        if includeZero {
            return min(0, lowerBound)...max(upperBound, minimumSpan)
        }
        return lowerBound...upperBound
    }

    private static func xDomain(for points: [TimeSeriesChartPoint]) -> ClosedRange<Date>? {
        guard let minDate = points.map(\.timestamp).min(),
              let maxDate = points.map(\.timestamp).max() else {
            return nil
        }
        if minDate == maxDate {
            let expanded = minDate.addingTimeInterval(-30)...maxDate.addingTimeInterval(30)
            return expanded
        }
        return minDate...maxDate
    }

    private static func inferredCadence<Sample>(
        for values: [Sample],
        timestamp: KeyPath<Sample, Date>
    ) -> TimeInterval {
        inferredCadence(for: values.map { $0[keyPath: timestamp] })
    }

    private static func normalizedAlpha(_ alpha: Double) -> Double {
        guard alpha.isFinite else { return 1.0 }
        return min(max(alpha, 0.05), 1.0)
    }
}
