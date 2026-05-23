import SwiftUI
import PulseBarCore

struct TemperatureComparePaneContentView: View {
    @Environment(\.detachedPaneStyle) private var paneStyle
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var historiesByRowID: [String: [TemperatureHistoryPoint]] = [:]
    @State private var hoveredDate: Date?
    @State private var viewport = ChartViewport()
    @State private var zoomSelectionRect: CGRect?
    @State private var chartModel = PreparedTimeSeriesChartModel.empty
    @State private var hiddenLegendIDs = Set<String>()

    var body: some View {
        DetachedMetricsPaneShell(
            coordinator: coordinator,
            paneController: paneController,
            historyWindow: $coordinator.selectedTemperatureHistoryWindow,
            hoveredDate: $hoveredDate,
            viewport: $viewport,
            zoomSelectionRect: $zoomSelectionRect,
            sectionAccent: DashboardPalette.temperatureChartAccent,
            header: { paneHeader },
            chart: { chartSection },
            footer: { compareFooter }
        )
        .detachedPaneHistoryRefresh(
            contextRefreshID: contextRefreshID,
            refreshTriggerID: refreshTriggerID,
            isInteractionActive: isInteractionActive,
            onContextChange: {
                hoveredDate = nil
                viewport.reset()
                zoomSelectionRect = nil
                historiesByRowID = [:]
                chartModel = .empty
                hiddenLegendIDs = []
            },
            refresh: { await refreshHistories() }
        )
    }

    private var selectedSensors: [TemperatureAggregateRow] {
        _ = coordinator.temperatureCompareSelectionRevision
        return coordinator.comparedTemperatureRows()
    }

    private var selectedSensorIDs: [String] {
        selectedSensors.map(\.id)
    }

    private var paneHeader: some View {
        DetachedPaneHeaderCard(
            sectionTitle: "Sensor Compare",
            title: selectedSensors.isEmpty ? "Select aggregates to compare" : "\(selectedSensors.count) aggregates",
            subtitle: "Group max, average, and minimum history",
            valueText: selectedSensors.isEmpty ? "--" : "\(selectedSensors.count)/\(coordinator.maxComparedTemperatureSensors)",
            badgeText: paneController.pinnedTarget != nil ? "Pinned" : "Compare",
            accent: DashboardPalette.temperatureAccent
        )
    }

