import Foundation

public enum MetricID: Hashable, Codable, Sendable {
    case cpuTotalPercent
    case cpuCorePercent(Int)
    case cpuLoadAverage1
    case cpuLoadAverage5
    case cpuLoadAverage15
    case thermalStateLevel
    case temperaturePrimaryCelsius
    case temperatureMaxCelsius
    case batteryChargePercent
    case batteryCurrentMilliAmps
    case batteryTimeRemainingMinutes
    case batteryHealthPercent
    case batteryCycleCount
    case batteryIsCharging
    case memoryUsedBytes
    case memoryFreeBytes
    case memoryCompressedBytes
    case memorySwapUsedBytes
    case memoryPressureLevel
    case networkInBytesPerSec
    case networkOutBytesPerSec
    case networkInterfaceInBytesPerSec(String)
    case networkInterfaceOutBytesPerSec(String)
    case diskThroughputBytesPerSec
    case diskReadBytesPerSec
    case diskWriteBytesPerSec
    case diskFreeBytes
    case diskSMARTStatusCode

    public var displayName: String {
        switch self {
        case .cpuTotalPercent:
            return "CPU Total"
        case .cpuCorePercent(let index):
            return "CPU Core \(index + 1)"
        case .cpuLoadAverage1:
            return "CPU Load (1m)"
        case .cpuLoadAverage5:
            return "CPU Load (5m)"
        case .cpuLoadAverage15:
            return "CPU Load (15m)"
        case .thermalStateLevel:
            return "Thermal State"
        case .temperaturePrimaryCelsius:
            return "Temperature Primary"
        case .temperatureMaxCelsius:
            return "Temperature Max"
        case .batteryChargePercent:
            return "Battery Charge"
        case .batteryCurrentMilliAmps:
            return "Battery Current"
        case .batteryTimeRemainingMinutes:
            return "Battery Time Remaining"
        case .batteryHealthPercent:
            return "Battery Health"
        case .batteryCycleCount:
            return "Battery Cycle Count"
        case .batteryIsCharging:
            return "Battery Charging"
        case .memoryUsedBytes:
            return "Memory Used"
        case .memoryFreeBytes:
            return "Memory Free"
        case .memoryCompressedBytes:
            return "Memory Compressed"
        case .memorySwapUsedBytes:
            return "Memory Swap Used"
        case .memoryPressureLevel:
            return "Memory Pressure"
        case .networkInBytesPerSec:
            return "Network In"
        case .networkOutBytesPerSec:
            return "Network Out"
        case .networkInterfaceInBytesPerSec(let interface):
            return "Network In (\(interface))"
        case .networkInterfaceOutBytesPerSec(let interface):
            return "Network Out (\(interface))"
        case .diskThroughputBytesPerSec:
            return "Disk Throughput"
        case .diskReadBytesPerSec:
            return "Disk Read"
        case .diskWriteBytesPerSec:
            return "Disk Write"
        case .diskFreeBytes:
            return "Disk Free"
        case .diskSMARTStatusCode:
            return "Disk SMART Status"
        }
    }

    public var defaultUnit: MetricUnit {
        switch self {
        case .cpuTotalPercent, .cpuCorePercent, .memoryPressureLevel:
            return .percent
        case .cpuLoadAverage1, .cpuLoadAverage5, .cpuLoadAverage15:
            return .scalar
        case .temperaturePrimaryCelsius, .temperatureMaxCelsius:
            return .celsius
        case .batteryChargePercent, .batteryHealthPercent:
            return .percent
        case .batteryCurrentMilliAmps:
            return .milliamps
        case .batteryTimeRemainingMinutes:
            return .minutes
        case .batteryCycleCount, .batteryIsCharging:
            return .scalar
        case .thermalStateLevel:
            return .scalar
        case .memoryUsedBytes, .memoryFreeBytes, .memoryCompressedBytes, .memorySwapUsedBytes, .diskFreeBytes:
            return .bytes
        case .networkInBytesPerSec, .networkOutBytesPerSec,
            .networkInterfaceInBytesPerSec, .networkInterfaceOutBytesPerSec,
            .diskThroughputBytesPerSec, .diskReadBytesPerSec, .diskWriteBytesPerSec:
            return .bytesPerSecond
        case .diskSMARTStatusCode:
            return .scalar
        }
    }
}
