import Foundation

public enum MetricID: Hashable, Codable, Sendable {
    case cpuTotalPercent
    case cpuCorePercent(Int)
    case thermalStateLevel
    case temperaturePrimaryCelsius
    case temperatureMaxCelsius
    case memoryUsedBytes
    case memoryFreeBytes
    case memoryPressureLevel
    case networkInBytesPerSec
    case networkOutBytesPerSec
    case diskThroughputBytesPerSec
    case diskFreeBytes

    public var displayName: String {
        switch self {
        case .cpuTotalPercent:
            return "CPU Total"
        case .cpuCorePercent(let index):
            return "CPU Core \(index + 1)"
        case .thermalStateLevel:
            return "Thermal State"
        case .temperaturePrimaryCelsius:
            return "Temperature Primary"
        case .temperatureMaxCelsius:
            return "Temperature Max"
        case .memoryUsedBytes:
            return "Memory Used"
        case .memoryFreeBytes:
            return "Memory Free"
        case .memoryPressureLevel:
            return "Memory Pressure"
        case .networkInBytesPerSec:
            return "Network In"
        case .networkOutBytesPerSec:
            return "Network Out"
        case .diskThroughputBytesPerSec:
            return "Disk Throughput"
        case .diskFreeBytes:
            return "Disk Free"
        }
    }

    public var defaultUnit: MetricUnit {
        switch self {
        case .cpuTotalPercent, .cpuCorePercent, .memoryPressureLevel:
            return .percent
        case .temperaturePrimaryCelsius, .temperatureMaxCelsius:
            return .celsius
        case .thermalStateLevel:
            return .scalar
        case .memoryUsedBytes, .memoryFreeBytes, .diskFreeBytes:
            return .bytes
        case .networkInBytesPerSec, .networkOutBytesPerSec, .diskThroughputBytesPerSec:
            return .bytesPerSecond
        }
    }
}
