import Foundation
import PulseBarCore

enum SensorIdentityResolver {
    static func stableID(for reading: SensorReading) -> String {
        let trimmed = reading.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return PowermetricsTemperatureReading.makeStableID(
            from: reading.rawName,
            source: reading.source,
            channelType: reading.channelType
        )
    }
}

enum SensorDisplayNameMapper {
    static func present(_ reading: SensorReading) -> SensorReading {
        let normalizedDisplay = displayName(from: reading.rawName)
        let normalizedCategory = category(from: reading.rawName, fallback: reading.category, channelType: reading.channelType)

        return SensorReading(
            id: SensorIdentityResolver.stableID(for: reading),
            rawName: reading.rawName,
            displayName: normalizedDisplay,
            category: normalizedCategory,
            channelType: reading.channelType,
            value: reading.value,
            source: reading.source,
            timestamp: reading.timestamp,
            reliabilityFlags: reading.reliabilityFlags
        )
    }

    private static func category(from rawName: String, fallback: SensorCategory, channelType: SensorChannelType) -> SensorCategory {
        if channelType == .fanRPM {
            return .fan
        }

        let lower = rawName.lowercased()
        if lower.contains("gpu") {
            return .gpu
        }
        if lower.contains("ane") {
            return .ane
        }
        if lower.contains("soc") || lower.contains("pmgr") {
            return .soc
        }
        if lower.contains("nand") || lower.contains("ssd") {
            return .storage
        }
        if lower.contains("battery") || lower.contains("gas gauge") {
            return .battery
        }
        if lower.contains("cpu") || lower.contains("pmu") || lower.contains("pacc") || lower.contains("eacc") {
            return .cpu
        }
        return fallback
    }

    private static func displayName(from rawName: String) -> String {
        let lower = rawName.lowercased()

        if lower == "gas gauge battery" {
            return "Battery"
        }
        if lower.contains("pmgr soc die temp sensor") {
            let suffix = rawName.components(separatedBy: " ").last ?? ""
            return "SoC Die \(suffix)"
        }
        if lower.contains("soc mtr temp sensor") {
            let suffix = rawName.components(separatedBy: " ").last ?? ""
            return "SoC Sensor \(suffix)"
        }
        if lower.contains("gpu mtr temp sensor") {
            return "GPU"
        }
        if lower.contains("ane mtr temp sensor") {
            return "Neural Engine"
        }
        if lower.contains("isp mtr temp sensor") {
            return "Image Signal Processor"
        }
        if lower.contains("nand") {
            return "SSD"
        }
        if lower.hasPrefix("pmu tdie") {
            return "CPU Core Die \(rawName.replacingOccurrences(of: "PMU tdie", with: ""))"
        }
        if lower.hasPrefix("pmu2 tdie") {
            return "CPU Cluster Die \(rawName.replacingOccurrences(of: "PMU2 tdie", with: ""))"
        }
        if lower.hasPrefix("f"), lower.hasSuffix("ac"), rawName.count <= 4 {
            let index = rawName.dropFirst().dropLast(2)
            return "System Fan \(index)"
        }

        return rawName
    }
}
