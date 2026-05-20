import Foundation

public enum DashboardLayoutMode: String, Codable, CaseIterable, Sendable {
    case cardDashboard
    case focusGrid
    case compactMatrix

    public var label: String {
        switch self {
        case .cardDashboard:
            return "Balanced Grid"
        case .focusGrid:
            return "Focus Grid"
        case .compactMatrix:
            return "Compact Matrix"
        }
    }
}

public enum DashboardDensityMode: String, Codable, CaseIterable, Sendable {
    case comfortable
    case compact

    public var label: String {
        switch self {
        case .comfortable:
            return "Comfortable"
        case .compact:
            return "Compact"
        }
    }
}

public enum DashboardCardSizeMode: String, Codable, CaseIterable, Sendable {
    case standard
    case expanded

    public var label: String {
        switch self {
        case .standard:
            return "Standard"
        case .expanded:
            return "Expanded"
        }
    }
}

public enum DashboardCardID: String, Codable, CaseIterable, Sendable {
    case cpu
    case memory
    case battery
    case network
    case disk
    case sensors

    public var label: String {
        switch self {
        case .cpu:
            return "CPU"
        case .memory:
            return "Memory"
        case .battery:
            return "Battery"
        case .network:
            return "Network"
        case .disk:
            return "Disk"
        case .sensors:
            return "Sensors"
        }
    }
}

public enum DashboardSection: String, Codable, CaseIterable, Sendable {
    case overview
    case cpu
    case memory
    case battery
    case network
    case temperature
    case disk
    case settings

    public var label: String {
        switch self {
        case .overview:
            return "Overview"
        case .cpu:
            return "CPU"
        case .memory:
            return "Memory"
        case .battery:
            return "Battery"
        case .network:
            return "Network"
        case .temperature:
            return "Temperature"
        case .disk:
            return "Disk"
        case .settings:
            return "Settings"
        }
    }
}

public enum MenuBarDisplayMode: String, Codable, CaseIterable, Sendable {
    case compact
    case balanced
    case dense

    public var label: String {
        switch self {
        case .compact:
            return "Compact"
        case .balanced:
            return "Balanced"
        case .dense:
            return "Dense"
        }
    }
}

public enum MenuBarMetricID: String, Codable, CaseIterable, Sendable {
    case cpu
    case memory
    case battery
    case network
    case disk
    case temperature

    public var label: String {
        switch self {
        case .cpu:
            return "CPU"
        case .memory:
            return "Memory"
        case .battery:
            return "Battery"
        case .network:
            return "Network"
        case .disk:
            return "Disk"
        case .temperature:
            return "Temperature"
        }
    }

    public var systemImage: String {
        switch self {
        case .cpu:
            return "cpu"
        case .memory:
            return "memorychip"
        case .battery:
            return "battery.100"
        case .network:
            return "network"
        case .disk:
            return "internaldrive"
        case .temperature:
            return "thermometer.medium"
        }
    }
}

public enum MenuBarMetricStyle: String, Codable, CaseIterable, Sendable {
    case text
    case value
    case label
    case icon
    case iconText
    case pieValue
    case graph
    case sparklineValue
    case history
    case historyValue

    public var label: String {
        switch self {
        case .text:
            return "Label + Value"
        case .value:
            return "Value"
        case .label:
            return "Label"
        case .icon:
            return "Icon"
        case .iconText:
            return "Icon + Value"
        case .pieValue:
            return "Pie + Value"
        case .graph:
            return "Graph"
        case .sparklineValue:
            return "Graph + Value"
        case .history:
            return "History"
        case .historyValue:
            return "History + Value"
        }
    }
}

public struct SensorPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var sensorIDs: [String]

    public init(id: String = UUID().uuidString, name: String, sensorIDs: [String]) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sensorIDs = Array(NSOrderedSet(array: sensorIDs.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        })) as? [String] ?? []
    }
}

public extension DashboardCardID {
    static let defaultOrder = DashboardCardID.allCases
    static let defaultVisibility = Dictionary(uniqueKeysWithValues: DashboardCardID.allCases.map { ($0, true) })

    var detailSection: DashboardSection {
        switch self {
        case .cpu:
            return .cpu
        case .memory:
            return .memory
        case .battery:
            return .battery
        case .network:
            return .network
        case .disk:
            return .disk
        case .sensors:
            return .temperature
        }
    }
}

public extension MenuBarMetricID {
    static let defaultStyles: [MenuBarMetricID: MenuBarMetricStyle] = [
        .cpu: .sparklineValue,
        .memory: .iconText,
        .battery: .iconText,
        .network: .text,
        .disk: .text,
        .temperature: .iconText
    ]
}
