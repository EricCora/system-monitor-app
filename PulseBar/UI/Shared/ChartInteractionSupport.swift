import Foundation
import PulseBarCore

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
            return series.min(by: {
                abs($0[keyPath: timestamp].timeIntervalSince(hoveredDate))
                    < abs($1[keyPath: timestamp].timeIntervalSince(hoveredDate))
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
}
