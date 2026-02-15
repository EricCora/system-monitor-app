import SwiftUI

@main
struct PulseBarApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(coordinator: coordinator)
                .frame(minWidth: 520, minHeight: 420)
        } label: {
            MenuBarSummaryView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(coordinator: coordinator)
                .frame(width: 460)
                .padding()
        }
    }
}
