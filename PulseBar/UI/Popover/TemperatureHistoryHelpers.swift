import Foundation
import PulseBarCore

enum TemperatureHistoryHelpers {
    static func nearestPoint(to date: Date, in points: [TemperatureHistoryPoint]) -> TemperatureHistoryPoint? {
        points.min {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }
    }

    static func valueText(for channel: SensorReading) -> String {
        valueText(for: channel, value: channel.value)
    }

    static func valueText(for channel: SensorReading?, value: Double) -> String {
        guard let channel else { return "--" }
        switch channel.channelType {
        case .temperatureCelsius:
            return UnitsFormatter.format(value, unit: .celsius)
        case .fanRPM:
            return "\(Int(value.rounded())) rpm"
        }
    }
}