    @ViewBuilder
    private var chartSection: some View {
        if selectedSensors.isEmpty {
            compareEmptyState(
                systemImage: "checklist",
                title: "No sensors selected",
                message: "Enable Compare in the Temperature pane and select up to \(coordinator.maxComparedTemperatureSensors) aggregate rows."
            )
        } else if chartModel.hasRenderableCompareHistory {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DashboardSectionLabel(title: "Combined History", tint: DashboardPalette.secondaryText)
                    Spacer()
                    Text(coordinator.selectedTemperatureHistoryWindow.label)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                DashboardTimeSeriesChart(
                    model: chartModel,
                    window: coordinator.selectedTemperatureHistoryWindow,
                    height: paneStyle.chartHeight,
                    paneController: paneController,
                    hiddenLegendIDs: hiddenLegendIDs,
                    yAxisLabel: { value in
                        String(format: "%.0f C", value)
                    },
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    zoomSelectionRect: $zoomSelectionRect
                )
            }
        } else {
            liveOnlyState
        }
    }

    @ViewBuilder
    private var compareFooter: some View {
        if !selectedSensors.isEmpty {
            HStack(spacing: 8) {
                Button("Clear Selection") {
                    coordinator.clearComparedTemperatureSensors()
                    hoveredDate = nil
                    viewport.reset()
                    zoomSelectionRect = nil
                    historiesByRowID = [:]
                    chartModel = .empty
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 2)

            ChartLegendStrip(items: legendItems, hiddenItemIDs: hiddenLegendIDs) { item in
                ChartInteractionSupport.toggleLegendItem(item.id, hiddenLegendIDs: &hiddenLegendIDs)
            }

            if chartModel.hasRenderableCompareHistory, let hoveredDate {
                HStack {
                    Text(hoveredDate.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Spacer()
                    Text("\(selectedSensors.count) series")
                        .font(.caption.monospacedDigit())
                }
                .font(.caption)
                .frame(height: 18)
            }
        }
    }

    private var liveOnlyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DashboardSectionLabel(title: "Combined History", tint: DashboardPalette.secondaryText)
                Spacer()
                Text(coordinator.selectedTemperatureHistoryWindow.label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            VStack(spacing: 8) {
                Image(systemName: "clock.badge.plus")
                    .font(.title2)
                    .foregroundStyle(DashboardPalette.secondaryText)
                Text("History starts now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DashboardPalette.primaryText)
                Text(coordinator.temperatureHistoryStoreStatusMessage ?? "PulseBar is recording aggregate compare history from this build. Current values are shown below.")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, minHeight: 190)

            ChartLegendStrip(items: legendItems, hiddenItemIDs: hiddenLegendIDs) { item in
                ChartInteractionSupport.toggleLegendItem(item.id, hiddenLegendIDs: &hiddenLegendIDs)
            }
        }
    }

    private var legendItems: [ChartLegendItem] {
        selectedSensors.enumerated().map { index, row in
            ChartLegendItem(
                id: row.id,
                label: row.displayName,
                color: DashboardChartTheme.compareColor(for: index),
                valueText: legendValue(for: row)
            )
        }
    }

    private func compareEmptyState(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(DashboardPalette.secondaryText)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DashboardPalette.primaryText)
            Text(message)
                .font(.caption)
                .foregroundStyle(DashboardPalette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private func legendValue(for row: TemperatureAggregateRow) -> String {
        let point = hoveredPoint(for: row) ?? historiesByRowID[row.id]?.last
        return UnitsFormatter.format(point?.value ?? row.value, unit: .celsius)
    }

    private func hoveredPoint(for row: TemperatureAggregateRow) -> TemperatureHistoryPoint? {
        guard let hoveredDate, let history = historiesByRowID[row.id] else { return nil }
        return TemperatureHistoryHelpers.nearestPoint(to: hoveredDate, in: history)
    }

    private func refreshHistories() async {
        coordinator.performanceDiagnosticsStore.recordDetachedPaneQuery()
        let sensors = selectedSensors
        guard !sensors.isEmpty else {
            historiesByRowID = [:]
            chartModel = .empty
            return
        }

        let start = ContinuousClock.now
        var nextHistories: [String: [TemperatureHistoryPoint]] = [:]
        var descriptors: [ChartMetricSeriesDescriptor<TemperatureHistoryPoint>] = []

        let window = coordinator.selectedTemperatureHistoryWindow
        let maxPoints = DetachedPaneLayout.detachedHistoryMaxPoints(window: window)
        let histories = await withTaskGroup(of: (Int, TemperatureAggregateRow, [TemperatureHistoryPoint]).self) { group in
            for (index, row) in sensors.enumerated() {
                group.addTask {
                    let history = await coordinator.temperatureAggregateHistorySeries(
                        row: row,
                        window: window,
                        maxPoints: maxPoints
                    )
                    return (index, row, history)
                }
            }

            var output: [(Int, TemperatureAggregateRow, [TemperatureHistoryPoint])] = []
            output.reserveCapacity(sensors.count)
            for await result in group {
                output.append(result)
            }
            return output.sorted { $0.0 < $1.0 }
        }

        for (index, row, history) in histories {
            nextHistories[row.id] = history
            descriptors.append(
                ChartMetricSeriesDescriptor(
                    key: row.id,
                    label: row.displayName,
                    color: DashboardChartTheme.compareColor(for: index),
                    samples: history
                )
            )
        }

        historiesByRowID = nextHistories
        chartModel = PreparedTimeSeriesChartModel.fromTemperatureCompare(
            series: descriptors,
            window: window,
            smoothingAlpha: coordinator.chartSmoothingAlpha
        )

        let elapsed = start.duration(to: ContinuousClock.now)
        coordinator.performanceDiagnosticsStore.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }

    private var contextRefreshID: String {
        "\(selectedSensorIDs.joined(separator: ","))-\(coordinator.selectedTemperatureHistoryWindow.rawValue)"
    }

    private var refreshTriggerID: String {
        "\(contextRefreshID)-\(coordinator.temperatureHistoryRevision)-\(coordinator.chartSmoothingAlpha)"
    }

    private var isInteractionActive: Bool {
        ChartInteractionSupport.isChartInteractionActive(hoveredDate: hoveredDate, zoomSelectionRect: zoomSelectionRect)
    }
}
