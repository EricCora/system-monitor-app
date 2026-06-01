import SwiftUI
import PulseBarCore

struct CPUDashboardCard: View {
    let coordinator: AppCoordinator
    @ObservedObject var usageStore: CPUUsageSurfaceStore
    @ObservedObject var gpuStore: CPUGPUSurfaceStore
    @ObservedObject var fpsStore: CPUFPSSurfaceStore
    @ObservedObject var processesStore: CPUProcessesSurfaceStore

    var body: some View {
        DashboardCard(
            "CPU & GPU",
            accent: DashboardPalette.cpuAccent,
            actionTitle: "Open CPU",
            action: { coordinator.openDashboardDetails(for: .cpu) }
        ) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(UnitsFormatter.format(cpuTotalPercent, unit: .percent))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardPalette.primaryText)
                    Text("CPU total")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "L %.2f", usageStore.snapshot.summary.loadAverages.one))
                        .font(.subheadline.monospacedDigit())
                    if let gpuPercent = gpuStore.snapshot.summary?.processorPercent {
                        Text("GPU \(UnitsFormatter.format(gpuPercent, unit: .percent))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DashboardPalette.secondaryText)
                    }
                    if let fps = fpsStore.snapshot.framesPerSecond {
                        Text(String(format: "%.0f FPS", fps))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DashboardPalette.secondaryText)
                    }
                }
            }

            DashboardSparklineView(
                model: PreparedTimeSeriesChartModel.fromCompactCPUUsage(
                    renderModel: usageStore.snapshot.renderModel,
                    window: usageStore.snapshot.chartWindow
                )
            )

            HStack(spacing: 10) {
                metricPill(label: "User", value: usageStore.snapshot.summary.userPercent, tint: DashboardPalette.cpuUserAccent)
                metricPill(label: "System", value: usageStore.snapshot.summary.systemPercent, tint: DashboardPalette.cpuSystemAccent)
                metricPill(label: "Idle", value: usageStore.snapshot.summary.idlePercent, tint: DashboardPalette.tertiaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("CORES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)

                HStack(spacing: 6) {
                    ForEach(coordinator.latestCPUCores(), id: \.metricID) { sample in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                Capsule()
                                    .fill(DashboardPalette.insetFill)
                                    .frame(width: 12, height: 44)

                                Capsule()
                                    .fill(sample.value > 70 ? DashboardPalette.memoryAccent : DashboardPalette.cpuAccent)
                                    .frame(width: 12, height: CGFloat(max(10, min(44, sample.value * 0.44))))
                            }
                            Text(coreLabel(for: sample.metricID))
                                .font(.caption2)
                                .foregroundStyle(DashboardPalette.tertiaryText)
                        }
                    }
                }
            }

            if !processesStore.snapshot.entries.isEmpty {
                Divider()
                    .overlay(DashboardPalette.divider)
                VStack(alignment: .leading, spacing: 6) {
                    Text("PROCESSES")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardPalette.secondaryText)

                    ForEach(Array(processesStore.snapshot.entries.prefix(4))) { entry in
                        ProcessListRow(entry: entry)
                    }
                }
            }
        }
    }

    private var cpuTotalPercent: Double {
        max(0, 100 - usageStore.snapshot.summary.idlePercent)
    }

    private func metricPill(label: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(UnitsFormatter.format(value, unit: .percent))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(DashboardPalette.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.14))
        )
    }

    private func coreLabel(for metricID: MetricID) -> String {
        guard case .cpuCorePercent(let index) = metricID else { return "-" }
        return "\(index + 1)"
    }
}

struct MemoryDashboardCard: View {
    let coordinator: AppCoordinator
    @ObservedObject var featureStore: MemoryFeatureStore

