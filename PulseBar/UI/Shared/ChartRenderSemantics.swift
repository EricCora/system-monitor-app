import Foundation

/// Shared rules for how prepared chart points are grouped before rendering.
enum ChartRenderSemantics {
    static func usesContinuitySegments(for style: DashboardTimeSeriesRenderStyle) -> Bool {
        switch style {
        case .stackedArea:
            return false
        case .baselineAreaLine, .lineOnly:
            return true
        }
    }

    static func continuitySegments(
        for style: DashboardTimeSeriesRenderStyle,
        points: [TimeSeriesChartPoint]
    ) -> [[TimeSeriesChartPoint]] {
        switch style {
        case .stackedArea:
            return Dictionary(grouping: points, by: \.seriesKey)
                .values
                .map { $0.sorted { $0.timestamp < $1.timestamp } }
                .sorted { ($0.first?.seriesKey ?? "") < ($1.first?.seriesKey ?? "") }
        case .baselineAreaLine, .lineOnly:
            return ChartPlotGeometry.groupedSegments(from: points)
        }
    }
}
