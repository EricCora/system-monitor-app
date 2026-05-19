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
            ChartToolsStrip(
                smoothingAlpha: Binding(
                    get: { coordinator.chartSmoothingAlpha },
                    set: { coordinator.chartSmoothingAlpha = $0 }
                ),
                showsMinorGrid: Binding(
                    get: { coordinator.chartMinorGridEnabled },
                    set: { coordinator.chartMinorGridEnabled = $0 }
                )
            )

            HStack {
                DashboardReadoutCell(
                    title: "Inbound",
                    value: UnitsFormatter.format(
                        featureStore.inboundBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ),
                    tint: DashboardPalette.networkAccent
                )

                DashboardReadoutCell(
                    title: "Outbound",
                    value: UnitsFormatter.format(
                        featureStore.outboundBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ),
                    tint: DashboardPalette.cpuAccent
                )
            }
            .dashboardSurface(padding: 16, cornerRadius: 20)

            MetricChartView(
                title: "Inbound Throughput",
                samples: featureStore.inboundSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.networkAccent,
                displayOptions: ChartDisplayOptions(showsMinorGrid: coordinator.chartMinorGridEnabled, smoothingAlpha: coordinator.chartSmoothingAlpha)
            )

            MetricChartView(
                title: "Outbound Throughput",
                samples: featureStore.outboundSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.cpuAccent,
                displayOptions: ChartDisplayOptions(showsMinorGrid: coordinator.chartMinorGridEnabled, smoothingAlpha: coordinator.chartSmoothingAlpha)
            )

            if !readableInterfaceRates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        DashboardSectionLabel(title: "Interfaces", tint: DashboardPalette.secondaryText)
                        Spacer()
                        Text("Only active and recognizable interfaces are shown first.")
                            .font(.caption2)
                            .foregroundStyle(DashboardPalette.tertiaryText)
                    }

                    ForEach(Array(readableInterfaceRates.enumerated()), id: \.element.id) { index, rate in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(interfaceTitle(for: rate.interface))
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(DashboardPalette.primaryText)
                                    Text(rate.interface)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(DashboardPalette.tertiaryText)
                                }
                                Text(interfaceSubtitle(for: rate.interface, index: index))
                                    .font(.caption2)
                                    .foregroundStyle(DashboardPalette.secondaryText)
                            }

                            if index == 0 {
                                Text("Primary")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DashboardPalette.selectionFill, in: Capsule())
                                    .foregroundStyle(DashboardPalette.primaryText)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Download \(UnitsFormatter.format(rate.inboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))")
                                    .foregroundStyle(DashboardPalette.networkAccent)
                                Text("Upload \(UnitsFormatter.format(rate.outboundBytesPerSecond, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))")
                                    .foregroundStyle(DashboardPalette.cpuAccent)
                            }
                            .font(.caption.monospacedDigit())
                        }
                    }
                }
                .dashboardSurface(padding: 16, cornerRadius: 20)
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

    private var readableInterfaceRates: [NetworkInterfaceRate] {
        let active = interfaceRates.filter { $0.totalBytesPerSecond > 0 }
        let primary = interfaceRates.prefix(1)
        let candidates = active.isEmpty ? Array(primary) : Array(primary) + active
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.interface).inserted }.prefix(8).map { $0 }
    }

    private func interfaceTitle(for interface: String) -> String {
        if interface.hasPrefix("en") { return "Wi-Fi / Ethernet" }
        if interface.hasPrefix("utun") { return "VPN Tunnel" }
        if interface.hasPrefix("bridge") { return "Bridge" }
        if interface.hasPrefix("awdl") { return "Apple Direct Link" }
        if interface.hasPrefix("llw") { return "Low-Latency Wi-Fi" }
        if interface.hasPrefix("anpi") { return "Thunderbolt / USB" }
        return "Network Interface"
    }

    private func interfaceSubtitle(for interface: String, index: Int) -> String {
        if index == 0 { return "Current primary route" }
        if interface.hasPrefix("utun") { return "Often VPN, iCloud Private Relay, or system tunnel traffic" }
        if interface.hasPrefix("awdl") || interface.hasPrefix("llw") { return "Apple peer-to-peer system traffic" }
        if interface.hasPrefix("anpi") { return "External adapter or Thunderbolt networking" }
        return "Active traffic source"
    }
}
