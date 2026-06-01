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
                smoothingAlpha: coordinator.chartSmoothingAlpha,
                areaOpacity: coordinator.chartAreaOpacity
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
                    pendingAppAction = nil
                    coordinator.restartApplication()
                }
                .disabled(coordinator.isAppLifecycleTransitionInProgress)
            }
            if pendingAppAction == .quit {
                Button("Quit Now", role: .destructive) {
                    pendingAppAction = nil
                    coordinator.quitApplication()
                }
                .disabled(coordinator.isAppLifecycleTransitionInProgress)
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
                            guard pendingAppAction == nil else { return }
                            pendingAppAction = .restart
                        }

                        appActionButton(
                            systemImage: "power.circle.fill",
                            tint: DashboardPalette.danger,
                            helpText: "Quit PulseBar"
                        ) {
                            guard pendingAppAction == nil else { return }
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
        .disabled(coordinator.isAppLifecycleTransitionInProgress || pendingAppAction != nil)
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
                summaryTile("CPU", value: cpuSummaryText, caption: "Total load", tint: DashboardPalette.cpuAccent, systemImage: "cpu") {
                    coordinator.setDashboardSection(.cpu)
                }
                summaryTile("Memory", value: memorySummaryText, caption: "Used", tint: DashboardPalette.memoryAccent, systemImage: "memorychip") {
                    coordinator.setDashboardSection(.memory)
                }
                summaryTile("Battery", value: batterySummaryText, caption: coordinator.batteryFeatureStore.isCharging ? "Charging" : "Charge", tint: DashboardPalette.batteryAccent, systemImage: "battery.75") {
                    coordinator.setDashboardSection(.battery)
                }
                summaryTile("Temp", value: temperatureSummaryText, caption: "Primary sensor", tint: DashboardPalette.temperatureAccent, systemImage: "thermometer.medium") {
                    coordinator.setDashboardSection(.temperature)
                }
                summaryTile("Network", value: networkSummaryText, caption: "Down / Up", tint: DashboardPalette.networkAccent, systemImage: "network") {
                    coordinator.setDashboardSection(.network)
                }
                summaryTile("Disk", value: diskSummaryText, caption: "Free", tint: DashboardPalette.diskAccent, systemImage: "internaldrive") {
                    coordinator.setDashboardSection(.disk)
                }
            }
        }
        .padding(14)
        .dashboardSurface(padding: 0, cornerRadius: 8)
    }

    private func summaryTile(
        _ title: String,
        value: String,
        caption: String,
        tint: Color,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
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
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: action)
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
