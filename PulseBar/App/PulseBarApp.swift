import SwiftUI

@main
struct PulseBarApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(coordinator: coordinator, statusStore: coordinator.dashboardStatusStore)
                .frame(minWidth: 520, minHeight: 420)
        } label: {
            MenuBarSummaryView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                coordinator: coordinator,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
            )
                .frame(width: 460)
                .padding()
        }
    }
}
