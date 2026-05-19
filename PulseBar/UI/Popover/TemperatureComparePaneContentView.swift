import Charts
import SwiftUI
import PulseBarCore

struct TemperatureComparePaneContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var historiesByRowID: [String: [TemperatureHistoryPoint]] = [:]
    @State private var hoveredDate: Date?
    @State private var viewport = ChartViewport()
    @State private var zoomSelectionRect: CGRect?
    @State private var lastRefreshContextID = ""
    @State private var chartModel: PreparedTemperatureCompareChartModel?
    @State private var deferredRefreshTriggerID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: $coordinator.selectedTemperatureHistoryWindow,
                paneController: paneController,
                style: .detached
            )

            paneHeader
            toolbar

            if selectedSensors.isEmpty {
                emptyState(
                    systemImage: "checklist",
                    title: "No sensors selected",
                    message: "Enable Compare in the Temperature pane and select up to \(coordinator.maxComparedTemperatureSensors) aggregate rows."
                )
            } else if (chartModel?.points ?? []).isEmpty {
                emptyState(
                    systemImage: "chart.xyaxis.line",
                    title: "Collecting comparison history",
                    message: coordinator.temperatureHistoryStoreStatusMessage ?? "Selected sensors will appear together once history is available."
                )
            } else {
                compareChart
            }
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .dashboardSurface(padding: 14, cornerRadius: 18)
        .animation(.easeInOut(duration: 0.18), value: selectedSensorIDs)
        .task(id: refreshTriggerID) {
            if lastRefreshContextID != contextRefreshID {
                hoveredDate = nil
                viewport.reset()
                zoomSelectionRect = nil
                historiesByRowID = [:]
                chartModel = nil
                lastRefreshContextID = contextRefreshID
            }
            if isInteractionActive {
                deferredRefreshTriggerID = refreshTriggerID
                return
            }
            await refreshHistories()
        }
        .onChange(of: isInteractionActive) { isActive in
            guard !isActive, deferredRefreshTriggerID != nil else { return }
            deferredRefreshTriggerID = nil
            Task {
                await refreshHistories()
            }
        }
    }

    private var selectedSensors: [TemperatureAggregateRow] {
        coordinator.comparedTemperatureRows()
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

    private var toolbar: some View {
        HStack(spacing: 8) {
            if viewport.isZoomed {
                Button("Reset Zoom") {
                    viewport.reset()
                    zoomSelectionRect = nil
                    hoveredDate = nil
                }
                .buttonStyle(.bordered)
            }

            if paneController.pinnedTarget != nil {
                Button("Unpin") {
                    paneController.unpin()
                }
                .buttonStyle(.bordered)
            }

            if !selectedSensors.isEmpty {
                Button("Clear") {
                    coordinator.clearComparedTemperatureSensors()
                    hoveredDate = nil
                    viewport.reset()
                    zoomSelectionRect = nil
                    historiesByRowID = [:]
                    chartModel = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.bottom, 2)
    }

    private var compareChart: some View {
        let chartModel = chartModel ?? .empty

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                DashboardSectionLabel(title: "Combined History", tint: DashboardPalette.secondaryText)
                Spacer()
                Text(coordinator.selectedTemperatureHistoryWindow.label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            ZStack(alignment: .topLeading) {
                Chart(chartModel.points) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Temperature", point.value),
                        series: .value("Segment", point.continuityKey)
                    )
                    .foregroundStyle(point.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)

                    if let hoveredDate {
                        RuleMark(x: .value("Hover", hoveredDate))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(DashboardPalette.chartRule)
                    }
                }
                .chartXScale(domain: viewport.xDomain ?? chartModel.scale.xDomain ?? chartModel.fallbackXDomain)
                .chartYScale(domain: viewport.yDomain ?? chartModel.scale.yDomain)
                .chartYAxis {
                    DashboardChartStyle.leadingNumericAxis { value in
                        String(format: "%.0f C", value)
                    }
                }
                .chartXAxis {
                    DashboardChartStyle.timeXAxis()
                }
                .chartPlotStyle { plot in
                    plot
                        .background(DashboardPalette.chartPlotBackground(cornerRadius: 14))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(height: 270)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        let plotFrame = geometry[proxy.plotAreaFrame]

                        ZStack(alignment: .topLeading) {
                            DetachedChartInteractionOverlay(
                                proxy: proxy,
                                geometry: geometry,
                                paneController: paneController,
                                hoveredDate: $hoveredDate,
                                viewport: $viewport,
                                selectionRect: $zoomSelectionRect
                            )

                            ChartZoomSelectionOverlay(
                                selectionRect: zoomSelectionRect,
                                plotFrame: plotFrame,
                                cornerRadius: 14
                            )
                        }
                    }
                }
            }

            legend
        }
        .padding(12)
        .dashboardInset(cornerRadius: 16)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(selectedSensors.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 8) {
                    Circle()
                        .fill(compareColor(for: index))
                        .frame(width: 8, height: 8)

                    Text(row.displayName)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(legendValue(for: row))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .frame(minWidth: 58, alignment: .trailing)
                }
            }
        }
        .padding(.top, 2)
    }

    private func emptyState(systemImage: String, title: String, message: String) -> some View {
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
        .frame(maxWidth: .infinity, minHeight: 300)
        .dashboardInset(cornerRadius: 16)
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
            chartModel = nil
            return
        }

        let start = ContinuousClock.now
        var nextHistories: [String: [TemperatureHistoryPoint]] = [:]
        var descriptors: [ChartMetricSeriesDescriptor<TemperatureHistoryPoint>] = []

        for (index, row) in sensors.enumerated() {
            let history = await coordinator.temperatureAggregateHistorySeries(
                rowID: row.id,
                window: coordinator.selectedTemperatureHistoryWindow,
                maxPoints: 480
            )
            let sanitized = ChartSeriesPipeline.sanitize(history, timestamp: \.timestamp)
            nextHistories[row.id] = sanitized
            descriptors.append(
                ChartMetricSeriesDescriptor(
                    key: row.id,
                    label: row.displayName,
                    color: compareColor(for: index),
                    samples: sanitized
                )
            )
        }

        historiesByRowID = nextHistories
        chartModel = PreparedTemperatureCompareChartModel(series: descriptors)

        let elapsed = start.duration(to: ContinuousClock.now)
        coordinator.performanceDiagnosticsStore.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }

    private var contextRefreshID: String {
        "\(selectedSensorIDs.joined(separator: ","))-\(coordinator.selectedTemperatureHistoryWindow.rawValue)"
    }

    private var refreshTriggerID: String {
        "\(contextRefreshID)-\(coordinator.temperatureHistoryRevision)"
    }

    private var isInteractionActive: Bool {
        hoveredDate != nil || zoomSelectionRect != nil
    }

    private func compareColor(for index: Int) -> Color {
        Self.compareColors[index % Self.compareColors.count]
    }

    private static let compareColors: [Color] = [
        DashboardPalette.temperatureAccent,
        DashboardPalette.cpuAccent,
        DashboardPalette.memoryAccent,
        DashboardPalette.diskAccent,
        DashboardPalette.networkAccent,
        DashboardPalette.success
    ]
}

private struct PreparedTemperatureCompareChartModel {
    let points: [TimeSeriesChartPoint]
    let scale: ChartScale
    let fallbackXDomain: ClosedRange<Date>

    init(series: [ChartMetricSeriesDescriptor<TemperatureHistoryPoint>]) {
        points = ChartSeriesPipeline.temperatureHistory(series: series)
        scale = ChartSeriesPipeline.scale(for: points, baseline: .dataMin(minimumSpan: 1, paddingFraction: 0.12))
        fallbackXDomain = Self.makeXDomain(from: points.map(\.timestamp))
    }

    static let empty = PreparedTemperatureCompareChartModel(series: [])

    private static func makeXDomain(from dates: [Date]) -> ClosedRange<Date> {
        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? minDate.addingTimeInterval(1)
        if minDate == maxDate {
            return minDate.addingTimeInterval(-30)...maxDate.addingTimeInterval(30)
        }
        return minDate...maxDate
    }
}
