import AppKit
import SwiftUI
import PulseBarCore

struct TemperatureTabView: View {
    let coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController
    @ObservedObject var featureStore: TemperatureFeatureStore
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let gateMessage = featureStore.fanParityGateMessage {
                Text(gateMessage)
                    .font(.caption)
                    .foregroundStyle(featureStore.fanParityGateBlocked ? .red : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill((featureStore.fanParityGateBlocked ? Color.red : Color.secondary).opacity(0.12))
                    )
            }

            sensorListPanel
            diagnosticsPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            PopoverWindowAccessor { window in
                if hostWindow !== window {
                    hostWindow = window
                }
            }
        )
        .task {
            synchronizeSelectionAndPane()
        }
        .task(id: featureStore.visibleSensors.map(\.id).joined(separator: ",")) {
            synchronizeSelectionAndPane()
        }
        .onDisappear {
            paneController.closeIfActive(family: .temperature)
        }
    }

    private var sensorListPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SENSORS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(featureStore.visibleSensors.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !coordinator.hiddenTemperatureSensorIDs.isEmpty {
                Button("Show Hidden Sensors (\(coordinator.hiddenTemperatureSensorIDs.count))") {
                    coordinator.resetHiddenTemperatureSensors()
                    synchronizeSelectionAndPane()
                }
                .buttonStyle(.bordered)
            }

            if featureStore.visibleSensors.isEmpty {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(featureStore.groupedSensors) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.category.label.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(group.channels, id: \.id) { sensor in
                                sensorRow(sensor)
                            }
                        }
                    }
                }
            }
        }
        .onHover { hovering in
            paneController.setMainListHovering(hovering)
        }
    }

    private func sensorRow(_ sensor: SensorReading) -> some View {
        Button {
            coordinator.selectedTemperatureSensorID = sensor.id
            if let parentWindow = currentParentWindow {
                paneController.pin(.temperature(sensorID: sensor.id), coordinator: coordinator, parentWindow: parentWindow)
            }
        } label: {
            HStack(spacing: 8) {
                Text(sensor.displayName)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(TemperatureHistoryHelpers.valueText(for: sensor))
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 68, alignment: .trailing)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                        Capsule()
                            .fill(sensor.channelType == .fanRPM ? Color.orange : Color.cyan)
                            .frame(width: barWidth(for: sensor, totalWidth: proxy.size.width))
                    }
                }
                .frame(width: 90, height: 10)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(for: sensor))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                if let parentWindow = currentParentWindow {
                    paneController.preview(.temperature(sensorID: sensor.id), coordinator: coordinator, parentWindow: parentWindow)
                }
            } else {
                paneController.clearPreview(.temperature(sensorID: sensor.id))
            }
        }
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source Diagnostics")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if featureStore.privilegedSourceDiagnostics.isEmpty {
                Text("No diagnostics yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(featureStore.privilegedSourceDiagnostics.enumerated()), id: \.offset) { _, diagnostic in
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

            if let historyStatus = featureStore.temperatureHistoryStoreStatusMessage {
                Text(historyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyStateText: String {
        if coordinator.privilegedTemperatureEnabled && !featureStore.privilegedTemperatureHealthy {
            return "Privileged mode is unavailable right now. Falling back to standard thermal state."
        }
        if !coordinator.hiddenTemperatureSensorIDs.isEmpty {
            return "All current sensors are hidden."
        }
        return "Waiting for privileged sensor channels."
    }

    private var currentParentWindow: NSWindow? {
        hostWindow ?? NSApp.keyWindow
    }

    private func synchronizeSelectionAndPane() {
        if coordinator.selectedSensorReading() == nil {
            coordinator.selectedTemperatureSensorID = featureStore.visibleSensors.first?.id ?? ""
        }

        paneController.reconcileTemperatureSensors(Set(featureStore.visibleSensors.map(\.id)))
        if featureStore.visibleSensors.isEmpty {
            paneController.closePanel(clearSelection: false)
        }
    }

    private func backgroundColor(for sensor: SensorReading) -> Color {
        if paneController.isActive(.temperature(sensorID: sensor.id)) {
            return Color.accentColor.opacity(0.16)
        }
        if sensor.id == coordinator.selectedTemperatureSensorID {
            return Color.accentColor.opacity(0.22)
        }
        return .clear
    }

    private func barWidth(for channel: SensorReading, totalWidth: CGFloat) -> CGFloat {
        guard let group = featureStore.groupedSensors.first(where: { $0.category == channel.category }) else {
            return 0
        }
        return totalWidth * group.barWidthRatio(for: channel)
    }
}
