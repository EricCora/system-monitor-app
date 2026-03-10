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
                    Text("Inbound")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(
                        featureStore.inboundBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ))
                    .font(.title3.monospacedDigit())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Outbound")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(
                        featureStore.outboundBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ))
                    .font(.title3.monospacedDigit())
                }
            }

            MetricChartView(
                title: "Inbound Throughput",
                samples: featureStore.inboundSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
            )

            MetricChartView(
                title: "Outbound Throughput",
                samples: featureStore.outboundSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
            )

            if !interfaceRates.isEmpty {
                Divider()
                Text("Interfaces")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(Array(interfaceRates.enumerated()), id: \.element.id) { index, rate in
                    HStack {
                        Text(rate.interface)
                            .font(.callout.monospacedDigit())
                        if index == 0 {
                            Text("Primary")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Text("↓\(UnitsFormatter.format(rate.inboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))")
                            .font(.caption.monospacedDigit())
                        Text("↑\(UnitsFormatter.format(rate.outboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
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
