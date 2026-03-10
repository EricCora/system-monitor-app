import Foundation

enum DashboardTab: CaseIterable {
    case cpu
    case memory
    case battery
    case network
    case temperature
    case disk
    case settings

    var title: String {
        switch self {
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
