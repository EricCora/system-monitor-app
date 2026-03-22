import SwiftUI

@main
struct PulseBarApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(coordinator: coordinator, statusStore: coordinator.dashboardStatusStore)
                .frame(minWidth: 860, minHeight: 720)
        } label: {
            MenuBarSummaryView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                coordinator: coordinator,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
            )
                .frame(width: 620)
                .padding()
        }
    }
}
