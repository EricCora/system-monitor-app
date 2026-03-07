import Foundation
import PulseBarCore

enum ChartSeriesSanitizer {
    static func metricHistory(_ points: [MetricHistoryPoint]) -> [MetricHistoryPoint] {
        var latestByTimestamp: [Date: MetricHistoryPoint] = [:]
        for point in points {
            latestByTimestamp[point.timestamp] = point
        }
        return latestByTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }

    static func temperatureHistory(_ points: [TemperatureHistoryPoint]) -> [TemperatureHistoryPoint] {
        var latestByTimestamp: [Date: TemperatureHistoryPoint] = [:]
        for point in points {
            latestByTimestamp[point.timestamp] = point
        }
        return latestByTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }

    static func memoryHistory(_ points: [MemoryHistoryPoint]) -> [MemoryHistoryPoint] {
        var latestByTimestamp: [Date: MemoryHistoryPoint] = [:]
        for point in points {
            latestByTimestamp[point.timestamp] = point
        }
        return latestByTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }

    static func metricSamples(_ samples: [MetricSample]) -> [MetricSample] {
        var latestByTimestamp: [Date: MetricSample] = [:]
        for sample in samples {
            latestByTimestamp[sample.timestamp] = sample
        }
        return latestByTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }
}
