import SwiftUI
import PulseBarCore

struct DiskTabView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var throughputSamples: [MetricSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Disk throughput in MVP is combined read/write via iostat.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Combined Throughput")
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
        throughputSamples = await coordinator.series(for: .diskThroughputBytesPerSec)
    }
}
