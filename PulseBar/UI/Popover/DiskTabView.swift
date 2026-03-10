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
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Read")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(
                        featureStore.readBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ))
                    .font(.title3.monospacedDigit())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Write")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(
                        featureStore.writeBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ))
                    .font(.title3.monospacedDigit())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Free Space")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(
                        featureStore.freeBytes,
                        unit: .bytes
                    ))
                    .font(.title3.monospacedDigit())
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Combined")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(
                        featureStore.combinedBytesPerSecond,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ))
                    .font(.title3.monospacedDigit())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("S.M.A.R.T.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(smartStatusText)
                        .font(.title3.monospacedDigit())
                }
            }

            MetricChartView(
                title: "Disk Read Throughput",
                samples: featureStore.readSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
            )

            MetricChartView(
                title: "Disk Write Throughput",
                samples: featureStore.writeSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
            )

            MetricChartView(
                title: "Disk Combined Throughput",
                samples: featureStore.throughputSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore
            )
        }
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
