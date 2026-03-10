import SwiftUI
import PulseBarCore

struct BatteryTabView: View {
    let coordinator: AppCoordinator
    @ObservedObject var featureStore: BatteryFeatureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if coordinator.hasBatteryTelemetry() {
                ChartWindowPicker(
                    options: coordinator.visibleChartWindows,
                    selection: Binding(
                        get: { coordinator.batteryChartWindow },
                        set: { coordinator.batteryChartWindow = $0 }
                    )
                )

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Charge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(UnitsFormatter.format(featureStore.chargePercent, unit: .percent))
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
                        if let current = featureStore.currentMilliamps {
                            Text(UnitsFormatter.format(current, unit: .milliamps))
                                .font(.title3.monospacedDigit())
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(powerLabelTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let power = featureStore.powerWatts {
                            Text(UnitsFormatter.format(power, unit: .watts))
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
                        if let minutes = featureStore.timeRemainingMinutes {
                            Text(UnitsFormatter.format(minutes, unit: .minutes))
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
                        if let health = featureStore.healthPercent {
                            Text(UnitsFormatter.format(health, unit: .percent))
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
                        if let cycleCount = featureStore.cycleCount {
                            Text(String(format: "%.0f", cycleCount))
                                .font(.title3.monospacedDigit())
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                        }
                    }
                }

            MetricChartView(
                title: "Battery Charge",
                samples: featureStore.chargeSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
            )

            MetricChartView(
                title: powerChartTitle,
                samples: featureStore.powerSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
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
            coordinator.refreshBatterySurface()
        }
        .task(id: coordinator.batteryChartWindow.rawValue) {
            coordinator.refreshBatterySurface()
        }
    }

    private var batteryStateText: String {
        featureStore.isCharging ? "Charging" : "Discharging"
    }

    private var isCharging: Bool {
        featureStore.isCharging
    }

    private var powerLabelTitle: String {
        isCharging ? "Power Gain" : "Power Use"
    }

    private var powerChartTitle: String {
        isCharging ? "Battery Power Gain" : "Battery Power Use"
    }
}
