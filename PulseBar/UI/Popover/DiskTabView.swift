import SwiftUI
import PulseBarCore

struct DiskTabView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var throughputSamples: [MetricSample] = []
    @State private var readSamples: [MetricSample] = []
    @State private var writeSamples: [MetricSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(splitStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Read")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(
                        coordinator.latestValue(for: .diskReadBytesPerSec)?.value ?? 0,
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
                        coordinator.latestValue(for: .diskWriteBytesPerSec)?.value ?? 0,
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
                        coordinator.latestValue(for: .diskFreeBytes)?.value ?? 0,
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
                        coordinator.latestValue(for: .diskThroughputBytesPerSec)?.value ?? 0,
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
                samples: readSamples,
                throughputUnit: coordinator.throughputUnit
            )

            MetricChartView(
                title: "Disk Write Throughput",
                samples: writeSamples,
                throughputUnit: coordinator.throughputUnit
            )

            MetricChartView(
                title: "Disk Combined Throughput",
                samples: throughputSamples,
                throughputUnit: coordinator.throughputUnit
            )
        }
        .task {
            await refresh()
        }
        .onReceive(coordinator.$latestSamples) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        readSamples = await coordinator.series(for: .diskReadBytesPerSec)
        writeSamples = await coordinator.series(for: .diskWriteBytesPerSec)
        throughputSamples = await coordinator.series(for: .diskThroughputBytesPerSec)
    }

    private var splitStatusText: String {
        if coordinator.latestValue(for: .diskReadBytesPerSec) != nil && coordinator.latestValue(for: .diskWriteBytesPerSec) != nil {
            return "Disk throughput is split into read/write from IOBlockStorageDriver statistics."
        }
        return "Read/write split unavailable on this host. Showing combined throughput fallback."
    }

    private var smartStatusText: String {
        guard let code = coordinator.latestValue(for: .diskSMARTStatusCode)?.value else {
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
