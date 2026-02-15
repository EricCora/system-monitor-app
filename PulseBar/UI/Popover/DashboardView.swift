import SwiftUI
import PulseBarCore

struct DashboardView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var selectedTab: DashboardTab = .cpu

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("Profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Profile", selection: $coordinator.selectedProfileID) {
                        ForEach(ProfileID.allCases, id: \.self) { profile in
                            Text(profile.label).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Spacer()

                    Text(coordinator.currentPowerSourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Section", selection: $selectedTab) {
                    ForEach(DashboardTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                Divider()
            }
            .padding(.bottom, 8)
            .layoutPriority(2)

            ScrollView {
                Group {
                    switch selectedTab {
                    case .cpu:
                        CPUTabView(coordinator: coordinator)
                    case .memory:
                        MemoryTabView(coordinator: coordinator)
                    case .network:
                        NetworkTabView(coordinator: coordinator)
                    case .temperature:
                        TemperatureTabView(coordinator: coordinator)
                    case .disk:
                        DiskTabView(coordinator: coordinator)
                    case .settings:
                        SettingsView(coordinator: coordinator)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding()
    }
}

private enum DashboardTab: CaseIterable {
    case cpu
    case memory
    case network
    case temperature
    case disk
    case settings

    var title: String {
        switch self {
        case .cpu:
            return "CPU"
        case .memory:
            return "Memory"
        case .network:
            return "Network"
        case .temperature:
            return "Temperature"
        case .disk:
            return "Disk"
        case .settings:
            return "Settings"
        }
    }
}
