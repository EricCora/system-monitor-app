import SwiftUI
import PulseBarCore

struct DashboardView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var statusStore: DashboardStatusStore
    @StateObject private var paneController = DetachedMetricsPaneController()
    @Namespace private var sectionTabsNamespace

    private let columns = [
        GridItem(.flexible(minimum: 320), spacing: 18),
        GridItem(.flexible(minimum: 320), spacing: 18)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dashboardHeader
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Divider()
                .overlay(DashboardPalette.divider)

            contentView
        }
        .dashboardCanvasBackground()
        .preferredColorScheme(.light)
        .onAppear {
            coordinator.resetDashboardSectionForPresentation()
            coordinator.setDashboardVisible(true)
            coordinator.refreshDashboardSurface()
        }
        .onDisappear {
            coordinator.setDashboardVisible(false)
            coordinator.resetDashboardSectionForPresentation()
            paneController.shutdown()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch coordinator.dashboardSection {
        case .overview:
            ScrollView {
                overviewContent
                    .padding(22)
            }
        case .cpu, .memory, .battery, .network, .temperature, .disk, .settings:
            ScrollView {
                detailContent
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var overviewContent: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(coordinator.dashboardCardOrder, id: \.self) { card in
                cardView(for: card)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch coordinator.dashboardSection {
        case .overview:
            EmptyView()
        case .cpu:
            CPUTabView(
                coordinator: coordinator,
                paneController: paneController,
                usageStore: coordinator.cpuUsageSurfaceStore,
                loadStore: coordinator.cpuLoadSurfaceStore,
                processesStore: coordinator.cpuProcessesSurfaceStore,
                gpuStore: coordinator.cpuGPUSurfaceStore,
                fpsStore: coordinator.cpuFPSSurfaceStore
            )
        case .memory:
            MemoryTabView(
                coordinator: coordinator,
                paneController: paneController,
                featureStore: coordinator.memoryFeatureStore
            )
        case .battery:
            BatteryTabView(
                coordinator: coordinator,
                featureStore: coordinator.batteryFeatureStore
            )
        case .network:
            NetworkTabView(
                coordinator: coordinator,
                featureStore: coordinator.networkFeatureStore
            )
        case .temperature:
            TemperatureTabView(
                coordinator: coordinator,
                paneController: paneController,
                featureStore: coordinator.temperatureFeatureStore
            )
        case .disk:
            DiskTabView(
                coordinator: coordinator,
                featureStore: coordinator.diskFeatureStore
            )
        case .settings:
            QuickSettingsView(
                coordinator: coordinator,
                statusStore: statusStore,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
            )
        }
    }

    @ViewBuilder
    private func cardView(for card: DashboardCardID) -> some View {
        switch card {
        case .cpu:
            CPUDashboardCard(
                coordinator: coordinator,
                usageStore: coordinator.cpuUsageSurfaceStore,
                gpuStore: coordinator.cpuGPUSurfaceStore,
                fpsStore: coordinator.cpuFPSSurfaceStore,
                processesStore: coordinator.cpuProcessesSurfaceStore
            )
        case .memory:
            MemoryDashboardCard(coordinator: coordinator, featureStore: coordinator.memoryFeatureStore)
        case .battery:
            BatteryDashboardCard(coordinator: coordinator, featureStore: coordinator.batteryFeatureStore)
        case .network:
            NetworkDashboardCard(coordinator: coordinator, featureStore: coordinator.networkFeatureStore, throughputUnit: coordinator.throughputUnit)
        case .disk:
            DiskDashboardCard(coordinator: coordinator, featureStore: coordinator.diskFeatureStore, throughputUnit: coordinator.throughputUnit)
        case .sensors:
            SensorsDashboardCard(coordinator: coordinator, featureStore: coordinator.temperatureFeatureStore)
        }
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LIVE SYSTEM")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(DashboardPalette.temperatureAccent)

                    Text("PulseBar")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardPalette.primaryText)
                    Text("Overview first, deep inspection one tap away.")
                        .font(.subheadline)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Menu {
                        ForEach(ProfileID.allCases, id: \.self) { profile in
                            Button(profile.label) {
                                coordinator.selectedProfileID = profile
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Profile")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardPalette.secondaryText)

                            Spacer(minLength: 8)

                            Text(coordinator.selectedProfileID.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DashboardPalette.primaryText)
                                .lineLimit(1)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DashboardPalette.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(width: 220)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.94))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    HStack(spacing: 10) {
                        headerBadge(
                            title: "Power",
                            value: statusStore.snapshot.currentPowerSourceDescription,
                            tint: DashboardPalette.batteryAccent
                        )
                        headerBadge(
                            title: "Refresh",
                            value: "\(Int(coordinator.globalSamplingInterval))s",
                            tint: DashboardPalette.cpuAccent
                        )
                        headerBadge(
                            title: "Thermals",
                            value: statusStore.snapshot.privilegedTemperatureHealthy ? "Live" : "Fallback",
                            tint: statusStore.snapshot.privilegedTemperatureHealthy ? DashboardPalette.success : DashboardPalette.warning
                        )
                        headerBadge(
                            title: "Section",
                            value: coordinator.dashboardSection.label,
                            tint: accent(for: coordinator.dashboardSection)
                        )
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DashboardSection.allCases, id: \.self) { section in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                coordinator.setDashboardSection(section)
                            }
                        } label: {
                            Text(section.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    coordinator.dashboardSection == section
                                    ? Color.white
                                    : DashboardPalette.primaryText
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 88)
                                .background(
                                    ZStack {
                                        if coordinator.dashboardSection == section {
                                            Capsule(style: .continuous)
                                                .fill(accent(for: section))
                                                .matchedGeometryEffect(id: "dashboard-section-pill", in: sectionTabsNamespace)
                                        } else {
                                            Capsule(style: .continuous)
                                                .fill(Color.white.opacity(0.84))
                                                .overlay(
                                                    Capsule(style: .continuous)
                                                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                                                )
                                        }
                                    }
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.36))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                        )
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.50))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                )
                .shadow(color: DashboardPalette.shadow, radius: 18, x: 0, y: 10)
        )
    }

    private func headerBadge(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .center, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)

                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(DashboardPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 108, height: 68, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.98))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                )
        )
    }

    private func accent(for section: DashboardSection) -> Color {
        switch section {
        case .overview:
            return DashboardPalette.cpuAccent
        case .cpu:
            return DashboardPalette.cpuAccent
        case .memory:
            return DashboardPalette.memoryAccent
        case .battery:
            return DashboardPalette.batteryAccent
        case .network:
            return DashboardPalette.networkAccent
        case .temperature:
            return DashboardPalette.temperatureAccent
        case .disk:
            return DashboardPalette.diskAccent
        case .settings:
            return DashboardPalette.secondaryText
        }
    }
}

