import Charts
import SwiftUI
import PulseBarCore

struct TemperatureTabView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var selectedSensorHistory: [TemperatureHistoryPoint] = []
    @State private var hoveredPoint: TemperatureHistoryPoint?
    @State private var hoveringHistoryChart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                headerSection(compact: false)
                headerSection(compact: true)
            }

            if let gateMessage = coordinator.fanParityGateMessage {
                Text(gateMessage)
                    .font(.caption)
                    .foregroundStyle(coordinator.fanParityGateBlocked ? .red : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill((coordinator.fanParityGateBlocked ? Color.red : Color.secondary).opacity(0.12))
                    )
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    sensorListPanel(maxHeight: 430)
                        .frame(width: 320)
                    selectedHistoryPanel(compact: false)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 14) {
                    sensorListPanel(maxHeight: 280)
                    selectedHistoryPanel(compact: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            diagnosticsPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            await refreshSelectedHistory()
        }
        .onReceive(coordinator.$latestSensorChannels) { _ in
            Task { await refreshSelectedHistory() }
        }
        .onChange(of: coordinator.selectedTemperatureSensorID) { _ in
            Task { await refreshSelectedHistory() }
        }
        .onChange(of: coordinator.selectedTemperatureHistoryWindow) { _ in
            Task { await refreshSelectedHistory() }
        }
    }

    private func headerSection(compact: Bool) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: compact ? 2 : 4)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            metricCard(
                title: "Primary Temp",
                value: coordinator.latestValue(for: .temperaturePrimaryCelsius).map {
                    UnitsFormatter.format($0.value, unit: .celsius)
                } ?? "Unavailable"
            )

            metricCard(
                title: "Max Temp",
                value: coordinator.latestValue(for: .temperatureMaxCelsius).map {
                    UnitsFormatter.format($0.value, unit: .celsius)
                } ?? "Unavailable"
            )

            metricCard(
                title: "Source",
                value: sourceLabel
            )

            metricCard(
                title: "Thermal State",
                value: coordinator.latestThermalState().label
            )
        }
    }

    private func sensorListPanel(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sensors")
                    .font(.headline)
                Spacer()
                Text("\(coordinator.latestSensorChannels.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if groupedSensors.isEmpty {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groupedSensors, id: \.category) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.category.label.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(group.channels, id: \.id) { channel in
                                    sensorRow(channel: channel)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: maxHeight)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    @ViewBuilder
    private func sensorRow(channel: SensorReading) -> some View {
        Button {
            coordinator.selectedTemperatureSensorID = channel.id
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(channel.source.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(valueText(for: channel))
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 66, alignment: .trailing)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                        Capsule()
                            .fill(channel.channelType == .fanRPM ? Color.orange : Color.cyan)
                            .frame(width: barWidth(for: channel, totalWidth: proxy.size.width))
                    }
                }
                .frame(width: 90, height: 10)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(channel.id == coordinator.selectedTemperatureSensorID ? Color.accentColor.opacity(0.2) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectedHistoryPanel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    historyTitleBlock
                    historyWindowPicker(segmented: false)
                }
            } else {
                HStack(alignment: .top) {
                    historyTitleBlock
                    Spacer()
                    historyWindowPicker(segmented: true)
                        .frame(maxWidth: 420)
                }
            }

            if selectedSensorHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Collecting \(selectedSensor?.displayName ?? "sensor") history")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 250)
            } else {
                ZStack(alignment: .topLeading) {
                    Chart(selectedSensorHistory, id: \.timestamp) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Value", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(selectedSensor?.channelType == .fanRPM ? .orange : .cyan)

                        if let hoveredPoint {
                            RuleMark(x: .value("Hover", hoveredPoint.timestamp))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYScale(domain: historyYDomain)
                    .frame(height: hoveringHistoryChart ? 240 : 180)
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
                                            hoveredPoint = nil
                                            return
                                        }
                                        hoveredPoint = nearestHistoryPoint(to: date)
                                    case .ended:
                                        hoveringHistoryChart = false
                                        hoveredPoint = nil
                                    }
                                }
                        }
                    }
                }
                .frame(height: 250)

                HStack {
                    if let summaryPoint = hoveredPoint ?? selectedSensorHistory.last {
                        Text(summaryPoint.timestamp.formatted(date: .omitted, time: .standard))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(valueText(for: selectedSensor, value: summaryPoint.value))
                    } else {
                        Text(" ")
                        Spacer()
                        Text(" ")
                    }
                }
                .font(.caption)
                .frame(height: 18)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var historyTitleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selectedSensor?.displayName ?? "Select a sensor")
                .font(.headline)
                .lineLimit(1)
            if let selectedSensor {
                Text("\(selectedSensor.category.label) • \(selectedSensor.channelType == .fanRPM ? "Fan RPM" : "Temperature")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func historyWindowPicker(segmented: Bool) -> some View {
        Group {
            if segmented {
                Picker("Window", selection: $coordinator.selectedTemperatureHistoryWindow) {
                    ForEach(TemperatureHistoryWindow.allCases, id: \.self) { window in
                        Text(window.label).tag(window)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            } else {
                Picker("Window", selection: $coordinator.selectedTemperatureHistoryWindow) {
                    ForEach(TemperatureHistoryWindow.allCases, id: \.self) { window in
                        Text(window.label).tag(window)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source Diagnostics")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if coordinator.privilegedSourceDiagnostics.isEmpty {
                Text("No diagnostics yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(coordinator.privilegedSourceDiagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    HStack(alignment: .firstTextBaseline) {
                        Circle()
                            .fill(diagnostic.healthy ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                        Text("\(diagnostic.source): \(diagnostic.message ?? (diagnostic.healthy ? "ok" : "failed"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let historyStatus = coordinator.temperatureHistoryStoreStatusMessage {
                Text(historyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var groupedSensors: [(category: SensorCategory, channels: [SensorReading])] {
        let grouped = Dictionary(grouping: coordinator.latestSensorChannels, by: \.category)
        return grouped
            .map { category, channels in
                (
                    category: category,
                    channels: channels.sorted { lhs, rhs in
                        if lhs.channelType != rhs.channelType {
                            return lhs.channelType.rawValue < rhs.channelType.rawValue
                        }
                        if lhs.value != rhs.value {
                            return lhs.value > rhs.value
                        }
                        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                    }
                )
            }
            .sorted { $0.category.label < $1.category.label }
    }

    private var selectedSensor: SensorReading? {
        coordinator.selectedSensorReading()
    }

    private var sourceLabel: String {
        if coordinator.privilegedTemperatureEnabled && coordinator.privilegedTemperatureHealthy {
            if coordinator.privilegedActiveSourceChain.isEmpty {
                return "Privileged"
            }
            return coordinator.privilegedActiveSourceChain.joined(separator: " -> ")
        }
        return "Standard"
    }

    private var emptyStateText: String {
        if coordinator.privilegedTemperatureEnabled && !coordinator.privilegedTemperatureHealthy {
            return "Privileged mode is unavailable right now. Falling back to standard thermal state."
        }
        return "Waiting for privileged sensor channels."
    }

    private var historyYDomain: ClosedRange<Double> {
        let values = selectedSensorHistory.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }
        if minValue == maxValue {
            let delta = max(1, abs(minValue * 0.1))
            return (minValue - delta)...(maxValue + delta)
        }
        let padding = (maxValue - minValue) * 0.1
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func refreshSelectedHistory() async {
        guard let selectedSensor else {
            selectedSensorHistory = []
            return
        }
        selectedSensorHistory = await coordinator.temperatureHistorySeries(
            sensorID: selectedSensor.id,
            channelType: selectedSensor.channelType,
            window: coordinator.selectedTemperatureHistoryWindow,
            maxPoints: 900
        )
    }

    private func nearestHistoryPoint(to date: Date) -> TemperatureHistoryPoint? {
        selectedSensorHistory.min {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }
    }

    private func valueText(for channel: SensorReading) -> String {
        valueText(for: channel, value: channel.value)
    }

    private func valueText(for channel: SensorReading?, value: Double) -> String {
        guard let channel else { return "--" }
        switch channel.channelType {
        case .temperatureCelsius:
            return UnitsFormatter.format(value, unit: .celsius)
        case .fanRPM:
            return "\(Int(value.rounded())) rpm"
        }
    }

    private func barWidth(for channel: SensorReading, totalWidth: CGFloat) -> CGFloat {
        let maxValue: Double
        switch channel.channelType {
        case .temperatureCelsius:
            let temperatures = coordinator.latestSensorChannels
                .filter { $0.channelType == .temperatureCelsius }
                .map(\.value)
            maxValue = max(50, temperatures.max() ?? 50)
        case .fanRPM:
            let rpms = coordinator.latestSensorChannels
                .filter { $0.channelType == .fanRPM }
                .map(\.value)
            maxValue = max(1000, rpms.max() ?? 1000)
        }
        guard maxValue > 0 else { return 0 }
        let ratio = max(0, min(1, channel.value / maxValue))
        return totalWidth * ratio
    }
}
