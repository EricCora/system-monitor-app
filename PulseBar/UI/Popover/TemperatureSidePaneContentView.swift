import Charts
import SwiftUI
import PulseBarCore

struct TemperaturePaneContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var sensorHistory: [TemperatureHistoryPoint] = []
    @State private var hoveredHistoryPoint: TemperatureHistoryPoint?
    @State private var hoveringHistoryChart = false
    @State private var viewport = ChartViewport()
    @State private var zoomSelectionRect: CGRect?
    @State private var lastRefreshContextID = ""
    @State private var chartModel: PreparedTemperatureChartModel?
    @State private var deferredRefreshTriggerID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: $coordinator.selectedTemperatureHistoryWindow,
                paneController: paneController,
                style: .detached
            )

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeSensor?.displayName ?? "Select a sensor")
                        .font(.headline)
                        .lineLimit(1)
                    if let activeSensor {
                        Text("\(activeSensor.category.label) • \(activeSensor.channelType == .fanRPM ? "Fan RPM" : "Temperature")")
                            .font(.caption)
                            .foregroundStyle(DashboardPalette.secondaryText)
                    }
                }

                Spacer()

                if paneController.pinnedTarget != nil {
                    Text("Pinned")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                } else {
                    Text("Hover Preview")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }

            HStack(spacing: 8) {
                if viewport.isZoomed {
                    Button("Reset Zoom") {
                        viewport.reset()
                        zoomSelectionRect = nil
                        hoveredHistoryPoint = nil
                    }
                    .buttonStyle(.bordered)
                }

                if paneController.pinnedTarget != nil {
                    Button("Unpin") {
                        paneController.unpin()
                    }
                    .buttonStyle(.bordered)
                }

                if let activeSensor {
                    Button("Hide This Sensor") {
                        coordinator.hideTemperatureSensor(sensorID: activeSensor.id)
                        paneController.reconcileTemperatureSensors(Set(coordinator.visibleSensorChannels().map(\.id)))
                    }
                    .buttonStyle(.bordered)
                }

                if !coordinator.hiddenTemperatureSensorIDs.isEmpty {
                    Button("Show Hidden (\(coordinator.hiddenTemperatureSensorIDs.count))") {
                        coordinator.resetHiddenTemperatureSensors()
                        paneController.reconcileTemperatureSensors(Set(coordinator.visibleSensorChannels().map(\.id)))
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let activeSensor {
                if sensorHistory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title2)
                            .foregroundStyle(DashboardPalette.secondaryText)
                        Text("Collecting \(activeSensor.displayName) history")
                            .font(.subheadline)
                            .foregroundStyle(DashboardPalette.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    let chartModel = chartModel ?? PreparedTemperatureChartModel.empty
                    ZStack(alignment: .topLeading) {
                        Chart(chartModel.points) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                yStart: .value("Baseline", chartModel.scale.renderedAreaBaseline(viewport: viewport)),
                                yEnd: .value("Value", point.value),
                                series: .value("Segment", point.continuityKey)
                            )
                            .foregroundStyle(point.color)
                            .opacity(coordinator.chartAreaOpacity)
                            .interpolationMethod(.linear)

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Value", point.value),
                                series: .value("Segment", point.continuityKey)
                            )
                            .foregroundStyle(point.color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.linear)

                            if let hoveredHistoryPoint {
                                RuleMark(x: .value("Hover", hoveredHistoryPoint.timestamp))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(DashboardPalette.chartRule)
                            }
                        }
                        .chartXScale(domain: viewport.xDomain ?? chartModel.scale.xDomain ?? chartModel.fallbackXDomain)
                        .chartYScale(domain: viewport.yDomain ?? chartModel.scale.yDomain)
                        .frame(height: 260)
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                DetachedChartInteractionOverlay(
                                    proxy: proxy,
                                    geometry: geometry,
                                    paneController: paneController,
                                    hoveredDate: Binding(
                                        get: { hoveredHistoryPoint?.timestamp },
                                        set: { newDate in
                                            hoveringHistoryChart = newDate != nil || zoomSelectionRect != nil
                                            if let newDate {
                                                hoveredHistoryPoint = TemperatureHistoryHelpers.nearestPoint(
                                                    to: newDate,
                                                    in: sensorHistory
                                                )
                                            } else {
                                                hoveredHistoryPoint = nil
                                            }
                                        }
                                    ),
                                    viewport: $viewport,
                                    selectionRect: $zoomSelectionRect
                                )
                            }
                        }
                        .overlay(ChartZoomSelectionOverlay(selectionRect: zoomSelectionRect))
                    }
                    .frame(height: 300)

                    HStack {
                        if let summaryPoint = hoveredHistoryPoint ?? sensorHistory.last {
                            Text(summaryPoint.timestamp.formatted(date: .omitted, time: .standard))
                                .foregroundStyle(DashboardPalette.secondaryText)
                            Spacer()
                            Text(TemperatureHistoryHelpers.valueText(for: activeSensor, value: summaryPoint.value))
                        } else {
                            Text(" ")
                            Spacer()
                            Text(" ")
                        }
                    }
                    .font(.caption)
                    .frame(height: 18)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "thermometer.medium")
                        .font(.title2)
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Text("No sensor selected")
                        .font(.subheadline)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DashboardPalette.sectionFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                )
        )
        .task(id: refreshTriggerID) {
            if lastRefreshContextID != contextRefreshID {
                hoveredHistoryPoint = nil
                hoveringHistoryChart = false
                viewport.reset()
                zoomSelectionRect = nil
                lastRefreshContextID = contextRefreshID
            }
            if isInteractionActive {
                deferredRefreshTriggerID = refreshTriggerID
                return
            }
            await refreshHistory()
        }
        .onChange(of: isInteractionActive) { isActive in
            guard !isActive, deferredRefreshTriggerID != nil else { return }
            deferredRefreshTriggerID = nil
            Task {
                await refreshHistory()
            }
        }
    }

    private var activeSensor: SensorReading? {
        let visibleSensors = coordinator.visibleSensorChannels()

        if case .temperature(let activeSensorID)? = paneController.activeTarget,
           let activeSensor = visibleSensors.first(where: { $0.id == activeSensorID }) {
            return activeSensor
        }

        if !coordinator.selectedTemperatureSensorID.isEmpty,
           let selectedSensor = visibleSensors.first(where: { $0.id == coordinator.selectedTemperatureSensorID }) {
            return selectedSensor
        }

        return visibleSensors.first
    }

    private func refreshHistory() async {
        coordinator.performanceDiagnosticsStore.recordDetachedPaneQuery()
        guard let activeSensor else {
            sensorHistory = []
            chartModel = nil
            return
        }

        let start = ContinuousClock.now
        sensorHistory = await coordinator.temperatureHistorySeries(
            sensorID: activeSensor.id,
            channelType: activeSensor.channelType,
            window: coordinator.selectedTemperatureHistoryWindow,
            maxPoints: 480
        )
        sensorHistory = ChartSeriesPipeline.sanitize(sensorHistory, timestamp: \.timestamp)
        chartModel = PreparedTemperatureChartModel(
            points: ChartSeriesPipeline.temperatureHistory(
                sensorHistory,
                key: activeSensor.id,
                label: activeSensor.displayName,
                color: activeSensor.channelType == .fanRPM ? DashboardPalette.diskAccent : DashboardPalette.temperatureAccent
            ),
            baseline: .dataMin(minimumSpan: 1, paddingFraction: 0.12)
        )
        let elapsed = start.duration(to: ContinuousClock.now)
        coordinator.performanceDiagnosticsStore.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }

    private var contextRefreshID: String {
        let sensorID = activeSensor?.id ?? "none"
        return "\(sensorID)-\(coordinator.selectedTemperatureHistoryWindow.rawValue)"
    }

    private var historyRefreshID: String {
        "\(contextRefreshID)-\(coordinator.temperatureHistoryRevision)"
    }

    private var refreshTriggerID: String {
        historyRefreshID
    }

    private var isInteractionActive: Bool {
        hoveredHistoryPoint != nil || zoomSelectionRect != nil
    }
}

private struct PreparedTemperatureChartModel {
    let points: [TimeSeriesChartPoint]
    let scale: ChartScale
    let fallbackXDomain: ClosedRange<Date>

    init(points: [TimeSeriesChartPoint], baseline: ChartBaselinePolicy) {
        self.points = points
        scale = ChartSeriesPipeline.scale(for: points, baseline: baseline)
        fallbackXDomain = Self.makeXDomain(from: points.map(\.timestamp))
    }

    static let empty = PreparedTemperatureChartModel(points: [], baseline: .dataMin())

    private static func makeXDomain(from dates: [Date]) -> ClosedRange<Date> {
        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? minDate.addingTimeInterval(1)
        if minDate == maxDate {
            return minDate.addingTimeInterval(-30)...maxDate.addingTimeInterval(30)
        }
        return minDate...maxDate
    }
}
