import SwiftUI
import PulseBarCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Form {
            Section("Profiles") {
                Picker("Active Profile", selection: $coordinator.selectedProfileID) {
                    ForEach(ProfileID.allCases, id: \.self) { profile in
                        Text(profile.label).tag(profile)
                    }
                }

                Text(profileExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Tip: changing any setting manually switches to Custom.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Refresh frequency is global and no longer tied to the selected profile.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

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

            Section("Sampling") {
                HStack {
                    Text("Refresh Frequency")
                    Slider(value: $coordinator.globalSamplingInterval, in: 1...10, step: 1)
                    Text("\(Int(coordinator.globalSamplingInterval))s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Toggle("Enable live compositor FPS capture", isOn: $coordinator.liveCompositorFPSEnabled)

                Text("Off by default. Turn this on only if you want true compositor FPS telemetry. macOS may ask for Screen Recording permission when enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Graph Window", selection: $coordinator.selectedWindow) {
                    ForEach(TimeWindow.allCases, id: \.self) { window in
                        Text(window.label).tag(window)
                    }
                }
            }

            Section("CPU Menu Layout") {
                Stepper(
                    "CPU Processes: \(coordinator.cpuProcessCount)",
                    value: $coordinator.cpuProcessCount,
                    in: 3...12
                )

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

            Section("Memory Menu Layout") {
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

            Section("Menu Bar Items") {
                Toggle("CPU", isOn: $coordinator.showCPUInMenu)
                Toggle("Memory", isOn: $coordinator.showMemoryInMenu)
                Toggle("Battery", isOn: $coordinator.showBatteryInMenu)
                Toggle("Network", isOn: $coordinator.showNetworkInMenu)
                Toggle("Disk", isOn: $coordinator.showDiskInMenu)
                Toggle("Temperature", isOn: $coordinator.showTemperatureInMenu)
            }

            Section("Temperature") {
                Toggle("Enable privileged temperature sampling", isOn: $coordinator.privilegedTemperatureEnabled)
                if let modeDescription = temperatureModeDescription {
                    Text(modeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if coordinator.privilegedTemperatureEnabled && !coordinator.privilegedTemperatureHealthy {
                    Button("Retry Privileged Sampling") {
                        coordinator.retryPrivilegedTemperatureNow()
                    }
                }

                if let status = coordinator.privilegedTemperatureStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let success = coordinator.privilegedTemperatureLastSuccessMessage {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let fanGate = coordinator.fanParityGateMessage {
                    Text("Fan parity: \(fanGate)")
                        .font(.caption)
                        .foregroundStyle(coordinator.fanParityGateBlocked ? .red : .secondary)
                }

                if !coordinator.privilegedActiveSourceChain.isEmpty {
                    Text("Active source chain: \(coordinator.privilegedActiveSourceChain.joined(separator: " -> "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Units") {
                Picker("Throughput", selection: $coordinator.throughputUnit) {
                    ForEach(ThroughputDisplayUnit.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            Section("Launch At Login") {
                Toggle("Start PulseBar at login", isOn: $coordinator.launchAtLoginEnabled)
                if let message = coordinator.launchAtLoginStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("CPU Alert") {
                Toggle("Enable CPU threshold alert", isOn: $coordinator.cpuAlertEnabled)

                HStack {
                    Text("Threshold")
                    Slider(value: $coordinator.cpuAlertThreshold, in: 1...100, step: 1)
                    Text("\(Int(coordinator.cpuAlertThreshold))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Stepper("Duration: \(coordinator.cpuAlertDuration)s", value: $coordinator.cpuAlertDuration, in: 5...600, step: 5)
            }

            Section("Temperature Alert") {
                Toggle("Enable temperature threshold alert", isOn: $coordinator.temperatureAlertEnabled)

                HStack {
                    Text("Threshold")
                    Slider(value: $coordinator.temperatureAlertThreshold, in: 40...110, step: 1)
                    Text("\(Int(coordinator.temperatureAlertThreshold)) C")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Stepper("Duration: \(coordinator.temperatureAlertDuration)s", value: $coordinator.temperatureAlertDuration, in: 5...600, step: 5)
            }

            Section("Memory Alert") {
                Toggle("Enable memory pressure alert", isOn: $coordinator.memoryPressureAlertEnabled)

                HStack {
                    Text("Threshold")
                    Slider(value: $coordinator.memoryPressureAlertThreshold, in: 1...100, step: 1)
                    Text("\(Int(coordinator.memoryPressureAlertThreshold))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Stepper(
                    "Duration: \(coordinator.memoryPressureAlertDuration)s",
                    value: $coordinator.memoryPressureAlertDuration,
                    in: 5...600,
                    step: 5
                )
            }

            Section("Disk Free Alert") {
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
                        .foregroundStyle(.secondary)
                }

                Stepper(
                    "Duration: \(coordinator.diskFreeAlertDuration)s",
                    value: $coordinator.diskFreeAlertDuration,
                    in: 5...600,
                    step: 5
                )
            }

            Section("Recent Alerts") {
                if coordinator.recentAlerts.isEmpty {
                    Text("No alerts fired yet in this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.recentAlerts) { alert in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.subheadline.weight(.semibold))
                            Text(alert.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(alert.deliveredAt.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
                return "Privileged mode is enabled and active. Celsius readings come from IOHID sensors with powermetrics fallback."
            }
            // Avoid duplicate/conflicting text when a specific status/error message is already shown below.
            return nil
        }
        return "Standard mode uses macOS thermal state (qualitative). Enable privileged mode for Celsius readings."
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
}
