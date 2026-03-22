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
                        DashboardSectionLabel(title: "Charge", tint: DashboardPalette.secondaryText)
                        Text(UnitsFormatter.format(featureStore.chargePercent, unit: .percent))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(DashboardPalette.primaryText)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        DashboardSectionLabel(title: "State", tint: DashboardPalette.secondaryText)
                        Text(batteryStateText)
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(DashboardPalette.primaryText)
                    }
                }
                .dashboardSurface()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        DashboardSectionLabel(title: "Current", tint: DashboardPalette.secondaryText)
                        if let current = featureStore.currentMilliamps {
                            Text(UnitsFormatter.format(current, unit: .milliamps))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.primaryText)
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.tertiaryText)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        DashboardSectionLabel(title: powerLabelTitle, tint: DashboardPalette.secondaryText)
                        if let power = featureStore.powerWatts {
                            Text(UnitsFormatter.format(power, unit: .watts))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.primaryText)
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.tertiaryText)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        DashboardSectionLabel(title: "Time Remaining", tint: DashboardPalette.secondaryText)
                        if let minutes = featureStore.timeRemainingMinutes {
                            Text(UnitsFormatter.format(minutes, unit: .minutes))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.primaryText)
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.tertiaryText)
                        }
                    }
                }
                .dashboardSurface()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        DashboardSectionLabel(title: "Health", tint: DashboardPalette.secondaryText)
                        if let health = featureStore.healthPercent {
                            Text(UnitsFormatter.format(health, unit: .percent))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.primaryText)
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.tertiaryText)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        DashboardSectionLabel(title: "Cycle Count", tint: DashboardPalette.secondaryText)
                        if let cycleCount = featureStore.cycleCount {
                            Text(String(format: "%.0f", cycleCount))
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.primaryText)
                        } else {
                            Text("--")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(DashboardPalette.tertiaryText)
                        }
                    }
                }
                .dashboardSurface()

            MetricChartView(
                title: "Battery Charge",
                samples: featureStore.chargeSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.batteryAccent
            )

            MetricChartView(
                title: powerChartTitle,
                samples: featureStore.powerSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: featureStore.isCharging ? DashboardPalette.batteryAccent : DashboardPalette.cpuAccent
            )
            } else {
                Text("Battery Unavailable")
                    .font(.headline)
                    .foregroundStyle(DashboardPalette.primaryText)
                Text("No internal battery telemetry is available on this device.")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
        }
        .foregroundStyle(DashboardPalette.primaryText)
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
