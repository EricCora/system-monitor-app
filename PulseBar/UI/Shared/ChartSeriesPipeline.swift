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
        flatten(series: series) { entry in
            segmented(
                sanitize(entry.samples, timestamp: \.timestamp),
                seriesKey: entry.key,
                timestamp: \.timestamp
            ) { sample, continuityKey in
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
    }

    static func metricHistory(
        series: [ChartMetricSeriesDescriptor<MetricHistoryPoint>]
    ) -> [TimeSeriesChartPoint] {
        flatten(series: series) { entry in
            segmented(
                sanitize(entry.samples, timestamp: \.timestamp),
                seriesKey: entry.key,
                timestamp: \.timestamp
            ) { point, continuityKey in
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
        flatten(series: series) { entry in
            segmented(
                sanitize(entry.samples, timestamp: \.timestamp),
                seriesKey: entry.key,
                timestamp: \.timestamp
            ) { point, continuityKey in
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
        smoothingAlpha: Double = 1.0
    ) -> [MetricHistoryPoint] {
        var output = sanitize(points, timestamp: \.timestamp)
        if let maxPoints, maxPoints > 0, output.count > maxPoints {
            output = downsampleHistory(output, maxPoints: maxPoints)
        }
        return lowPass(output, alpha: smoothingAlpha)
    }

    static func prepareTemperatureHistory(
        _ points: [TemperatureHistoryPoint],
        maxPoints: Int? = nil,
        smoothingAlpha: Double = 1.0
    ) -> [TemperatureHistoryPoint] {
        var output = sanitize(points, timestamp: \.timestamp)
        if let maxPoints, maxPoints > 0, output.count > maxPoints {
            output = downsampleTemperature(output, maxPoints: maxPoints)
        }
        return lowPass(output, alpha: smoothingAlpha)
    }

    static func downsample(_ samples: [MetricSample], maxPoints: Int) -> [MetricSample] {
        Downsampler.downsample(samples, maxPoints: maxPoints)
    }

    static func downsampleHistory(_ points: [MetricHistoryPoint], maxPoints: Int) -> [MetricHistoryPoint] {
        guard maxPoints > 0, points.count > maxPoints else { return points }

        let bucketSize = Int(ceil(Double(points.count) / Double(maxPoints)))
        var output: [MetricHistoryPoint] = []
        output.reserveCapacity(maxPoints)

        var index = 0
        while index < points.count {
            let end = min(index + bucketSize, points.count)
            let bucket = points[index..<end]
            guard let first = bucket.first, let last = bucket.last else {
                index = end
                continue
            }
            let average = bucket.reduce(0.0) { $0 + $1.value } / Double(bucket.count)
            output.append(MetricHistoryPoint(timestamp: last.timestamp, value: average, unit: first.unit))
            index = end
        }
        return output
    }

    static func downsampleTemperature(_ points: [TemperatureHistoryPoint], maxPoints: Int) -> [TemperatureHistoryPoint] {
        guard maxPoints > 0, points.count > maxPoints else { return points }

        let bucketSize = Int(ceil(Double(points.count) / Double(maxPoints)))
        var output: [TemperatureHistoryPoint] = []
        output.reserveCapacity(maxPoints)

        var index = 0
        while index < points.count {
            let end = min(index + bucketSize, points.count)
            let bucket = points[index..<end]
            guard let first = bucket.first, let last = bucket.last else {
                index = end
                continue
            }
            let average = bucket.reduce(0.0) { $0 + $1.value } / Double(bucket.count)
            output.append(
                TemperatureHistoryPoint(
                    sensorID: last.sensorID,
                    timestamp: last.timestamp,
                    value: average,
                    channelType: first.channelType
                )
            )
            index = end
        }
        return output
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

        let cadence = inferredCadence(for: values, timestamp: timestamp)
        let gapThreshold = max(cadence * 1.9, cadence + 1)
        var segmentIndex = 0
        var previousTimestamp: Date?

        return values.map { value in
            let currentTimestamp = value[keyPath: timestamp]
            if let previousTimestamp,
               currentTimestamp.timeIntervalSince(previousTimestamp) > gapThreshold {
                segmentIndex += 1
            }
            previousTimestamp = currentTimestamp
            return "\(seriesKey)#\(segmentIndex)"
        }
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
        let deltas = zip(values, values.dropFirst()).compactMap { previous, current -> TimeInterval? in
            let delta = current[keyPath: timestamp].timeIntervalSince(previous[keyPath: timestamp])
            return delta > 0 ? delta : nil
        }
        guard !deltas.isEmpty else { return 1 }
        let sorted = deltas.sorted()
        return sorted[sorted.count / 2]
    }

    private static func normalizedAlpha(_ alpha: Double) -> Double {
        guard alpha.isFinite else { return 1.0 }
        return min(max(alpha, 0.05), 1.0)
    }
}
