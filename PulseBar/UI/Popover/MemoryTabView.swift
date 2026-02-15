import SwiftUI
import PulseBarCore

struct MemoryTabView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var memorySamples: [MetricSample] = []

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

            MetricChartView(
                title: "Memory Used",
                samples: memorySamples,
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
    }
}
