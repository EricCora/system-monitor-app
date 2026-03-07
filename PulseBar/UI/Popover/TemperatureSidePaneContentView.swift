import Charts
import SwiftUI
import PulseBarCore

struct TemperaturePaneContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var sensorHistory: [TemperatureHistoryPoint] = []
    @State private var hoveredHistoryPoint: TemperatureHistoryPoint?
    @State private var hoveringHistoryChart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HistoryWindowSegmentedControl(
                options: TemperatureHistoryWindow.allCases,
                selection: $coordinator.selectedTemperatureHistoryWindow,
                paneController: paneController,
                label: \.label
            )

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeSensor?.displayName ?? "Select a sensor")
                        .font(.headline)
                        .lineLimit(1)
                    if let activeSensor {
                        Text("\(activeSensor.category.label) • \(activeSensor.channelType == .fanRPM ? "Fan RPM" : "Temperature")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if paneController.pinnedTarget != nil {
                    Text("Pinned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Hover Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
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
                            .foregroundStyle(.secondary)
                        Text("Collecting \(activeSensor.displayName) history")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    ZStack(alignment: .topLeading) {
                        Chart(ChartSeriesSanitizer.temperatureHistory(sensorHistory), id: \.timestamp) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Value", point.value)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(activeSensor.channelType == .fanRPM ? .orange : .cyan)

                            if let hoveredHistoryPoint {
                                RuleMark(x: .value("Hover", hoveredHistoryPoint.timestamp))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartYScale(domain: TemperatureHistoryHelpers.yDomain(for: sensorHistory))
                        .frame(height: hoveringHistoryChart ? 290 : 260)
                        .animation(.easeInOut(duration: 0.15), value: hoveringHistoryChart)
                        .chartOverlay { proxy in
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(.clear)
                                    .contentShape(Rectangle())
                                    .onContinuousHover { phase in
                                        switch phase {
                                        case .active(let location):
                                            hoveringHistoryChart = true
                                            let xPosition = location.x - geometry[proxy.plotAreaFrame].origin.x
                                            guard xPosition >= 0,
                                                  xPosition <= proxy.plotAreaSize.width,
                                                  let date: Date = proxy.value(atX: xPosition, as: Date.self) else {
                                                hoveredHistoryPoint = nil
                                                return
                                            }
                                            hoveredHistoryPoint = TemperatureHistoryHelpers.nearestPoint(
                                                to: date,
                                                in: sensorHistory
                                            )
                                        case .ended:
                                            hoveringHistoryChart = false
                                            hoveredHistoryPoint = nil
                                        }
                                    }
                            }
                        }
                    }
                    .frame(height: 300)

                    HStack {
                        if let summaryPoint = hoveredHistoryPoint ?? sensorHistory.last {
                            Text(summaryPoint.timestamp.formatted(date: .omitted, time: .standard))
                                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    Text("No sensor selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .task {
            await refreshHistory()
        }
        .onChange(of: paneController.pinnedTarget) { _ in
            hoveredHistoryPoint = nil
            Task { await refreshHistory() }
        }
        .onChange(of: paneController.hoveredTarget) { _ in
            hoveredHistoryPoint = nil
            Task { await refreshHistory() }
        }
        .onChange(of: coordinator.selectedTemperatureHistoryWindow) { _ in
            hoveredHistoryPoint = nil
            Task { await refreshHistory() }
        }
        .onReceive(coordinator.$latestSensorChannels) { _ in
            Task { await refreshHistory() }
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
        guard let activeSensor else {
            sensorHistory = []
            return
        }

        sensorHistory = await coordinator.temperatureHistorySeries(
            sensorID: activeSensor.id,
            channelType: activeSensor.channelType,
            window: coordinator.selectedTemperatureHistoryWindow,
            maxPoints: 900
        )
        sensorHistory = ChartSeriesSanitizer.temperatureHistory(sensorHistory)
    }
}
