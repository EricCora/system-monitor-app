import SwiftUI
import PulseBarCore

struct DiskTabView: View {
    let coordinator: AppCoordinator
    @ObservedObject var featureStore: DiskFeatureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: Binding(
                    get: { coordinator.diskChartWindow },
                    set: { coordinator.diskChartWindow = $0 }
                )
            )

            Text(splitStatusText)
                .font(.caption)
                .foregroundStyle(DashboardPalette.secondaryText)
                .dashboardSurface()

            HStack {
                DashboardReadoutCell(
                    title: "Read",
                    value: UnitsFormatter.format(
                        featureStore.readBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ),
                    tint: DashboardPalette.diskAccent
                )

                DashboardReadoutCell(
                    title: "Write",
                    value: UnitsFormatter.format(
                        featureStore.writeBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ),
                    tint: DashboardPalette.cpuAccent
                )

                DashboardReadoutCell(
                    title: "Free Space",
                    value: UnitsFormatter.format(
                        featureStore.freeBytes,
                        unit: .bytes
                    ),
                    tint: DashboardPalette.secondaryText
                )
            }
            .dashboardSurface(padding: 16, cornerRadius: 20)

            HStack {
                DashboardReadoutCell(
                    title: "Combined",
                    value: UnitsFormatter.format(
                        featureStore.combinedBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ),
                    tint: DashboardPalette.diskAccent
                )

                DashboardReadoutCell(
                    title: "S.M.A.R.T.",
                    value: smartStatusText,
                    tint: DashboardPalette.secondaryText
                )

                Spacer(minLength: 0)
            }
            .dashboardSurface(padding: 16, cornerRadius: 20)

            MetricChartView(
                title: "Disk Read Throughput",
                samples: featureStore.readSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.diskAccent
            )

            MetricChartView(
                title: "Disk Write Throughput",
                samples: featureStore.writeSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.cpuAccent
            )

            MetricChartView(
                title: "Disk Combined Throughput",
                samples: featureStore.throughputSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.diskAccent
            )
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .task {
            coordinator.refreshDiskSurface()
        }
        .task(id: coordinator.diskChartWindow.rawValue) {
            coordinator.refreshDiskSurface()
        }
    }

    private var splitStatusText: String {
        if featureStore.readBytesPerSecond > 0 || featureStore.writeBytesPerSecond > 0 {
            return "Disk throughput is split into read/write from IOBlockStorageDriver statistics."
        }
        return "Read/write split unavailable on this host. Showing combined throughput fallback."
    }

    private var smartStatusText: String {
        guard let code = featureStore.smartStatusCode else {
            return "Unknown"
        }
        switch code {
        case 1:
            return "Verified"
        case -1:
            return "Failing"
        case 0:
            return "Not Supported"
        default:
            return "Unknown"
        }
    }

}
