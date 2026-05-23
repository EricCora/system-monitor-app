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

    static func nearestPoint(in series: [MetricHistoryPoint], hoveredDate: Date?) -> MetricHistoryPoint? {
        guard !series.isEmpty else { return nil }
        if let hoveredDate {
            return series.min(by: {
                abs($0.timestamp.timeIntervalSince(hoveredDate)) < abs($1.timestamp.timeIntervalSince(hoveredDate))
            })
        }
        return series.last
    }

    static func nearestPoint(in series: [MemoryHistoryPoint], hoveredDate: Date?) -> MemoryHistoryPoint? {
        guard !series.isEmpty else { return nil }
        if let hoveredDate {
            return series.min(by: {
                abs($0.timestamp.timeIntervalSince(hoveredDate)) < abs($1.timestamp.timeIntervalSince(hoveredDate))
            })
        }
        return series.last
    }

    static func nearestPoint(in series: [MetricSample], hoveredDate: Date?) -> MetricSample? {
        guard !series.isEmpty else { return nil }
        if let hoveredDate {
            return series.min(by: {
                abs($0.timestamp.timeIntervalSince(hoveredDate)) < abs($1.timestamp.timeIntervalSince(hoveredDate))
            })
        }
        return series.last
    }
}
