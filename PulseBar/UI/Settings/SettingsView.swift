import SwiftUI
import PulseBarCore

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Form {
            Section("Sampling") {
                HStack {
                    Text("Interval")
                    Slider(value: $coordinator.sampleInterval, in: 1...10, step: 1)
                    Text("\(Int(coordinator.sampleInterval))s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Picker("Graph Window", selection: $coordinator.selectedWindow) {
                    ForEach(TimeWindow.allCases, id: \.self) { window in
                        Text(window.label).tag(window)
                    }
                }
            }

            Section("Menu Bar Items") {
                Toggle("CPU", isOn: $coordinator.showCPUInMenu)
                Toggle("Memory", isOn: $coordinator.showMemoryInMenu)
                Toggle("Network", isOn: $coordinator.showNetworkInMenu)
                Toggle("Disk", isOn: $coordinator.showDiskInMenu)
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
        }
        .formStyle(.grouped)
    }
}