    var body: some View {
        DashboardCard(
            "Memory",
            accent: DashboardPalette.memoryAccent,
            actionTitle: "Open Memory",
            action: { coordinator.openDashboardDetails(for: .memory) }
        ) {
            HStack(spacing: 18) {
                DashboardRingGauge(
                    value: featureStore.pressurePercent,
                    total: 100,
                    title: "Pressure",
                    valueText: "\(Int(featureStore.pressurePercent.rounded()))%",
                    tint: DashboardPalette.networkAccent
                )

                DashboardRingGauge(
                    value: usedPercent,
                    total: 100,
                    title: "Used",
                    valueText: "\(Int(usedPercent.rounded()))%",
                    tint: DashboardPalette.memoryAccent
                )
            }

            DashboardSparklineView(
                values: featureStore.usedSamples.map(\.value),
                lineColor: DashboardPalette.networkAccent
            )

            VStack(alignment: .leading, spacing: 6) {
                DashboardMetricRow(title: "App", value: UnitsFormatter.format(featureStore.appBytes, unit: .bytes), tint: DashboardPalette.memoryAccent)
                DashboardMetricRow(title: "Wired", value: UnitsFormatter.format(featureStore.wiredBytes, unit: .bytes), tint: DashboardPalette.diskAccent)
                DashboardMetricRow(title: "Compressed", value: UnitsFormatter.format(featureStore.compressedBytes, unit: .bytes), tint: DashboardPalette.networkAccent)
                DashboardMetricRow(title: "Free", value: UnitsFormatter.format(featureStore.freeBytes, unit: .bytes), tint: DashboardPalette.secondaryText)
                DashboardMetricRow(title: "Swap", value: UnitsFormatter.format(featureStore.swapUsedBytes, unit: .bytes), tint: DashboardPalette.secondaryText)
            }

            if !featureStore.topProcesses.isEmpty {
                Divider()
                    .overlay(DashboardPalette.divider)
                VStack(alignment: .leading, spacing: 6) {
                    Text("PROCESSES")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardPalette.secondaryText)

                    ForEach(Array(featureStore.topProcesses.prefix(4))) { entry in
                        ProcessListRow(entry: entry)
                    }
                }
            }
        }
    }

    private var usedPercent: Double {
        let total = max(featureStore.usedBytes + featureStore.freeBytes, 1)
        return (featureStore.usedBytes / total) * 100
    }
}

struct BatteryDashboardCard: View {
    let coordinator: AppCoordinator
    @ObservedObject var featureStore: BatteryFeatureStore

    var body: some View {
        DashboardCard(
            "Battery",
            accent: DashboardPalette.batteryAccent,
            actionTitle: "Open Battery",
            action: { coordinator.openDashboardDetails(for: .battery) }
        ) {
            HStack(spacing: 18) {
                DashboardRingGauge(
                    value: featureStore.chargePercent,
                    total: 100,
                    title: featureStore.isCharging ? "Charging" : "Battery",
                    valueText: "\(Int(featureStore.chargePercent.rounded()))%",
                    tint: DashboardPalette.batteryAccent
                )

                DashboardRingGauge(
                    value: featureStore.healthPercent ?? 0,
                    total: 100,
                    title: "Health",
                    valueText: featureStore.healthPercent.map { "\(Int($0.rounded()))%" } ?? "--",
                    tint: DashboardPalette.cpuAccent
                )
            }

            DashboardSparklineView(
                values: featureStore.chargeSamples.map(\.value),
                lineColor: featureStore.isCharging ? DashboardPalette.batteryAccent : DashboardPalette.cpuAccent
            )

            VStack(alignment: .leading, spacing: 6) {
                DashboardMetricRow(title: "Power", value: featureStore.powerWatts.map { UnitsFormatter.format($0, unit: .watts) } ?? "--")
                DashboardMetricRow(title: "Time Remaining", value: featureStore.timeRemainingMinutes.map { UnitsFormatter.format($0, unit: .minutes) } ?? "--")
                DashboardMetricRow(title: "Current", value: featureStore.currentMilliamps.map { UnitsFormatter.format($0, unit: .milliamps) } ?? "--")
                DashboardMetricRow(title: "Energy Mode", value: featureStore.energyModeLabel)
            }

            if !featureStore.significantEnergyProcesses.isEmpty {
                Divider()
                    .overlay(DashboardPalette.divider)
                VStack(alignment: .leading, spacing: 6) {
                    Text("USING SIGNIFICANT ENERGY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardPalette.secondaryText)

                    ForEach(Array(featureStore.significantEnergyProcesses.prefix(3))) { entry in
                        ProcessListRow(entry: entry)
                    }
                }
            }
        }
    }
}

struct NetworkDashboardCard: View {
    let coordinator: AppCoordinator
    @ObservedObject var featureStore: NetworkFeatureStore
    let throughputUnit: ThroughputDisplayUnit

