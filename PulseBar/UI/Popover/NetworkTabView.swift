import SwiftUI
import PulseBarCore

struct NetworkTabView: View {
    let coordinator: AppCoordinator
    @ObservedObject var featureStore: NetworkFeatureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: Binding(
                    get: { coordinator.networkChartWindow },
                    set: { coordinator.networkChartWindow = $0 }
                )
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    DashboardSectionLabel(title: "Inbound", tint: DashboardPalette.secondaryText)
                    Text(UnitsFormatter.format(
                        featureStore.inboundBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    DashboardSectionLabel(title: "Outbound", tint: DashboardPalette.secondaryText)
                    Text(UnitsFormatter.format(
                        featureStore.outboundBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)
                }
            }
            .dashboardSurface()

            MetricChartView(
                title: "Inbound Throughput",
                samples: featureStore.inboundSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.networkAccent
            )

            MetricChartView(
                title: "Outbound Throughput",
                samples: featureStore.outboundSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.cpuAccent
            )

            if !interfaceRates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    DashboardSectionLabel(title: "Interfaces", tint: DashboardPalette.secondaryText)

                    ForEach(Array(interfaceRates.enumerated()), id: \.element.id) { index, rate in
                        HStack {
                            Text(rate.interface)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(DashboardPalette.primaryText)
                            if index == 0 {
                                Text("Primary")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DashboardPalette.selectionFill, in: Capsule())
                                    .foregroundStyle(DashboardPalette.primaryText)
                            }
                            Spacer()
                            Text("↓\(UnitsFormatter.format(rate.inboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DashboardPalette.networkAccent)
                            Text("↑\(UnitsFormatter.format(rate.outboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(DashboardPalette.cpuAccent)
                        }
                    }
                }
                .dashboardSurface()
            }
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .task {
            coordinator.refreshNetworkSurface()
        }
        .task(id: coordinator.networkChartWindow.rawValue) {
            coordinator.refreshNetworkSurface()
        }
    }

    private var interfaceRates: [NetworkInterfaceRate] {
        featureStore.interfaceRates
    }
}
