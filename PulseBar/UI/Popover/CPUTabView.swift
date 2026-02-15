import SwiftUI
import PulseBarCore

struct CPUTabView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var cpuSamples: [MetricSample] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Total CPU")
                    .font(.headline)
                Spacer()
                if let latest = coordinator.latestValue(for: .cpuTotalPercent) {
                    Text(UnitsFormatter.format(latest.value, unit: .percent))
                        .font(.title3.monospacedDigit())
                }
            }

            MetricChartView(
                title: "CPU Usage",
                samples: cpuSamples,
                throughputUnit: coordinator.throughputUnit
            )

            if !coordinator.latestCPUCores().isEmpty {
                Divider()
                Text("Per-Core")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 8) {
                    ForEach(coordinator.latestCPUCores(), id: \.metricID) { core in
                        VStack(alignment: .leading) {
                            Text(core.metricID.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(UnitsFormatter.format(core.value, unit: .percent))
                                .font(.callout.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .task {
            await refresh()
        }
        .onReceive(timer) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        cpuSamples = await coordinator.series(for: .cpuTotalPercent)
    }
}
