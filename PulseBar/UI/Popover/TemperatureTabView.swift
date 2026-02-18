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

            sensorPanel

            MetricChartView(
                title: "Primary Temperature",
                samples: primaryTemperatureSamples,
                throughputUnit: coordinator.throughputUnit
            )

            MetricChartView(
                title: "Maximum Temperature",
                samples: maxTemperatureSamples,
                throughputUnit: coordinator.throughputUnit
            )

            MetricChartView(
                title: "Thermal State Level",
                samples: thermalStateSamples,
                throughputUnit: coordinator.throughputUnit
            )

            if sensorRows.isEmpty {
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

    private var sensorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sensors")
                .font(.headline)

            if sensorRows.isEmpty {
                Text("Waiting for sensor names from privileged readings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(sensorRows.prefix(14), id: \.name) { sensor in
                        TemperatureSensorRow(
                            name: sensor.name,
                            celsius: sensor.celsius,
                            maxScale: sensorScaleMax
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var sensorRows: [TemperatureSensorReading] {
        let sensors = coordinator.latestTemperatureSensors
            .filter { $0.celsius.isFinite }
            .sorted { lhs, rhs in
                if lhs.celsius != rhs.celsius {
                    return lhs.celsius > rhs.celsius
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        if !sensors.isEmpty {
            return sensors
        }

        guard let primary = coordinator.latestValue(for: .temperaturePrimaryCelsius)?.value else {
            return []
        }
        let maxValue = coordinator.latestValue(for: .temperatureMaxCelsius)?.value ?? primary
        return [
            TemperatureSensorReading(name: "Primary", celsius: primary),
            TemperatureSensorReading(name: "Maximum", celsius: maxValue)
        ]
    }

    private var sensorScaleMax: Double {
        max(45, sensorRows.map(\.celsius).max() ?? 45)
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

private struct TemperatureSensorRow: View {
    let name: String
    let celsius: Double
    let maxScale: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.0f C", celsius))
                .font(.subheadline.monospacedDigit())
                .frame(width: 52, alignment: .trailing)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(.cyan)
                        .frame(width: fillWidth(totalWidth: proxy.size.width))
                }
            }
            .frame(width: 120, height: 11)
        }
    }

    private func fillWidth(totalWidth: Double) -> Double {
        guard maxScale > 0 else { return 0 }
        let ratio = max(0, min(1, celsius / maxScale))
        return totalWidth * ratio
    }
}
