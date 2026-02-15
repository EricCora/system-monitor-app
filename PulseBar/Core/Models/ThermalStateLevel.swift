import Foundation

public enum ThermalStateLevel: Int, Codable, CaseIterable, Sendable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    public var label: String {
        switch self {
        case .nominal:
            return "Nominal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        }
    }

    public var shortLabel: String {
        switch self {
        case .nominal:
            return "Nom"
        case .fair:
            return "Fair"
        case .serious:
            return "Hot"
        case .critical:
            return "Crit"
        }
    }

    public var metricValue: Double {
        Double(rawValue)
    }

    public static func from(metricValue: Double) -> ThermalStateLevel {
        let rounded = Int(metricValue.rounded())
        return ThermalStateLevel(rawValue: rounded) ?? .nominal
    }

    public static func from(processThermalState state: ProcessInfo.ThermalState) -> ThermalStateLevel {
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .fair
        }
    }
}
