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
                    DashboardReadoutCell(
                        title: "Charge",
                        value: UnitsFormatter.format(featureStore.chargePercent, unit: .percent),
                        tint: DashboardPalette.batteryAccent
                    )
                    DashboardReadoutCell(
                        title: "State",
                        value: batteryStateText,
                        tint: DashboardPalette.secondaryText
                    )
                }
                .dashboardSurface(padding: 16, cornerRadius: 20)

                HStack {
                    DashboardReadoutCell(
                        title: "Current",
                        value: featureStore.currentMilliamps.map { UnitsFormatter.format($0, unit: .milliamps) } ?? "--",
                        tint: DashboardPalette.cpuAccent,
                        valueColor: featureStore.currentMilliamps == nil ? DashboardPalette.tertiaryText : DashboardPalette.primaryText
                    )
                    DashboardReadoutCell(
                        title: powerLabelTitle,
                        value: featureStore.powerWatts.map { UnitsFormatter.format($0, unit: .watts) } ?? "--",
                        tint: DashboardPalette.batteryAccent,
                        valueColor: featureStore.powerWatts == nil ? DashboardPalette.tertiaryText : DashboardPalette.primaryText
                    )
                    DashboardReadoutCell(
                        title: "Time Remaining",
                        value: featureStore.timeRemainingMinutes.map { UnitsFormatter.format($0, unit: .minutes) } ?? "--",
                        tint: DashboardPalette.secondaryText,
                        valueColor: featureStore.timeRemainingMinutes == nil ? DashboardPalette.tertiaryText : DashboardPalette.primaryText
                    )
                }
                .dashboardSurface(padding: 16, cornerRadius: 20)

                HStack {
                    DashboardReadoutCell(
                        title: "Health",
                        value: featureStore.healthPercent.map { UnitsFormatter.format($0, unit: .percent) } ?? "--",
                        tint: DashboardPalette.batteryAccent,
                        valueColor: featureStore.healthPercent == nil ? DashboardPalette.tertiaryText : DashboardPalette.primaryText
                    )
                    DashboardReadoutCell(
                        title: "Cycle Count",
                        value: featureStore.cycleCount.map { String(format: "%.0f", $0) } ?? "--",
                        tint: DashboardPalette.secondaryText,
                        valueColor: featureStore.cycleCount == nil ? DashboardPalette.tertiaryText : DashboardPalette.primaryText
                    )
                    Spacer(minLength: 0)
                }
                .dashboardSurface(padding: 16, cornerRadius: 20)

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
