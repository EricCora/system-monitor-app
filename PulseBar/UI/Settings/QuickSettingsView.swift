import AppKit
import SwiftUI
import PulseBarCore

struct QuickSettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var statusStore: DashboardStatusStore
    @ObservedObject var diagnosticsStore: PerformanceDiagnosticsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            quickCard("Profile") {
                Picker("Active Profile", selection: $coordinator.selectedProfileID) {
                    ForEach(ProfileID.allCases, id: \.self) { profile in
                        Text(profile.label).tag(profile)
                    }
                }
                .pickerStyle(.menu)

                Text(profileExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            quickCard("Sampling") {
                HStack {
                    Text("Refresh Frequency")
                    Slider(value: $coordinator.globalSamplingInterval, in: 1...10, step: 1)
                    Text("\(Int(coordinator.globalSamplingInterval))s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Toggle("Start PulseBar at login", isOn: $coordinator.launchAtLoginEnabled)

                if let message = coordinator.launchAtLoginStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            quickCard("Charts") {
                HStack {
                    Text("Area Opacity")
                    Slider(value: $coordinator.chartAreaOpacity, in: 0.05...0.5, step: 0.01)
                    Text(String(format: "%.2f", coordinator.chartAreaOpacity))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text("Detached charts support drag-to-zoom and double-click reset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            quickCard("Diagnostics") {
                if let message = statusStore.snapshot.privilegedTemperatureStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Temperature sampling is \(statusStore.snapshot.privilegedTemperatureHealthy ? "healthy" : "degraded").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(providerFailureSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                diagnosticsLine("Batch avg", value: millisecondsText(diagnosticsStore.snapshot.averageBatchHandlerMilliseconds))
                diagnosticsLine("Chart prep avg", value: millisecondsText(diagnosticsStore.snapshot.averageChartPreparationMilliseconds))
                diagnosticsLine("CPU polls/min", value: "\(diagnosticsStore.snapshot.cpuProcessPollsPerMinute)")
                diagnosticsLine("Mem polls/min", value: "\(diagnosticsStore.snapshot.memoryProcessPollsPerMinute)")
                diagnosticsLine("FPS refreshes/min", value: "\(diagnosticsStore.snapshot.fpsStatusRefreshesPerMinute)")
                diagnosticsLine("Active surfaces", value: diagnosticsStore.snapshot.surfaceActivitySummary)
            }

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Label("Open Full Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.cyan)

            content()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var providerFailureSummary: String {
        let count = statusStore.snapshot.providerFailureCount
        if count == 0 {
            return "No provider failures recorded in this session."
        }
        return "\(count) provider failure\(count == 1 ? "" : "s") recorded this session."
    }

    private var profileExplanation: String {
        switch coordinator.selectedProfileID {
        case .quiet:
            return "Quiet reduces menu noise and background activity."
        case .balanced:
            return "Balanced keeps the common metrics visible without extra churn."
        case .performance:
            return "Performance favors fast updates and broader telemetry."
        case .custom:
            return "Custom reflects your manual settings choices."
        }
    }

    private func diagnosticsLine(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func millisecondsText(_ value: Double) -> String {
        String(format: "%.2f ms", value)
    }
}
