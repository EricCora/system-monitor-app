import SwiftUI
import PulseBarCore

struct BatteryTabView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var chargeSamples: [MetricSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if coordinator.hasBatteryTelemetry() {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Charge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(UnitsFormatter.format(coordinator.latestValue(for: .batteryChargePercent)?.value ?? 0, unit: .percent))
                            .font(.title3.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("State")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(batteryStateText)
                            .font(.title3.monospacedDigit())
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let sample = coordinator.latestValue(for: .batteryCurrentMilliAmps) {
                            Text(UnitsFormatter.format(sample.value, unit: .milliamps))
                                .font(.title3.monospacedDigit())
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time Remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let sample = coordinator.latestValue(for: .batteryTimeRemainingMinutes) {
                            Text(UnitsFormatter.format(sample.value, unit: .minutes))
                                .font(.title3.monospacedDigit())
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Health")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let sample = coordinator.latestValue(for: .batteryHealthPercent) {
                            Text(UnitsFormatter.format(sample.value, unit: .percent))
                                .font(.title3.monospacedDigit())
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cycle Count")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let sample = coordinator.latestValue(for: .batteryCycleCount) {
                            Text(String(format: "%.0f", sample.value))
                                .font(.title3.monospacedDigit())
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                        }
                    }
                }

                MetricChartView(
                    title: "Battery Charge",
                    samples: chargeSamples,
                    throughputUnit: coordinator.throughputUnit
                )
            } else {
                Text("Battery Unavailable")
                    .font(.headline)
                Text("No internal battery telemetry is available on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await refresh()
        }
        .onReceive(coordinator.$latestSamples) { _ in
            Task { await refresh() }
        }
    }

    private var batteryStateText: String {
        guard let chargingSample = coordinator.latestValue(for: .batteryIsCharging) else {
            return "--"
        }
        return chargingSample.value >= 0.5 ? "Charging" : "Discharging"
    }

    private func refresh() async {
        chargeSamples = await coordinator.series(for: .batteryChargePercent)
    }
}