    var body: some View {
        DashboardCard(
            "Network",
            accent: DashboardPalette.networkAccent,
            actionTitle: "Open Network",
            action: { coordinator.openDashboardDetails(for: .network) }
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(UnitsFormatter.format(featureStore.outboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: throughputUnit))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardPalette.primaryText)
                    Text("Upload")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(UnitsFormatter.format(featureStore.inboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: throughputUnit))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardPalette.primaryText)
                    Text("Download")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }

            DashboardBidirectionalSparklineView(
                positiveValues: featureStore.outboundSamples.map(\.value),
                negativeValues: featureStore.inboundSamples.map(\.value),
                positiveColor: DashboardPalette.networkAccent,
                negativeColor: DashboardPalette.cpuAccent
            )

            VStack(alignment: .leading, spacing: 6) {
                DashboardMetricRow(title: "Interface", value: featureStore.context.activeInterface)
                if let ssid = featureStore.context.ssid, !ssid.isEmpty {
                    DashboardMetricRow(title: "Wi-Fi", value: ssid, tint: DashboardPalette.networkAccent)
                }
                DashboardMetricRow(title: "VPN", value: featureStore.context.vpnConnected ? "Connected" : "Inactive")
                DashboardMetricRow(title: "Private IP", value: featureStore.context.primaryPrivateIP ?? "--")
                if let publicIPAddress = featureStore.context.publicIPAddress {
                    DashboardMetricRow(title: "Public IP", value: publicIPAddress)
                }
            }
        }
    }
}

struct DiskDashboardCard: View {
    let coordinator: AppCoordinator
    @ObservedObject var featureStore: DiskFeatureStore
    let throughputUnit: ThroughputDisplayUnit

    var body: some View {
        DashboardCard(
            "Disk",
            accent: DashboardPalette.diskAccent,
            actionTitle: "Open Disk",
            action: { coordinator.openDashboardDetails(for: .disk) }
        ) {
            HStack(spacing: 18) {
                DashboardRingGauge(
                    value: featureStore.freeBytes,
                    total: rootVolume.totalBytes,
                    title: rootVolume.name,
                    valueText: rootVolume.totalBytes > 0 ? "\(Int(((featureStore.freeBytes / rootVolume.totalBytes) * 100).rounded()))%" : "--",
                    tint: DashboardPalette.diskAccent
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(UnitsFormatter.format(featureStore.freeBytes, unit: .bytes))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardPalette.primaryText)
                    Text("available")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                    DashboardMetricRow(title: "SMART", value: smartStatusText, tint: smartStatusTint)
                }
            }

            DashboardBidirectionalSparklineView(
                positiveValues: featureStore.readSamples.map(\.value),
                negativeValues: featureStore.writeSamples.map(\.value),
                positiveColor: DashboardPalette.diskAccent,
                negativeColor: DashboardPalette.cpuAccent
            )

            VStack(alignment: .leading, spacing: 6) {
                DashboardMetricRow(title: "Read", value: UnitsFormatter.format(featureStore.readBytesPerSecond, unit: .bytesPerSecond, throughputUnit: throughputUnit), tint: DashboardPalette.diskAccent)
                DashboardMetricRow(title: "Write", value: UnitsFormatter.format(featureStore.writeBytesPerSecond, unit: .bytesPerSecond, throughputUnit: throughputUnit), tint: DashboardPalette.cpuAccent)
                DashboardMetricRow(title: "Combined", value: UnitsFormatter.format(featureStore.combinedBytesPerSecond, unit: .bytesPerSecond, throughputUnit: throughputUnit))
            }
        }
    }

    private var rootVolume: RootVolumeSnapshot {
        RootVolumeSnapshot.current()
    }

    private var smartStatusText: String {
        guard let code = featureStore.smartStatusCode else { return "Unknown" }
        switch code {
        case let value where value > 0:
            return "Verified"
        case 0:
            return "Not Supported"
        case let value where value < 0:
            return "Attention"
        default:
            return "Unknown"
        }
    }

    private var smartStatusTint: Color {
        guard let code = featureStore.smartStatusCode else { return DashboardPalette.secondaryText }
        return code > 0 ? DashboardPalette.batteryAccent : (code < 0 ? DashboardPalette.temperatureAccent : DashboardPalette.secondaryText)
    }
}

