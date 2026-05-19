import Foundation
import PulseBarCore
import PulseBarSMCBridge
import Darwin

struct AppFanTelemetrySample: Sendable {
    let channels: [SensorReading]
    let fanCount: Int
    let hasFanHardware: Bool
    let diagnostic: SensorSourceDiagnostic
}

protocol FanTelemetryDataSource: Sendable {
    func readFans(at timestamp: Date) -> AppFanTelemetrySample
}

struct AppleSMCFanTelemetryDataSource: FanTelemetryDataSource {
    func readFans(at timestamp: Date = Date()) -> AppFanTelemetrySample {
        var snapshot = PulseBarFanSnapshot()
        var errorBuffer = [CChar](repeating: 0, count: 256)
        let result = pulsebar_read_fans(&snapshot, &errorBuffer, errorBuffer.count)
        let bridgeMessage = String(cString: errorBuffer).trimmingCharacters(in: .whitespacesAndNewlines)

        if result != 0 {
            let lowerMessage = bridgeMessage.lowercased()
            let permissionBlocked = lowerMessage.contains("notprivileged")
                || lowerMessage.contains("privileged helper access")
                || lowerMessage.contains("permission")
                || lowerMessage.contains("0xe00002c2")
            let hasFanHardware = permissionBlocked ? false : likelyHasFanHardware()
            let diagnosticMessage: String
            if permissionBlocked {
                diagnosticMessage = "Fan telemetry requires privileged helper access."
            } else if bridgeMessage.isEmpty {
                diagnosticMessage = "Unable to read AppleSMC fan data"
            } else {
                diagnosticMessage = bridgeMessage
            }
            return AppFanTelemetrySample(
                channels: [],
                fanCount: hasFanHardware ? 1 : 0,
                hasFanHardware: hasFanHardware,
                diagnostic: SensorSourceDiagnostic(
                    source: "smc",
                    healthy: false,
                    message: diagnosticMessage,
                    collectedAt: timestamp
                )
            )
        }

        let fanCount = max(0, Int(snapshot.fan_count))
        let rpmValues = withUnsafeBytes(of: &snapshot.rpms) { rawBuffer -> [Double] in
            Array(rawBuffer.bindMemory(to: Double.self))
        }
        let rpmCount = max(0, min(Int(snapshot.rpm_count), Int(PULSEBAR_SMC_MAX_FANS), rpmValues.count))

        var channels: [SensorReading] = []
        channels.reserveCapacity(rpmCount)
        for index in 0..<rpmCount {
            let rpm = rpmValues[index]
            guard rpm.isFinite else { continue }
            let rawName = "F\(index)Ac"
            channels.append(
                SensorReading(
                    id: PowermetricsTemperatureReading.makeStableID(
                        from: rawName,
                        source: "smc",
                        channelType: .fanRPM
                    ),
                    rawName: rawName,
                    displayName: "System Fan \(index + 1)",
                    category: .fan,
                    channelType: .fanRPM,
                    value: rpm,
                    source: "smc",
                    timestamp: timestamp
                )
            )
        }

        let hasFanHardware = fanCount > 0 || likelyHasFanHardware()
        let normalizedFanCount = hasFanHardware ? max(fanCount, 1) : 0
        let healthy = !hasFanHardware || !channels.isEmpty

        let message: String?
        if hasFanHardware && channels.isEmpty {
            if bridgeMessage.isEmpty {
                message = "Fan hardware detected but no RPM channels decoded"
            } else {
                message = bridgeMessage
            }
        } else if hasFanHardware {
            message = "Fan telemetry active (\(channels.count)/\(normalizedFanCount) channels)"
        } else {
            message = "No fan hardware reported by AppleSMC"
        }

        return AppFanTelemetrySample(
            channels: channels,
            fanCount: normalizedFanCount,
            hasFanHardware: hasFanHardware,
            diagnostic: SensorSourceDiagnostic(
                source: "smc",
                healthy: healthy,
                message: message,
                collectedAt: timestamp
            )
        )
    }

    private func likelyHasFanHardware() -> Bool {
        guard let model = modelIdentifier()?.lowercased() else {
            return false
        }
        if model.contains("macbookair") {
            return false
        }
        return model.contains("macbookpro")
            || model.contains("macmini")
            || model.contains("macpro")
            || model.contains("imac")
            || model.contains("macstudio")
    }

    private func modelIdentifier() -> String? {
        var size: size_t = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }
}
