import SwiftUI
import PulseBarCore

struct NetworkTabView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var inboundSamples: [MetricSample] = []
    @State private var outboundSamples: [MetricSample] = []

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inbound")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(UnitsFormatter.format(
                        coordinator.latestValue(for: .networkInBytesPerSec)?.value ?? 0,
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
                        coordinator.latestValue(for: .networkOutBytesPerSec)?.value ?? 0,
                        unit: .bytesPerSecond,
                        throughputUnit: coordinator.throughputUnit
                    ))
                    .font(.title3.monospacedDigit())
                }
            }

            MetricChartView(
                title: "Inbound Throughput",
                samples: inboundSamples,
                throughputUnit: coordinator.throughputUnit
            )

            MetricChartView(
                title: "Outbound Throughput",
                samples: outboundSamples,
                throughputUnit: coordinator.throughputUnit
            )
        }
        .task {
            await refresh()
        }
        .onReceive(timer) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        inboundSamples = await coordinator.series(for: .networkInBytesPerSec)
        outboundSamples = await coordinator.series(for: .networkOutBytesPerSec)
    }
}