struct SensorsDashboardCard: View {
    let coordinator: AppCoordinator
    @ObservedObject var featureStore: TemperatureFeatureStore

    var body: some View {
        DashboardCard(
            "Sensors",
            accent: DashboardPalette.temperatureAccent,
            actionTitle: "Open Temperature",
            action: { coordinator.openDashboardDetails(for: .sensors) }
        ) {
            if !coordinator.sensorPresets.isEmpty {
                Picker("Preset", selection: Binding(
                    get: { coordinator.selectedSensorPresetID ?? "favorites" },
                    set: { coordinator.selectedSensorPresetID = $0 == "favorites" ? nil : $0 }
                )) {
                    Text("Favorites").tag("favorites")
                    ForEach(coordinator.sensorPresets, id: \.id) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if featureStore.usingPersistedSnapshot, let capturedAt = featureStore.latestCapturedAt {
                Text("Last updated \(capturedAt.formatted(date: .omitted, time: .standard)).")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            if let message = featureStore.privilegedTemperatureStatusMessage, !featureStore.privilegedTemperatureHealthy {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            if coordinator.privilegedTemperatureEnabled && !featureStore.privilegedTemperatureHealthy {
                Button("Retry Privileged Sampling") {
                    coordinator.retryPrivilegedTemperatureNow()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(temperatureCategorySummaries, id: \.category) { summary in
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.category.label)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(summary.count) sensor\(summary.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(DashboardPalette.secondaryText)
                        }

                        HStack(spacing: 8) {
                            temperatureAggregatePill("Min", value: summary.minimum)
                            temperatureAggregatePill("Avg", value: summary.average)
                            temperatureAggregatePill("Max", value: summary.maximum)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if coordinator.dashboardSensorReadings().isEmpty {
                Text("No live sensors available yet. PulseBar will keep standard thermal state active until privileged sampling is retried.")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
        }
    }

    private var temperatureCategorySummaries: [TemperatureCategorySummary] {
        featureStore.groupedSensors.compactMap { group in
            let values = group.channels
                .filter { $0.channelType == .temperatureCelsius }
                .map(\.value)
            guard let minimum = values.min(), let maximum = values.max(), !values.isEmpty else {
                return nil
            }
            let average = values.reduce(0, +) / Double(values.count)
            return TemperatureCategorySummary(
                category: group.category,
                count: values.count,
                minimum: minimum,
                average: average,
                maximum: maximum
            )
        }
    }

    private func temperatureAggregatePill(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DashboardPalette.tertiaryText)
            Text(UnitsFormatter.format(value, unit: .celsius))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardPalette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardPalette.insetFill.opacity(0.72))
        )
    }
}

private struct TemperatureCategorySummary {
    let category: SensorCategory
    let count: Int
    let minimum: Double
    let average: Double
    let maximum: Double
}

private struct RootVolumeSnapshot {
    let name: String
    let totalBytes: Double

    static func current() -> RootVolumeSnapshot {
        let rootURL = URL(fileURLWithPath: "/")
        let values = try? rootURL.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey])
        return RootVolumeSnapshot(
            name: values?.volumeName ?? "Macintosh HD",
            totalBytes: Double(values?.volumeTotalCapacity ?? 0)
        )
    }
}
