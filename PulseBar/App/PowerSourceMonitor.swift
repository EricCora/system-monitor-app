import Foundation
import IOKit.ps

enum PowerSourceState: String, Sendable {
    case ac
    case battery
    case unknown

    var label: String {
        switch self {
        case .ac:
            return "AC Power"
        case .battery:
            return "Battery"
        case .unknown:
            return "Unknown"
        }
    }
}

actor PowerSourceMonitor {
    private var monitoringTask: Task<Void, Never>?
    private var lastState: PowerSourceState = .unknown

    func start(onChange: @escaping @Sendable (PowerSourceState) async -> Void) {
        guard monitoringTask == nil else { return }

        monitoringTask = Task {
            let initial = Self.readCurrentState()
            lastState = initial
            await onChange(initial)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                let next = Self.readCurrentState()
                guard next != lastState else { continue }
                lastState = next
                await onChange(next)
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private static func readCurrentState() -> PowerSourceState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              let state = description[kIOPSPowerSourceStateKey as String] as? String else {
            return .unknown
        }

        if state == kIOPSACPowerValue {
            return .ac
        }
        if state == kIOPSBatteryPowerValue {
            return .battery
        }
        return .unknown
    }
}
