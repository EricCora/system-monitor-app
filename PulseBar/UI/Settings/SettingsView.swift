import SwiftUI
import PulseBarCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var diagnosticsStore: PerformanceDiagnosticsStore
    @State private var selectedSection: SettingsSection? = .general
    @State private var newSensorPresetName = ""

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190)
            .scrollContentBackground(.hidden)
            .background(DashboardPalette.windowBackground)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionContent
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [DashboardPalette.canvasTop, DashboardPalette.canvasBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationTitle(selectedSection?.title ?? SettingsSection.general.title)
        }
        .preferredColorScheme(.light)
        .foregroundStyle(DashboardPalette.primaryText)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection ?? .general {
        case .general:
            generalSection
        case .charts:
            chartsSection
        case .cpu:
            cpuSection
        case .memory:
            memorySection
        case .temperature:
            temperatureSection
        case .alerts:
            alertsSection
        case .diagnostics:
            diagnosticsSection
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard("Profiles") {
                Picker("Active Profile", selection: $coordinator.selectedProfileID) {
                    ForEach(ProfileID.allCases, id: \.self) { profile in
                        Text(profile.label).tag(profile)
                    }
                }

                    Text(profileExplanation)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)

                Toggle("Auto-switch by power source", isOn: $coordinator.autoSwitchProfilesEnabled)

                if coordinator.autoSwitchProfilesEnabled {
                    Picker("AC Profile", selection: $coordinator.autoSwitchACProfile) {
                        ForEach(ProfileID.allCases.filter { $0 != .custom }, id: \.self) { profile in
                            Text(profile.label).tag(profile)
                        }
                    }

                    Picker("Battery Profile", selection: $coordinator.autoSwitchBatteryProfile) {
                        ForEach(ProfileID.allCases.filter { $0 != .custom }, id: \.self) { profile in
                            Text(profile.label).tag(profile)
                        }
                    }
                }
            }

            settingsCard("Sampling and Units") {
                HStack {
                    Text("Refresh Frequency")
                    Slider(value: $coordinator.globalSamplingInterval, in: 1...10, step: 1)
                    Text("\(Int(coordinator.globalSamplingInterval))s")
                        .monospacedDigit()
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Picker("Throughput", selection: $coordinator.throughputUnit) {
                    ForEach(ThroughputDisplayUnit.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }

                Toggle("Start PulseBar at login", isOn: $coordinator.launchAtLoginEnabled)

                if let message = coordinator.launchAtLoginStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }

            settingsCard("Menu Bar Items") {
                Picker("Display Mode", selection: $coordinator.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Toggle("CPU", isOn: $coordinator.showCPUInMenu)
                metricStylePicker(.cpu)
                Toggle("Memory", isOn: $coordinator.showMemoryInMenu)
                metricStylePicker(.memory)
                Toggle("Battery", isOn: $coordinator.showBatteryInMenu)
                metricStylePicker(.battery)
                Toggle("Network", isOn: $coordinator.showNetworkInMenu)
                metricStylePicker(.network)
                Toggle("Disk", isOn: $coordinator.showDiskInMenu)
                metricStylePicker(.disk)
                Toggle("Temperature", isOn: $coordinator.showTemperatureInMenu)
                metricStylePicker(.temperature)
            }

            settingsCard("Dashboard Layout") {
                Picker("Layout", selection: $coordinator.dashboardLayout) {
                    ForEach(DashboardLayoutMode.allCases, id: \.self) { layout in
                        Text(layout.label).tag(layout)
                    }
                }

                ForEach(Array(coordinator.dashboardCardOrder.enumerated()), id: \.element) { index, card in
                    HStack {
                        Text(card.label)
                        Spacer()
                        Button("Up") {
                            coordinator.moveDashboardCard(from: index, direction: -1)
                        }
                        .disabled(index == 0)

                        Button("Down") {
                            coordinator.moveDashboardCard(from: index, direction: 1)
                        }
                        .disabled(index == coordinator.dashboardCardOrder.count - 1)
                    }
                }
            }
        }
    }

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard("Appearance") {
                HStack {
                    Text("Area Opacity")
                    Slider(value: $coordinator.chartAreaOpacity, in: 0.05...0.5, step: 0.01)
                    Text(String(format: "%.2f", coordinator.chartAreaOpacity))
                        .monospacedDigit()
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Text("Detached charts support click-drag horizontal zoom and double-click reset.")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            settingsCard("Visible Chart Windows") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(ChartWindow.allCases, id: \.self) { window in
                        Button {
                            toggleChartWindow(window)
                        } label: {
                            HStack {
                                Image(systemName: coordinator.visibleChartWindows.contains(window) ? "checkmark.circle.fill" : "circle")
                                Text(window.accessibilityLabel)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(coordinator.visibleChartWindows.contains(window) ? DashboardPalette.selectionFill : DashboardPalette.insetFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(coordinator.visibleChartWindows.contains(window) ? DashboardPalette.cpuAccent.opacity(0.35) : DashboardPalette.divider, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("These windows appear on every chart picker in the app.")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
        }
    }

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard("Process and Layout") {
                Stepper(
                    "CPU Processes: \(coordinator.cpuProcessCount)",
                    value: $coordinator.cpuProcessCount,
                    in: 3...12
                )

                Toggle("Enable live compositor FPS capture", isOn: $coordinator.liveCompositorFPSEnabled)

                Text("Turn this on only if you want true compositor FPS telemetry. macOS may ask for Screen Recording permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(coordinator.cpuMenuLayout.orderedSections.enumerated()), id: \.element) { index, section in
                    HStack {
                        Toggle(
                            section.label,
                            isOn: Binding(
                                get: { isCPUSectionVisible(section) },
                                set: { toggleCPUSection(section, isVisible: $0) }
                            )
                        )

                        Spacer()

                        Button("Up") {
                            moveCPUSection(from: index, direction: -1)
                        }
                        .disabled(index == 0)

                        Button("Down") {
                            moveCPUSection(from: index, direction: 1)
                        }
                        .disabled(index == coordinator.cpuMenuLayout.orderedSections.count - 1)
                    }
                }
            }
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard("Process and Layout") {
                Stepper(
                    "Memory Processes: \(coordinator.memoryProcessCount)",
                    value: $coordinator.memoryProcessCount,
                    in: 3...12
                )

                ForEach(Array(coordinator.memoryMenuLayout.orderedSections.enumerated()), id: \.element) { index, section in
                    HStack {
                        Toggle(
                            section.label,
                            isOn: Binding(
                                get: { isMemorySectionVisible(section) },
                                set: { toggleMemorySection(section, isVisible: $0) }
                            )
                        )

                        Spacer()

                        Button("Up") {
                            moveMemorySection(from: index, direction: -1)
                        }
                        .disabled(index == 0)

                        Button("Down") {
                            moveMemorySection(from: index, direction: 1)
                        }
                        .disabled(index == coordinator.memoryMenuLayout.orderedSections.count - 1)
                    }
                }
            }
        }
    }

    private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard("Sampling") {
                Toggle("Enable privileged temperature sampling", isOn: $coordinator.privilegedTemperatureEnabled)

                if let modeDescription = temperatureModeDescription {
                    Text(modeDescription)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                if coordinator.privilegedTemperatureEnabled && !coordinator.privilegedTemperatureHealthy {
                    Button("Retry Privileged Sampling") {
                        coordinator.retryPrivilegedTemperatureNow()
                    }
                }

                if let status = coordinator.privilegedTemperatureStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                if let success = coordinator.privilegedTemperatureLastSuccessMessage {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                if let fanGate = coordinator.fanParityGateMessage {
                    Text("Fan parity: \(fanGate)")
                        .font(.caption)
                        .foregroundStyle(coordinator.fanParityGateBlocked ? DashboardPalette.danger : DashboardPalette.secondaryText)
                }
            }

            settingsCard("Favorites and Presets") {
                if coordinator.latestSensorChannels.isEmpty {
                    Text("Favorite sensors become available after privileged sensors have been sampled.")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                } else {
                    ForEach(Array(coordinator.latestSensorChannels.prefix(12)), id: \.id) { sensor in
                        Button {
                            coordinator.toggleFavoriteSensor(id: sensor.id)
                        } label: {
                            HStack {
                                Image(systemName: coordinator.favoriteSensorIDs.contains(sensor.id) ? "star.fill" : "star")
                                    .foregroundStyle(coordinator.favoriteSensorIDs.contains(sensor.id) ? DashboardPalette.diskAccent : DashboardPalette.secondaryText)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sensor.displayName)
                                        .foregroundStyle(DashboardPalette.primaryText)
                                    Text(sensor.category.label)
                                        .font(.caption2)
                                        .foregroundStyle(DashboardPalette.secondaryText)
                                }
                                Spacer()
                                Text(TemperatureHistoryHelpers.valueText(for: sensor))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(DashboardPalette.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                HStack {
                    TextField("Preset name", text: $newSensorPresetName)
                    Button("Save Favorites as Preset") {
                        coordinator.saveSensorPreset(name: newSensorPresetName, sensorIDs: coordinator.favoriteSensorIDs)
                        if !newSensorPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            newSensorPresetName = ""
                        }
                    }
                    .disabled(coordinator.favoriteSensorIDs.isEmpty || newSensorPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if coordinator.sensorPresets.isEmpty {
                    Text("No saved sensor presets yet.")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                } else {
                    ForEach(coordinator.sensorPresets, id: \.id) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                Text("\(preset.sensorIDs.count) sensors")
                                    .font(.caption)
                                    .foregroundStyle(DashboardPalette.secondaryText)
                            }
                            Spacer()
                            Button("Use") {
                                coordinator.selectedSensorPresetID = preset.id
                            }
                            Button("Delete") {
                                coordinator.deleteSensorPreset(id: preset.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            alertCard(
                "CPU Alert",
                enabled: $coordinator.cpuAlertEnabled,
                thresholdText: "\(Int(coordinator.cpuAlertThreshold))%",
                thresholdControl: AnyView(
                    Slider(value: $coordinator.cpuAlertThreshold, in: 1...100, step: 1)
                ),
                duration: $coordinator.cpuAlertDuration
            )

            alertCard(
                "Temperature Alert",
                enabled: $coordinator.temperatureAlertEnabled,
                thresholdText: "\(Int(coordinator.temperatureAlertThreshold)) C",
                thresholdControl: AnyView(
                    Slider(value: $coordinator.temperatureAlertThreshold, in: 40...110, step: 1)
                ),
                duration: $coordinator.temperatureAlertDuration
            )

            alertCard(
                "Memory Alert",
                enabled: $coordinator.memoryPressureAlertEnabled,
                thresholdText: "\(Int(coordinator.memoryPressureAlertThreshold))%",
                thresholdControl: AnyView(
                    Slider(value: $coordinator.memoryPressureAlertThreshold, in: 1...100, step: 1)
                ),
                duration: $coordinator.memoryPressureAlertDuration
            )

            settingsCard("Disk Free Alert") {
                Toggle("Enable low disk free-space alert", isOn: $coordinator.diskFreeAlertEnabled)

                HStack {
                    Text("Threshold")
                    Slider(
                        value: Binding(
                            get: { coordinator.diskFreeAlertThresholdBytes / 1_073_741_824 },
                            set: { coordinator.diskFreeAlertThresholdBytes = $0 * 1_073_741_824 }
                        ),
                        in: 1...500,
                        step: 1
                    )
                    Text("\(Int(coordinator.diskFreeAlertThresholdBytes / 1_073_741_824)) GB")
                        .monospacedDigit()
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Stepper(
                    "Duration: \(coordinator.diskFreeAlertDuration)s",
                    value: $coordinator.diskFreeAlertDuration,
                    in: 5...600,
                    step: 5
                )
            }

            settingsCard("Recent Alerts") {
                if coordinator.recentAlerts.isEmpty {
                    Text("No alerts fired yet in this session.")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                } else {
                    ForEach(coordinator.recentAlerts) { alert in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.subheadline.weight(.semibold))
                            Text(alert.body)
                                .font(.caption)
                                .foregroundStyle(DashboardPalette.secondaryText)
                            Text(alert.deliveredAt.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(DashboardPalette.secondaryText)
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard("Provider Failures") {
                if coordinator.recentProviderFailures.isEmpty {
                    Text("No provider failures recorded in this session.")
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                } else {
                    ForEach(coordinator.recentProviderFailures) { failure in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.providerID)
                                .font(.subheadline.weight(.semibold))
                            Text(failure.message)
                                .font(.caption)
                                .foregroundStyle(DashboardPalette.secondaryText)
                            Text(failure.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(DashboardPalette.secondaryText)
                        }
                    }
                }
            }

            settingsCard("Runtime Status") {
                diagnosticsRow("Metric history", coordinator.historyStoreStatusMessage)
                diagnosticsRow("Memory history", coordinator.memoryHistoryStoreStatusMessage)
                diagnosticsRow("Temperature history", coordinator.temperatureHistoryStoreStatusMessage)
                diagnosticsRow("CPU processes", coordinator.cpuProcessesStatusMessage)
                diagnosticsRow("Memory processes", coordinator.memoryProcessesStatusMessage)
                diagnosticsRow("Temperature", coordinator.privilegedTemperatureStatusMessage)
            }

            settingsCard("Performance Counters") {
                diagnosticsRow("CPU process polls/min", "\(diagnosticsStore.snapshot.cpuProcessPollsPerMinute)")
                diagnosticsRow("Memory process polls/min", "\(diagnosticsStore.snapshot.memoryProcessPollsPerMinute)")
                diagnosticsRow("Compact history reloads/min", "\(diagnosticsStore.snapshot.compactChartReloadsPerMinute)")
                diagnosticsRow("Detached pane queries/min", "\(diagnosticsStore.snapshot.detachedPaneQueriesPerMinute)")
                diagnosticsRow("GPU snapshot reads/min", "\(diagnosticsStore.snapshot.gpuSnapshotReadsPerMinute)")
                diagnosticsRow("FPS status refreshes/min", "\(diagnosticsStore.snapshot.fpsStatusRefreshesPerMinute)")
                diagnosticsRow("Privileged status refreshes/min", "\(diagnosticsStore.snapshot.privilegedStatusRefreshesPerMinute)")
                diagnosticsRow("Disk fallbacks/min", "\(diagnosticsStore.snapshot.diskFallbacksPerMinute)")
                diagnosticsRow("Chart prep avg", millisecondsText(diagnosticsStore.snapshot.averageChartPreparationMilliseconds))
                diagnosticsRow("Chart prep last", millisecondsText(diagnosticsStore.snapshot.lastChartPreparationMilliseconds))
                diagnosticsRow("Batch handler avg", millisecondsText(diagnosticsStore.snapshot.averageBatchHandlerMilliseconds))
                diagnosticsRow("Batch handler last", millisecondsText(diagnosticsStore.snapshot.lastBatchHandlerMilliseconds))
                diagnosticsRow("Active surfaces", diagnosticsStore.snapshot.surfaceActivitySummary)
            }
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DashboardPalette.primaryText)
            content()
        }
        .dashboardSurface(padding: 16, cornerRadius: 14)
    }

    private func alertCard(
        _ title: String,
        enabled: Binding<Bool>,
        thresholdText: String,
        thresholdControl: AnyView,
        duration: Binding<Int>
    ) -> some View {
        settingsCard(title) {
            Toggle("Enabled", isOn: enabled)
            HStack {
                Text("Threshold")
                thresholdControl
                Text(thresholdText)
                    .monospacedDigit()
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
            Stepper("Duration: \(duration.wrappedValue)s", value: duration, in: 5...600, step: 5)
        }
    }

    @ViewBuilder
    private func diagnosticsRow(_ title: String, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(DashboardPalette.secondaryText)
            Spacer()
            Text(value ?? "OK")
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func toggleChartWindow(_ window: ChartWindow) {
        var windows = coordinator.visibleChartWindows
        if let index = windows.firstIndex(of: window) {
            guard windows.count > 1 else { return }
            windows.remove(at: index)
        } else {
            windows.append(window)
        }
        coordinator.visibleChartWindows = ChartWindow.allCases.filter { windows.contains($0) }
    }

    private var profileExplanation: String {
        switch coordinator.selectedProfileID {
        case .quiet:
            return "Quiet: slower sampling, minimal menu items, least background activity."
        case .balanced:
            return "Balanced: default mode with moderate sampling and common metrics visible."
        case .performance:
            return "Performance: fastest sampling and fullest metric visibility."
        case .custom:
            return "Custom: your personalized settings. Edit controls below to tune behavior."
        }
    }

    private var temperatureModeDescription: String? {
        if coordinator.privilegedTemperatureEnabled {
            if coordinator.privilegedTemperatureHealthy {
                return "Enhanced temperature mode is active. PulseBar tries direct IOHID first, reuses a running helper if needed, and only asks for admin access when you explicitly retry."
            }
            return "Enhanced temperature mode will try direct IOHID on launch, reuse a running helper if one is already available, and otherwise stay in standard mode until you explicitly retry."
        }
        return "Standard mode uses macOS thermal state. Enable privileged mode for Celsius and fan RPM history."
    }

    private func isCPUSectionVisible(_ section: CPUMenuSectionID) -> Bool {
        coordinator.cpuMenuLayout.visibleSections.contains(section)
    }

    private func toggleCPUSection(_ section: CPUMenuSectionID, isVisible: Bool) {
        if !isVisible && coordinator.cpuMenuLayout.visibleSections.count <= 1 {
            return
        }
        var layout = coordinator.cpuMenuLayout
        layout.setHidden(!isVisible, for: section)
        coordinator.cpuMenuLayout = layout
    }

    private func moveCPUSection(from index: Int, direction: Int) {
        var layout = coordinator.cpuMenuLayout
        let destination = index + direction
        guard destination >= 0, destination < layout.orderedSections.count else { return }
        layout.orderedSections.swapAt(index, destination)
        layout.reconcile()
        coordinator.cpuMenuLayout = layout
    }

    private func isMemorySectionVisible(_ section: MemoryMenuSectionID) -> Bool {
        coordinator.memoryMenuLayout.visibleSections.contains(section)
    }

    private func toggleMemorySection(_ section: MemoryMenuSectionID, isVisible: Bool) {
        if !isVisible && coordinator.memoryMenuLayout.visibleSections.count <= 1 {
            return
        }
        var layout = coordinator.memoryMenuLayout
        layout.setHidden(!isVisible, for: section)
        coordinator.memoryMenuLayout = layout
    }

    private func moveMemorySection(from index: Int, direction: Int) {
        var layout = coordinator.memoryMenuLayout
        let destination = index + direction
        guard destination >= 0, destination < layout.orderedSections.count else { return }
        layout.orderedSections.swapAt(index, destination)
        layout.reconcile()
        coordinator.memoryMenuLayout = layout
    }

    private func millisecondsText(_ value: Double) -> String {
        String(format: "%.2f ms", value)
    }

    private func metricStylePicker(_ metric: MenuBarMetricID) -> some View {
        Picker("\(metric.label) Style", selection: Binding(
            get: { coordinator.menuBarMetricStyle(for: metric) },
            set: { coordinator.setMenuBarMetricStyle($0, for: metric) }
        )) {
            ForEach(MenuBarMetricStyle.allCases, id: \.self) { style in
                Text(style.label).tag(style)
            }
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case charts
    case cpu
    case memory
    case temperature
    case alerts
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .charts:
            return "Charts"
        case .cpu:
            return "CPU"
        case .memory:
            return "Memory"
        case .temperature:
            return "Temperature"
        case .alerts:
            return "Alerts"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .charts:
            return "chart.xyaxis.line"
        case .cpu:
            return "cpu"
        case .memory:
            return "memorychip"
        case .temperature:
            return "thermometer.medium"
        case .alerts:
            return "bell"
        case .diagnostics:
            return "stethoscope"
        }
    }
}
