import Foundation
import PulseBarCore

enum MenuBarMetricSummaryFormatter {
    static func text(
        for metric: MenuBarMetricID,
        latestSamples: [MetricID: MetricSample],
        thermalState: ThermalStateLevel,
        throughputUnit: ThroughputDisplayUnit
    ) -> String {
        switch metric {
        case .cpu:
            guard let sample = latestSamples[.cpuTotalPercent] else { return "CPU --" }
            if let load = latestSamples[.cpuLoadAverage1] {
                return "CPU \(UnitsFormatter.format(sample.value, unit: .percent))"
                    + " L\(String(format: "%.2f", load.value))"
            }
            return "CPU \(UnitsFormatter.format(sample.value, unit: .percent))"
        case .memory:
            guard let sample = latestSamples[.memoryUsedBytes] else { return "MEM --" }
            return "MEM \(UnitsFormatter.format(sample.value, unit: .bytes))"
        case .battery:
            guard let charge = latestSamples[.batteryChargePercent]?.value else { return "BAT --" }
            let charging = (latestSamples[.batteryIsCharging]?.value ?? 0) >= 0.5
            return "BAT \(UnitsFormatter.format(charge, unit: .percent))\(charging ? "+" : "-")"
        case .network:
            let inbound = latestSamples[.networkInBytesPerSec]?.value ?? 0
            let outbound = latestSamples[.networkOutBytesPerSec]?.value ?? 0
            let inboundText = UnitsFormatter.format(inbound, unit: .bytesPerSecond, throughputUnit: throughputUnit)
            let outboundText = UnitsFormatter.format(outbound, unit: .bytesPerSecond, throughputUnit: throughputUnit)
            return "NET ↓\(inboundText) ↑\(outboundText)"
        case .disk:
            guard let sample = latestSamples[.diskThroughputBytesPerSec] else { return "DSK --" }
            return "DSK \(UnitsFormatter.format(sample.value, unit: .bytesPerSecond, throughputUnit: throughputUnit))"
        case .temperature:
            if let sample = latestSamples[.temperaturePrimaryCelsius] {
                return "TMP \(UnitsFormatter.format(sample.value, unit: .celsius))"
            }
            return "TMP \(thermalState.shortLabel)"
        }
    }

    static func valueText(
        for metric: MenuBarMetricID,
        latestSamples: [MetricID: MetricSample],
        thermalState: ThermalStateLevel,
        throughputUnit: ThroughputDisplayUnit
    ) -> String {
        switch metric {
        case .cpu:
            return latestSamples[.cpuTotalPercent].map { UnitsFormatter.format($0.value, unit: .percent) } ?? "--"
        case .memory:
            return latestSamples[.memoryUsedBytes].map { UnitsFormatter.format($0.value, unit: .bytes) } ?? "--"
        case .battery:
            return latestSamples[.batteryChargePercent].map { UnitsFormatter.format($0.value, unit: .percent) } ?? "--"
        case .network:
            let inbound = latestSamples[.networkInBytesPerSec]?.value ?? 0
            let outbound = latestSamples[.networkOutBytesPerSec]?.value ?? 0
            let total = inbound + outbound
            return UnitsFormatter.format(total, unit: .bytesPerSecond, throughputUnit: throughputUnit)
        case .disk:
            return latestSamples[.diskThroughputBytesPerSec]
                .map { UnitsFormatter.format($0.value, unit: .bytesPerSecond, throughputUnit: throughputUnit) } ?? "--"
        case .temperature:
            if let sample = latestSamples[.temperaturePrimaryCelsius] {
                return UnitsFormatter.format(sample.value, unit: .celsius)
            }
            return thermalState.shortLabel
        }
    }
}
