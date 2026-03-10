import SwiftUI
import PulseBarCore

struct DashboardView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var statusStore: DashboardStatusStore
    @StateObject private var paneController = DetachedMetricsPaneController()
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

                    Text(statusStore.snapshot.currentPowerSourceDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Section", selection: $selectedTab) {
                    ForEach(DashboardTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)

                Divider()
            }
            .padding(.bottom, 8)
            .layoutPriority(2)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding()
        .onAppear {
            coordinator.setActiveDashboardTab(selectedTab)
        }
        .onChange(of: selectedTab) { newValue in
            coordinator.setActiveDashboardTab(newValue)
        }
        .onDisappear {
            coordinator.setActiveDashboardTab(nil)
        }
    }
}
