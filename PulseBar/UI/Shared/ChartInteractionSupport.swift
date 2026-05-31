import Foundation
import PulseBarCore

struct PreparedChartReadout {
    let timestamp: Date
    let valuesBySeriesKey: [String: Double]

    func value(forSeriesKey key: String) -> Double? {
        valuesBySeriesKey[key]
    }
}

enum ChartInteractionSupport {
    static func isChartInteractionActive(hoveredDate: Date?, zoomSelectionRect: CGRect?) -> Bool {
        hoveredDate != nil || zoomSelectionRect != nil
    }

    static func toggleLegendItem(_ id: String, hiddenLegendIDs: inout Set<String>) {
        if hiddenLegendIDs.contains(id) {
            hiddenLegendIDs.remove(id)
        } else {
            hiddenLegendIDs.insert(id)
        }
    }

    static func nearest<T>(
        in series: [T],
        to hoveredDate: Date?,
        timestamp: KeyPath<T, Date>
    ) -> T? {
        guard !series.isEmpty else { return nil }
        if let hoveredDate {
            return series.min(by: { lhs, rhs in
                let lhsDistance = abs(lhs[keyPath: timestamp].timeIntervalSince(hoveredDate))
                let rhsDistance = abs(rhs[keyPath: timestamp].timeIntervalSince(hoveredDate))
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                return lhs[keyPath: timestamp] > rhs[keyPath: timestamp]
            })
        }
        return series.last
    }

    static func nearestPoint(in series: [MetricHistoryPoint], hoveredDate: Date?) -> MetricHistoryPoint? {
        nearest(in: series, to: hoveredDate, timestamp: \.timestamp)
    }

    static func nearestPoint(in series: [MemoryHistoryPoint], hoveredDate: Date?) -> MemoryHistoryPoint? {
        nearest(in: series, to: hoveredDate, timestamp: \.timestamp)
    }

    static func nearestPoint(in series: [MetricSample], hoveredDate: Date?) -> MetricSample? {
        nearest(in: series, to: hoveredDate, timestamp: \.timestamp)
    }

    static func nearestPoint(in series: [TemperatureHistoryPoint], hoveredDate: Date?) -> TemperatureHistoryPoint? {
        nearest(in: series, to: hoveredDate, timestamp: \.timestamp)
    }

    /// Resolves one anchor timestamp for multi-series readouts from prepared chart points.
    static func anchorTimestamp(in points: [TimeSeriesChartPoint], hoveredDate: Date?) -> Date? {
        guard !points.isEmpty else { return nil }
        if let hoveredDate {
            var best: Date?
            var bestDistance = TimeInterval.greatestFiniteMagnitude
            for point in points {
                let timestamp = point.timestamp
                let distance = abs(timestamp.timeIntervalSince(hoveredDate))
                if distance < bestDistance {
                    bestDistance = distance
                    best = timestamp
                } else if distance == bestDistance, let current = best, timestamp > current {
                    best = timestamp
                }
            }
            return best
        }

        var latest = points[0].timestamp
        for point in points.dropFirst() where point.timestamp > latest {
            latest = point.timestamp
        }
        return latest
    }

    /// Reads per-series values nearest to the hover (or latest per series when idle).
    static func preparedReadout(
        in points: [TimeSeriesChartPoint],
        hoveredDate: Date?
    ) -> PreparedChartReadout? {
        guard !points.isEmpty else { return nil }

        var pointsBySeriesKey: [String: [TimeSeriesChartPoint]] = [:]
        for point in points {
            pointsBySeriesKey[point.seriesKey, default: []].append(point)
        }

        var valuesBySeriesKey: [String: Double] = [:]
        for (seriesKey, seriesPoints) in pointsBySeriesKey {
            guard let selected = nearest(in: seriesPoints, to: hoveredDate, timestamp: \.timestamp) else {
                continue
            }
            valuesBySeriesKey[seriesKey] = selected.value
        }
        guard !valuesBySeriesKey.isEmpty else { return nil }

        let timestamp = anchorTimestamp(in: points, hoveredDate: hoveredDate)
            ?? valuesBySeriesKey.keys.compactMap { key in
                pointsBySeriesKey[key]?.map(\.timestamp).max()
            }.max()
            ?? .distantPast

        return PreparedChartReadout(timestamp: timestamp, valuesBySeriesKey: valuesBySeriesKey)
    }
}
