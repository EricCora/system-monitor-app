import SwiftUI
import PulseBarCore

/// Standard detached-pane chart block: section label, empty state, or full chart at pane height.
struct DetachedPaneChartSection: View {
    @Environment(\.detachedPaneStyle) private var paneStyle

    let historyTitle: String
    var titleTint: Color = DashboardPalette.secondaryText
    let emptyMessage: String
    let model: PreparedTimeSeriesChartModel
    var window: ChartWindow?
    var throughputUnit: ThroughputDisplayUnit = .bytesPerSecond
    @ObservedObject var paneController: DetachedMetricsPaneController
    var hiddenLegendIDs: Set<String> = []
    var yAxisValues: [Double]?
    var yAxisLabel: ((Double) -> String)?
    @Binding var hoveredDate: Date?
    @Binding var viewport: ChartViewport
    @Binding var zoomSelectionRect: CGRect?

    var body: some View {
        DashboardSectionLabel(title: historyTitle, tint: titleTint)

        if model.isEmpty {
            DetachedPaneEmptyChartState(
                message: emptyMessage,
                minHeight: paneStyle.emptyChartMinHeight
            )
        } else {
            DashboardTimeSeriesChart(
                model: model,
                window: window,
                height: paneStyle.chartHeight,
                throughputUnit: throughputUnit,
                paneController: paneController,
                hiddenLegendIDs: hiddenLegendIDs,
                yAxisValues: yAxisValues,
                yAxisLabel: yAxisLabel,
                hoveredDate: $hoveredDate,
                viewport: $viewport,
                zoomSelectionRect: $zoomSelectionRect
            )
        }
    }
}

enum DetachedPaneSummaryRow {
    @ViewBuilder
    static func placeholder() -> some View {
        HStack {
            Text(" ")
            Spacer()
            Text(" ")
        }
    }

    static func captionRow(timestamp: Date, detail: String) -> some View {
        HStack {
            Text(timestamp.formatted(date: .omitted, time: .standard))
                .foregroundStyle(DashboardPalette.secondaryText)
            Spacer()
            Text(detail)
                .font(.caption.monospacedDigit())
        }
    }
}
