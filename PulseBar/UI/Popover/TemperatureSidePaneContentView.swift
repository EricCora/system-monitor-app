import SwiftUI
import PulseBarCore

struct TemperaturePaneContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var sensorHistory: [TemperatureHistoryPoint] = []
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
            paneStyle: DetachedPaneLayout.temperaturePane,
            sectionAccent: DashboardPalette.temperatureChartAccent,
            header: { paneHeader },
            chart: { chartSection },
            footer: {
                if let activeSensor {
                    ChartLegendStrip(items: legendItems(for: activeSensor), hiddenItemIDs: hiddenLegendIDs) { item in
                        ChartInteractionSupport.toggleLegendItem(item.id, hiddenLegendIDs: &hiddenLegendIDs)
                    }
                    summaryRow(for: activeSensor)
                }
            }
        )
        .detachedPaneHistoryRefresh(
            contextRefreshID: contextRefreshID,
            refreshTriggerID: refreshTriggerID,
            isInteractionActive: isInteractionActive,
            onContextChange: {
                hoveredDate = nil
                viewport.reset()
                zoomSelectionRect = nil
                hiddenLegendIDs = []
            },
            refresh: { await refreshHistory() }
        )
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
        DetachedPaneHeaderCard(
            sectionTitle: "Temperature Detail",
            title: activeSensor?.displayName ?? "Select a sensor",
            subtitle: activeSensor.map {
                "\($0.category.label) • \($0.channelType == .fanRPM ? "Fan RPM" : "Temperature")"
            },
            valueText: activeSensor.map { TemperatureHistoryHelpers.valueText(for: $0) } ?? "--",
            badgeText: paneController.pinnedTarget != nil ? "Pinned" : "Hover Preview",
            accent: DashboardPalette.temperatureAccent
        )
    }

    @ViewBuilder
    private var chartSection: some View {
        if let activeSensor {
            sensorActionsRow(for: activeSensor)
            DashboardSectionLabel(title: "Sensor History", tint: DashboardPalette.secondaryText)

            if chartModel.isEmpty {
                DetachedPaneEmptyChartState(message: historyEmptyStateText(for: activeSensor))
            } else {
                DashboardTimeSeriesChart(
                    model: chartModel,
                    window: coordinator.selectedTemperatureHistoryWindow,
                    height: DetachedPaneLayout.temperaturePane.chartHeight,
                    paneController: paneController,
                    hiddenLegendIDs: hiddenLegendIDs,
                    yAxisLabel: { value in
                        axisLabel(for: value, sensor: activeSensor)
                    },
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    zoomSelectionRect: $zoomSelectionRect
                )
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

    @ViewBuilder
    private func summaryRow(for sensor: SensorReading) -> some View {
        HStack {
            if let summaryPoint = hoveredHistoryPoint ?? sensorHistory.last {
                Text(summaryPoint.timestamp.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(DashboardPalette.secondaryText)
                Spacer()
                Text(TemperatureHistoryHelpers.valueText(for: sensor, value: summaryPoint.value))
            } else {
                Text(" ")
                Spacer()
                Text(" ")
            }
        }
        .font(.caption)
        .frame(height: 18)
    }

    private var hoveredHistoryPoint: TemperatureHistoryPoint? {
        guard let hoveredDate else { return nil }
        return TemperatureHistoryHelpers.nearestPoint(to: hoveredDate, in: sensorHistory)
    }

    private func refreshHistory() async {
        coordinator.performanceDiagnosticsStore.recordDetachedPaneQuery()
        guard let activeSensor else {
            sensorHistory = []
            chartModel = .empty
            return
        }

        let start = ContinuousClock.now
        sensorHistory = await coordinator.temperatureHistorySeries(
            sensorID: activeSensor.id,
            channelType: activeSensor.channelType,
            window: coordinator.selectedTemperatureHistoryWindow,
            maxPoints: 480
        )
        let color = activeSensor.channelType == .fanRPM ? DashboardPalette.diskAccent : DashboardPalette.temperatureChartAccent
        chartModel = PreparedTimeSeriesChartModel.fromTemperatureHistory(
            series: [
                ChartMetricSeriesDescriptor(
                    key: activeSensor.id,
                    label: activeSensor.displayName,
                    color: color,
                    samples: sensorHistory
                )
            ],
            baseline: .dataMin(minimumSpan: 1, paddingFraction: 0.12),
            window: coordinator.selectedTemperatureHistoryWindow,
            smoothingAlpha: coordinator.chartSmoothingAlpha,
            sampleBudget: .fullChart
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
        "\(historyRefreshID)-\(coordinator.chartSmoothingAlpha)"
    }

    private var isInteractionActive: Bool {
        ChartInteractionSupport.isChartInteractionActive(hoveredDate: hoveredDate, zoomSelectionRect: zoomSelectionRect)
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

    private func legendItems(for sensor: SensorReading) -> [ChartLegendItem] {
        [
            ChartLegendItem(
                id: sensor.id,
                label: sensor.displayName,
                color: sensor.channelType == .fanRPM ? DashboardPalette.diskAccent : DashboardPalette.temperatureChartAccent,
                valueText: (hoveredHistoryPoint ?? sensorHistory.last).map {
                    TemperatureHistoryHelpers.valueText(for: sensor, value: $0.value)
                }
            )
        ]
    }

    @ViewBuilder
    private func sensorActionsRow(for sensor: SensorReading) -> some View {
        HStack(spacing: 8) {
            Button("Hide This Sensor") {
                coordinator.hideTemperatureSensor(sensorID: sensor.id)
                paneController.reconcileTemperatureSensors(Set(coordinator.visibleSensorChannels().map(\.id)))
            }
            .buttonStyle(.bordered)

            if !coordinator.hiddenTemperatureSensorIDs.isEmpty {
                Button("Show Hidden (\(coordinator.hiddenTemperatureSensorIDs.count))") {
                    coordinator.resetHiddenTemperatureSensors()
                    paneController.reconcileTemperatureSensors(Set(coordinator.visibleSensorChannels().map(\.id)))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.bottom, 2)
    }

}
