import Foundation
import PulseBarCore

struct PrivilegedTelemetryOrchestrator: Sendable {
    private let iohidSource: TemperatureDataSource
    private let powermetricsFallback: TemperatureDataSource
    private let fanSource: AppleSMCFanDataSource

    init(
        iohidSource: TemperatureDataSource = IOHIDTemperatureDataSource(),
        powermetricsFallback: TemperatureDataSource = PowermetricsTemperatureDataSource(),
        fanSource: AppleSMCFanDataSource = AppleSMCFanDataSource()
    ) {
        self.iohidSource = iohidSource
        self.powermetricsFallback = powermetricsFallback
        self.fanSource = fanSource
    }

    func sample(at timestamp: Date = Date()) async throws -> PowermetricsTemperatureReading {
        var diagnostics: [SensorSourceDiagnostic] = []
        var temperatureReading: PowermetricsTemperatureReading?
        var failures: [String] = []

        do {
            let reading = try await iohidSource.readTemperatures()
            temperatureReading = reading
            diagnostics.append(
                SensorSourceDiagnostic(
                    source: "iohid",
                    healthy: true,
                    message: "IOHID returned \(reading.sensorCount) temperature channels",
                    collectedAt: timestamp
                )
            )
        } catch {
            failures.append("iohid: \(error.localizedDescription)")
            diagnostics.append(
                SensorSourceDiagnostic(
                    source: "iohid",
                    healthy: false,
                    message: error.localizedDescription,
                    collectedAt: timestamp
                )
            )
        }

        if temperatureReading == nil {
            do {
                let fallback = try await powermetricsFallback.readTemperatures()
                temperatureReading = fallback
                diagnostics.append(
                    SensorSourceDiagnostic(
                        source: "powermetrics",
                        healthy: true,
                        message: "powermetrics fallback returned \(fallback.sensorCount) channels",
                        collectedAt: timestamp
                    )
                )
            } catch {
                failures.append("powermetrics: \(error.localizedDescription)")
                diagnostics.append(
                    SensorSourceDiagnostic(
                        source: "powermetrics",
                        healthy: false,
                        message: error.localizedDescription,
                        collectedAt: timestamp
                    )
                )
            }
        }

        guard let temperatureReading else {
            throw ProviderError.unavailable("All temperature probes failed (\(failures.joined(separator: "; ")))")
        }

        let fanSample = fanSource.readFans(at: timestamp)
        diagnostics.append(fanSample.diagnostic)

        let rawTemperatureChannels = normalizedTemperatureChannels(from: temperatureReading, timestamp: timestamp)
        let fanChannels = fanSample.channels

        let allChannels = deduplicate(channels: rawTemperatureChannels + fanChannels)
        let temps = allChannels.filter { $0.channelType == .temperatureCelsius }.map(\.value)
        let primary = temps.first ?? temperatureReading.primaryCelsius
        let max = temps.max() ?? temperatureReading.maxCelsius
        let sensorCount = temps.count
        let legacySensors = allChannels
            .filter { $0.channelType == .temperatureCelsius }
            .map { TemperatureSensorReading(name: $0.displayName, celsius: $0.value) }

        var sourceChain = temperatureReading.sourceChain
        if sourceChain.isEmpty, let source = temperatureReading.source, !source.isEmpty {
            sourceChain = [source]
        }
        if !fanChannels.isEmpty || fanSample.hasFanHardware {
            if !sourceChain.contains("smc") {
                sourceChain.append("smc")
            }
        }

        let fanTelemetryAvailable = fanSample.hasFanHardware ? !fanChannels.isEmpty : true

        return PowermetricsTemperatureReading(
            primaryCelsius: primary,
            maxCelsius: max,
            sensorCount: sensorCount,
            sensors: legacySensors,
            channels: allChannels,
            source: sourceChain.first ?? temperatureReading.source ?? "iohid",
            sourceChain: sourceChain,
            sourceDiagnostics: diagnostics,
            fanTelemetryAvailable: fanTelemetryAvailable,
            fanCount: fanSample.fanCount
        )
    }

    private func normalizedTemperatureChannels(
        from reading: PowermetricsTemperatureReading,
        timestamp: Date
    ) -> [SensorReading] {
        let existing = reading.channels.filter { $0.channelType == .temperatureCelsius }
        if !existing.isEmpty {
            return existing
        }

        let source = reading.source ?? "unknown"
        return reading.sensors.map { sensor in
            SensorReading(
                id: PowermetricsTemperatureReading.makeStableID(
                    from: sensor.name,
                    source: source,
                    channelType: .temperatureCelsius
                ),
                rawName: sensor.name,
                displayName: sensor.name,
                category: .other,
                channelType: .temperatureCelsius,
                value: sensor.celsius,
                source: source,
                timestamp: timestamp
            )
        }
    }

    private func deduplicate(channels: [SensorReading]) -> [SensorReading] {
        var seen = Set<String>()
        var output: [SensorReading] = []
        output.reserveCapacity(channels.count)

        for channel in channels {
            if seen.contains(channel.id) {
                continue
            }
            seen.insert(channel.id)
            output.append(channel)
        }

        return output
    }
}
