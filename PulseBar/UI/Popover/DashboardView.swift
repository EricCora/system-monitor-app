import SwiftUI
import PulseBarCore

struct DashboardView: View {
    private enum AppActionToConfirm {
        case restart
        case quit
    }

    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var statusStore: DashboardStatusStore
    @StateObject private var paneController = DetachedMetricsPaneController()
    @Namespace private var sectionTabsNamespace
    @State private var pendingAppAction: AppActionToConfirm?

    private var contentPadding: CGFloat {
        coordinator.dashboardDensity == .compact ? 16 : 22
    }

    private var gridSpacing: CGFloat {
        coordinator.dashboardDensity == .compact ? 12 : 18
    }

    private var overviewColumns: [GridItem] {
        let minimumWidth: CGFloat
        switch coordinator.dashboardLayout {
        case .cardDashboard:
            minimumWidth = coordinator.dashboardCardSize == .expanded ? 400 : 320
        case .focusGrid:
            minimumWidth = coordinator.dashboardCardSize == .expanded ? 460 : 380
        case .compactMatrix:
            minimumWidth = coordinator.dashboardCardSize == .expanded ? 320 : 260
        }
        return [
            GridItem(.adaptive(minimum: minimumWidth), spacing: gridSpacing, alignment: .top)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dashboardHeader
                .padding(.horizontal, contentPadding)
                .padding(.top, contentPadding)
                .padding(.bottom, 14)

            Divider()
                .overlay(DashboardPalette.divider)

            contentView
        }
        .dashboardCanvasBackground()
        .environment(
            \.dashboardChartDisplayOptions,
            ChartDisplayOptions(
                showsMinorGrid: coordinator.chartMinorGridEnabled,
                smoothingAlpha: coordinator.chartSmoothingAlpha
            )
        )
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
        .confirmationDialog(
            pendingAppAction == .restart ? "Restart PulseBar?" : "Quit PulseBar?",
            isPresented: Binding(
                get: { pendingAppAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingAppAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if pendingAppAction == .restart {
                Button("Restart Now") {
                    coordinator.restartApplication()
                    pendingAppAction = nil
                }
            }
            if pendingAppAction == .quit {
                Button("Quit Now", role: .destructive) {
                    coordinator.quitApplication()
                    pendingAppAction = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAppAction = nil
            }
        } message: {
            if pendingAppAction == .restart {
                Text("PulseBar will close and reopen immediately.")
            } else if pendingAppAction == .quit {
                Text("PulseBar will close immediately.")
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch coordinator.dashboardSection {
        case .overview:
            ScrollView {
                overviewContent
                    .padding(contentPadding)
            }
        case .cpu, .memory, .battery, .network, .temperature, .disk, .settings:
            ScrollView {
                detailSection
                    .padding(contentPadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: gridSpacing) {
            overviewSummaryPanel

            LazyVGrid(columns: overviewColumns, alignment: .leading, spacing: gridSpacing) {
                ForEach(coordinator.visibleDashboardCards, id: \.self) { card in
                    cardView(for: card)
                }
            }
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: gridSpacing) {
            HStack(alignment: .center, spacing: 12) {
                sectionIcon(for: coordinator.dashboardSection)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent(for: coordinator.dashboardSection))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accent(for: coordinator.dashboardSection).opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(coordinator.dashboardSection.label)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardPalette.primaryText)
                    Text(detailSubtitle(for: coordinator.dashboardSection))
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Spacer()
            }
            .padding(14)
            .dashboardSurface(padding: 0, cornerRadius: 8)

            detailContent
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        statusDot(tint: statusStore.snapshot.privilegedTemperatureHealthy ? DashboardPalette.success : DashboardPalette.warning)
                        Text("LIVE SYSTEM")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(DashboardPalette.secondaryText)
                    }

                    Text("PulseBar")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardPalette.primaryText)
                    Text("Menu bar monitor")
                        .font(.subheadline)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Spacer()

                HStack(spacing: 8) {
                    headerBadge(
                        title: "Power",
                        value: statusStore.snapshot.currentPowerSourceDescription,
                        tint: DashboardPalette.batteryAccent,
                        systemImage: "powerplug"
                    )
                    headerBadge(
                        title: "Refresh",
                        value: "\(Int(coordinator.globalSamplingInterval))s",
                        tint: DashboardPalette.cpuAccent,
                        systemImage: "arrow.clockwise"
                    )
                    headerBadge(
                        title: "Thermals",
                        value: statusStore.snapshot.privilegedTemperatureHealthy ? "Live" : "Fallback",
                        tint: statusStore.snapshot.privilegedTemperatureHealthy ? DashboardPalette.success : DashboardPalette.warning,
                        systemImage: "thermometer.medium"
                    )

                    Menu {
                        ForEach(ProfileID.allCases, id: \.self) { profile in
                            Button(profile.label) {
                                coordinator.selectedProfileID = profile
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                            Text(coordinator.selectedProfileID.label)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardPalette.primaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(DashboardPalette.sectionFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    HStack(spacing: 6) {
                        appActionButton(
                            systemImage: "arrow.clockwise.circle.fill",
                            tint: DashboardPalette.cpuAccent,
                            helpText: "Restart PulseBar"
                        ) {
                            pendingAppAction = .restart
                        }

                        appActionButton(
                            systemImage: "power.circle.fill",
                            tint: DashboardPalette.danger,
                            helpText: "Quit PulseBar"
                        ) {
                            pendingAppAction = .quit
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DashboardSection.allCases, id: \.self) { section in
                        Button {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                coordinator.setDashboardSection(section)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                sectionIcon(for: section)
                                    .font(.caption.weight(.semibold))
                                Text(section.label)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .foregroundStyle(
                                coordinator.dashboardSection == section
                                ? Color.white
                                : DashboardPalette.primaryText
                            )
                            .padding(.vertical, 7)
                            .padding(.horizontal, 11)
                            .frame(minWidth: 78)
                            .contentShape(Rectangle())
                                .background(
                                    ZStack {
                                        if coordinator.dashboardSection == section {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(accent(for: section))
                                                .matchedGeometryEffect(id: "dashboard-section-pill", in: sectionTabsNamespace)
                                        } else {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(DashboardPalette.sectionFill)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DashboardPalette.insetFill.opacity(0.62))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                        )
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardPalette.cardTop.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                )
                .shadow(color: DashboardPalette.shadow, radius: 14, x: 0, y: 8)
        )
    }

    private func appActionButton(
        systemImage: String,
        tint: Color,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(DashboardPalette.sectionFill)
                        .overlay(
                            Circle()
                                .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private func headerBadge(title: String, value: String, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DashboardPalette.tertiaryText)
                    .lineLimit(1)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(width: 108, height: 42, alignment: .leading)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardPalette.sectionFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                )
        )
    }

    private func statusDot(tint: Color) -> some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(tint.opacity(0.22), lineWidth: 5)
            )
    }

    @ViewBuilder
    private func sectionIcon(for section: DashboardSection) -> some View {
        switch section {
        case .overview:
            Image(systemName: "rectangle.grid.2x2")
        case .cpu:
            Image(systemName: "cpu")
        case .memory:
            Image(systemName: "memorychip")
        case .battery:
            Image(systemName: "battery.75")
        case .network:
            Image(systemName: "network")
        case .temperature:
            Image(systemName: "thermometer.medium")
        case .disk:
            Image(systemName: "internaldrive")
        case .settings:
            Image(systemName: "gearshape")
        }
    }

    private func detailSubtitle(for section: DashboardSection) -> String {
        switch section {
        case .overview:
            return "Live summary"
        case .cpu:
            return "Load, GPU, FPS, processes"
        case .memory:
            return "Pressure, composition, swap, pages"
        case .battery:
            return "Charge, draw, health, energy"
        case .network:
            return "Throughput, interfaces, IP, VPN"
        case .temperature:
            return "Sensors, presets, fans, history"
        case .disk:
            return "Capacity, read/write, SMART"
        case .settings:
            return "Controls, diagnostics, layout"
        }
    }

    private var overviewSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overview")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardPalette.primaryText)
                    Text("Live summary")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Spacer()

                Text(statusStore.snapshot.privilegedTemperatureHealthy ? "Live sensors" : "Sensor fallback")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusStore.snapshot.privilegedTemperatureHealthy ? DashboardPalette.success : DashboardPalette.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill((statusStore.snapshot.privilegedTemperatureHealthy ? DashboardPalette.success : DashboardPalette.warning).opacity(0.12))
                    )
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 120), spacing: 10, alignment: .leading), count: 6),
                alignment: .leading,
                spacing: 10
            ) {
                summaryTile("CPU", value: cpuSummaryText, caption: "Total load", tint: DashboardPalette.cpuAccent, systemImage: "cpu")
                summaryTile("Memory", value: memorySummaryText, caption: "Used", tint: DashboardPalette.memoryAccent, systemImage: "memorychip")
                summaryTile("Battery", value: batterySummaryText, caption: coordinator.batteryFeatureStore.isCharging ? "Charging" : "Charge", tint: DashboardPalette.batteryAccent, systemImage: "battery.75")
                summaryTile("Temp", value: temperatureSummaryText, caption: "Primary sensor", tint: DashboardPalette.temperatureAccent, systemImage: "thermometer.medium")
                summaryTile("Network", value: networkSummaryText, caption: "Down / Up", tint: DashboardPalette.networkAccent, systemImage: "network")
                summaryTile("Disk", value: diskSummaryText, caption: "Free", tint: DashboardPalette.diskAccent, systemImage: "internaldrive")
            }
        }
        .padding(14)
        .dashboardSurface(padding: 0, cornerRadius: 8)
    }

    private func summaryTile(_ title: String, value: String, caption: String, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.13))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DashboardPalette.tertiaryText)
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardPalette.insetFill.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                )
        )
    }

    private var cpuSummaryText: String {
        let percent = max(0, 100 - coordinator.cpuUsageSurfaceStore.snapshot.summary.idlePercent)
        return UnitsFormatter.format(percent, unit: .percent)
    }

    private var memorySummaryText: String {
        let store = coordinator.memoryFeatureStore
        let total = max(store.usedBytes + store.freeBytes, 1)
        return UnitsFormatter.format((store.usedBytes / total) * 100, unit: .percent)
    }

    private var batterySummaryText: String {
        UnitsFormatter.format(coordinator.batteryFeatureStore.chargePercent, unit: .percent)
    }

    private var temperatureSummaryText: String {
        guard let latest = coordinator.temperatureFeatureStore.primarySamples.last?.value else { return "--" }
        return UnitsFormatter.format(latest, unit: .celsius)
    }

    private var networkSummaryText: String {
        let store = coordinator.networkFeatureStore
        let down = UnitsFormatter.format(store.inboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit)
        let up = UnitsFormatter.format(store.outboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit)
        return "\(down) / \(up)"
    }

    private var diskSummaryText: String {
        UnitsFormatter.format(coordinator.diskFeatureStore.freeBytes, unit: .bytes)
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