private struct CPUDashboardCard: View {
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
                values: usageStore.snapshot.renderModel.segments.flatMap(\.points).map(\.totalValue),
                lineColor: DashboardPalette.cpuAccent,
                fillColor: DashboardPalette.cpuAccent.opacity(0.18)
            )

            HStack(spacing: 10) {
                metricPill(label: "User", value: usageStore.snapshot.summary.userPercent, tint: DashboardPalette.memoryAccent)
                metricPill(label: "System", value: usageStore.snapshot.summary.systemPercent, tint: DashboardPalette.cpuAccent)
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
                        DashboardProcessListRow(
                            name: entry.name,
                            value: UnitsFormatter.format(entry.cpuPercent, unit: .percent)
                        )
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

private struct MemoryDashboardCard: View {
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
                lineColor: DashboardPalette.networkAccent,
                fillColor: DashboardPalette.networkAccent.opacity(0.18)
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
                        DashboardProcessListRow(
                            name: entry.name,
                            value: UnitsFormatter.format(entry.residentBytes, unit: .bytes)
                        )
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

private struct BatteryDashboardCard: View {
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
                lineColor: featureStore.isCharging ? DashboardPalette.batteryAccent : DashboardPalette.cpuAccent,
                fillColor: (featureStore.isCharging ? DashboardPalette.batteryAccent : DashboardPalette.cpuAccent).opacity(0.18)
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
                        DashboardProcessListRow(
                            name: entry.name,
                            value: UnitsFormatter.format(entry.cpuPercent, unit: .percent)
                        )
                    }
                }
            }
        }
    }
}

private struct NetworkDashboardCard: View {
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

private struct DiskDashboardCard: View {
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

private struct SensorsDashboardCard: View {
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
                ForEach(coordinator.dashboardSensorReadings(), id: \.id) { sensor in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sensor.displayName)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(sensor.category.label)
                                .font(.caption2)
                                .foregroundStyle(DashboardPalette.secondaryText)
                        }

                        Spacer()

                        Text(TemperatureHistoryHelpers.valueText(for: sensor))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(DashboardPalette.primaryText)

                        Capsule()
                            .fill(sensor.channelType == .fanRPM ? DashboardPalette.diskAccent : DashboardPalette.temperatureAccent)
                            .frame(width: 34, height: 8)
                    }
                }
            }

            if coordinator.dashboardSensorReadings().isEmpty {
                Text("No live sensors available yet. PulseBar will keep standard thermal state active until privileged sampling is retried.")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
        }
    }
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
