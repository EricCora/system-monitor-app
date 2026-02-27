import SwiftUI
import PulseBarCore

struct MemoryTabView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var memorySamples: [MetricSample] = []
    @State private var swapSamples: [MetricSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(coordinator.latestValue(for: .memoryUsedBytes)?.value ?? 0, unit: .bytes))
                        .font(.title3.monospacedDigit())
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(coordinator.latestValue(for: .memoryFreeBytes)?.value ?? 0, unit: .bytes))
                        .font(.title3.monospacedDigit())
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pressure")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(coordinator.latestValue(for: .memoryPressureLevel)?.value ?? 0, unit: .percent))
                        .font(.title3.monospacedDigit())
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compressed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(coordinator.latestValue(for: .memoryCompressedBytes)?.value ?? 0, unit: .bytes))
                        .font(.title3.monospacedDigit())
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Swap Used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(coordinator.latestValue(for: .memorySwapUsedBytes)?.value ?? 0, unit: .bytes))
                        .font(.title3.monospacedDigit())
                }
            }

            MetricChartView(
                title: "Memory Used",
                samples: memorySamples,
                throughputUnit: coordinator.throughputUnit
            )

            MetricChartView(
                title: "Swap Used",
                samples: swapSamples,
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
        memorySamples = await coordinator.series(for: .memoryUsedBytes)
        swapSamples = await coordinator.series(for: .memorySwapUsedBytes)
    }
}
