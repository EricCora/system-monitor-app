import SwiftUI
import PulseBarCore

struct TemperatureTabView: View {
    @ObservedObject var coordinator: AppCoordinator

    @State private var primaryTemperatureSamples: [MetricSample] = []
    @State private var thermalStateSamples: [MetricSample] = []
    @State private var maxTemperatureSamples: [MetricSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thermal State")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(coordinator.latestThermalState().label)
                        .font(.title3.monospacedDigit())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Primary Temp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let latestPrimary = coordinator.latestValue(for: .temperaturePrimaryCelsius) {
                        Text(UnitsFormatter.format(latestPrimary.value, unit: .celsius))
                            .font(.title3.monospacedDigit())
                    } else {
                        Text("Unavailable")
                            .font(.title3.monospacedDigit())
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(sourceLabel)
                        .font(.title3.monospacedDigit())
                }
            }

            MetricChartView(
                title: "Primary Temperature",
                samples: primaryTemperatureSamples,
                throughputUnit: coordinator.throughputUnit
            )

            MetricChartView(
                title: "Thermal State Level",
                samples: thermalStateSamples,
                throughputUnit: coordinator.throughputUnit
            )

            if !maxTemperatureSamples.isEmpty {
                MetricChartView(
                    title: "Maximum Temperature",
                    samples: maxTemperatureSamples,
                    throughputUnit: coordinator.throughputUnit
                )
            } else {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await refresh()
        }
        .onReceive(coordinator.$latestSamples) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        primaryTemperatureSamples = await coordinator.series(for: .temperaturePrimaryCelsius)
        thermalStateSamples = await coordinator.series(for: .thermalStateLevel)
        maxTemperatureSamples = await coordinator.series(for: .temperatureMaxCelsius)
    }

    private var sourceLabel: String {
        if coordinator.privilegedTemperatureEnabled && coordinator.privilegedTemperatureHealthy {
            return "Privileged"
        }
        return "Standard"
    }

    private var emptyStateText: String {
        if coordinator.privilegedTemperatureEnabled && !coordinator.privilegedTemperatureHealthy {
            return "Privileged mode is unavailable right now. Falling back to standard thermal state."
        }
        return "Enable privileged mode to collect Celsius readings."
    }
}
