import Foundation
import IOKit
import IOKit.ps

public struct BatteryProvider: MetricProvider {
    public let providerID = "battery"

    public init() {}

    public func sample(at date: Date) async throws -> [MetricSample] {
        let supplemental = readRegistrySupplement()

        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return []
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let snapshot = Self.parseBatterySnapshot(from: description) else {
                continue
            }

            let enriched = BatterySnapshot(
                chargePercent: snapshot.chargePercent,
                currentMilliAmps: snapshot.currentMilliAmps,
                timeRemainingMinutes: snapshot.timeRemainingMinutes,
                healthPercent: snapshot.healthPercent ?? supplemental.healthPercent,
                cycleCount: snapshot.cycleCount ?? supplemental.cycleCount,
                isCharging: snapshot.isCharging
            )

            return Self.metricSamples(from: enriched, date: date)
        }

        return []
    }

    static func metricSamples(from snapshot: BatterySnapshot, date: Date) -> [MetricSample] {
        var samples: [MetricSample] = [
            MetricSample(
                metricID: .batteryChargePercent,
                timestamp: date,
                value: snapshot.chargePercent,
                unit: .percent
            ),
            MetricSample(
                metricID: .batteryIsCharging,
                timestamp: date,
                value: snapshot.isCharging ? 1 : 0,
                unit: .scalar
            )
        ]

        if let currentMilliAmps = snapshot.currentMilliAmps {
            samples.append(
                MetricSample(
                    metricID: .batteryCurrentMilliAmps,
                    timestamp: date,
                    value: currentMilliAmps,
                    unit: .milliamps
                )
            )
        }

        if let timeRemainingMinutes = snapshot.timeRemainingMinutes {
            samples.append(
                MetricSample(
                    metricID: .batteryTimeRemainingMinutes,
                    timestamp: date,
                    value: timeRemainingMinutes,
                    unit: .minutes
                )
            )
        }

        if let healthPercent = snapshot.healthPercent {
            samples.append(
                MetricSample(
                    metricID: .batteryHealthPercent,
                    timestamp: date,
                    value: healthPercent,
                    unit: .percent
                )
            )
        }

        if let cycleCount = snapshot.cycleCount {
            samples.append(
                MetricSample(
                    metricID: .batteryCycleCount,
                    timestamp: date,
                    value: cycleCount,
                    unit: .scalar
                )
            )
        }

        return samples
    }

    static func parseBatterySnapshot(from description: [String: Any]) -> BatterySnapshot? {
        let sourceType = (description[kIOPSTypeKey as String] as? String) ?? ""
        let hasCapacityKeys = number(forAnyKey: [kIOPSCurrentCapacityKey as String], in: description) != nil
            && number(forAnyKey: [kIOPSMaxCapacityKey as String], in: description) != nil

        // Desktop Macs can expose only AC adapters; skip non-battery sources.
        guard sourceType.localizedCaseInsensitiveContains("internal") || hasCapacityKeys else {
            return nil
        }

        guard let currentCapacity = number(forAnyKey: [kIOPSCurrentCapacityKey as String], in: description),
              let maxCapacity = number(forAnyKey: [kIOPSMaxCapacityKey as String], in: description),
              maxCapacity > 0 else {
            return nil
        }

        let state = description[kIOPSPowerSourceStateKey as String] as? String
        let isCharging = (description[kIOPSIsChargingKey as String] as? Bool)
            ?? (state == kIOPSACPowerValue)

        let currentMilliAmps = number(forAnyKey: [
            kIOPSCurrentKey as String,
            "Current"
        ], in: description)

        let timeToEmpty = number(forAnyKey: [
            kIOPSTimeToEmptyKey as String,
            "Time to Empty"
        ], in: description)
        let timeToFull = number(forAnyKey: [
            kIOPSTimeToFullChargeKey as String,
            "Time to Full Charge"
        ], in: description)
        let timeRemainingMinutes: Double?
        if isCharging, let timeToFull, timeToFull > 0 {
            timeRemainingMinutes = timeToFull
        } else if !isCharging, let timeToEmpty, timeToEmpty > 0 {
            timeRemainingMinutes = timeToEmpty
        } else {
            timeRemainingMinutes = nil
        }

        let designCapacity = number(forAnyKey: [
            "DesignCapacity",
            "Design Capacity"
        ], in: description)
        let healthPercent: Double?
        if let designCapacity, designCapacity > 0 {
            healthPercent = min(max((maxCapacity / designCapacity) * 100.0, 0), 150)
        } else {
            healthPercent = nil
        }

        let cycleCount = number(forAnyKey: [
            "Cycle Count",
            "CycleCount"
        ], in: description)

        return BatterySnapshot(
            chargePercent: min(max((currentCapacity / maxCapacity) * 100.0, 0), 100),
            currentMilliAmps: currentMilliAmps,
            timeRemainingMinutes: timeRemainingMinutes,
            healthPercent: healthPercent,
            cycleCount: cycleCount,
            isCharging: isCharging
        )
    }

    private static func number(forAnyKey keys: [String], in dictionary: [String: Any]) -> Double? {
        for key in keys {
            guard let raw = dictionary[key] else { continue }
            if let number = raw as? NSNumber {
                return number.doubleValue
            }
            if let intValue = raw as? Int {
                return Double(intValue)
            }
            if let doubleValue = raw as? Double {
                return doubleValue
            }
            if let stringValue = raw as? String, let parsed = Double(stringValue) {
                return parsed
            }
        }
        return nil
    }

    private func readRegistrySupplement() -> (healthPercent: Double?, cycleCount: Double?) {
        let smartBattery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard smartBattery != 0 else {
            return (nil, nil)
        }
        defer { IOObjectRelease(smartBattery) }

        guard let properties = IORegistryEntryCreateCFPropertiesDictionary(smartBattery) as? [String: Any] else {
            return (nil, nil)
        }
        return Self.parseRegistrySupplement(from: properties)
    }

    static func parseRegistrySupplement(from properties: [String: Any]) -> (healthPercent: Double?, cycleCount: Double?) {
        let cycleCount = number(forAnyKey: [
            "CycleCount",
            "Cycle Count"
        ], in: properties)

        let maxCapacity = number(forAnyKey: [
            "AppleRawMaxCapacity",
            "MaxCapacity",
            "NominalChargeCapacity"
        ], in: properties)
        let designCapacity = number(forAnyKey: [
            "DesignCapacity",
            "Design Capacity"
        ], in: properties)

        let healthPercent: Double?
        if let maxCapacity, let designCapacity, designCapacity > 0 {
            healthPercent = min(max((maxCapacity / designCapacity) * 100.0, 0), 150)
        } else {
            healthPercent = nil
        }

        return (healthPercent, cycleCount)
    }
}

struct BatterySnapshot: Equatable {
    let chargePercent: Double
    let currentMilliAmps: Double?
    let timeRemainingMinutes: Double?
    let healthPercent: Double?
    let cycleCount: Double?
    let isCharging: Bool
}

private func IORegistryEntryCreateCFPropertiesDictionary(_ entry: io_registry_entry_t) -> CFDictionary? {
    var properties: Unmanaged<CFMutableDictionary>?
    let result = IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
    guard result == KERN_SUCCESS else {
        return nil
    }
    return properties?.takeRetainedValue()
}
