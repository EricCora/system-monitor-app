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

            paneHeader

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
            .padding(.bottom, 2)

            if let activeSensor {
                if sensorHistory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title2)
                            .foregroundStyle(DashboardPalette.secondaryText)
                        Text(historyEmptyStateText(for: activeSensor))
                            .font(.subheadline)
                            .foregroundStyle(DashboardPalette.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .dashboardInset(cornerRadius: 16)
                } else {
                    let chartModel = chartModel ?? PreparedTemperatureChartModel.empty
                    VStack(alignment: .leading, spacing: 10) {
                        DashboardSectionLabel(title: "Sensor History", tint: DashboardPalette.secondaryText)

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
                            .chartYAxis {
                                DashboardChartStyle.leadingNumericAxis { value in
                                    axisLabel(for: value, sensor: activeSensor)
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
                            .frame(height: 260)
                            .chartOverlay { proxy in
                                GeometryReader { geometry in
                                    let plotFrame = geometry[proxy.plotAreaFrame]

                                    ZStack(alignment: .topLeading) {
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

                                        ChartZoomSelectionOverlay(
                                            selectionRect: zoomSelectionRect,
                                            plotFrame: plotFrame,
                                            cornerRadius: 14
                                        )
                                    }
                                }
                            }
                        }

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
                    .padding(12)
                    .dashboardInset(cornerRadius: 16)
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
                .dashboardInset(cornerRadius: 16)
            }
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .dashboardSurface(padding: 14, cornerRadius: 18)
        .animation(.easeInOut(duration: 0.18), value: activeSensor?.id)
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

    private var paneHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                DashboardSectionLabel(title: "Temperature Detail", tint: DashboardPalette.temperatureAccent)
                Text(activeSensor?.displayName ?? "Select a sensor")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)

                if let activeSensor {
                    Text("\(activeSensor.category.label) • \(activeSensor.channelType == .fanRPM ? "Fan RPM" : "Temperature")")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(activeSensor.map { TemperatureHistoryHelpers.valueText(for: $0) } ?? "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)

                Text(paneController.pinnedTarget != nil ? "Pinned" : "Hover Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DashboardPalette.insetFill)
                    )
            }
        }
        .padding(12)
        .dashboardInset(cornerRadius: 16)
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

    private func historyEmptyStateText(for sensor: SensorReading) -> String {
        coordinator.temperatureHistoryStoreStatusMessage ?? "Collecting \(sensor.displayName) history"
    }

    private func axisLabel(for value: Double, sensor: SensorReading) -> String {
        switch sensor.channelType {
        case .temperatureCelsius:
            return String(format: "%.0f C", value)
        case .fanRPM:
            return "\(Int(value.rounded())) rpm"
        }
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
