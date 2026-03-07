import Foundation

public enum MetricID: Hashable, Codable, Sendable {
    case cpuTotalPercent
    case cpuUserPercent
    case cpuSystemPercent
    case cpuIdlePercent
    case cpuCorePercent(Int)
    case cpuLoadAverage1
    case cpuLoadAverage5
    case cpuLoadAverage15
    case gpuProcessorPercent
    case gpuMemoryPercent
    case framesPerSecond
    case uptimeSeconds
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
    case memorySwapTotalBytes
    case memoryActiveBytes
    case memoryWiredBytes
    case memoryCacheBytes
    case memoryAppBytes
    case memoryPressureLevel
    case memoryPageInsBytesPerSec
    case memoryPageOutsBytesPerSec
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
        case .cpuUserPercent:
            return "CPU User"
        case .cpuSystemPercent:
            return "CPU System"
        case .cpuIdlePercent:
            return "CPU Idle"
        case .cpuCorePercent(let index):
            return "CPU Core \(index + 1)"
        case .cpuLoadAverage1:
            return "CPU Load (1m)"
        case .cpuLoadAverage5:
            return "CPU Load (5m)"
        case .cpuLoadAverage15:
            return "CPU Load (15m)"
        case .gpuProcessorPercent:
            return "GPU Processor"
        case .gpuMemoryPercent:
            return "GPU Memory"
        case .framesPerSecond:
            return "Frames Per Second"
        case .uptimeSeconds:
            return "Uptime"
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
        case .memorySwapTotalBytes:
            return "Memory Swap Total"
        case .memoryActiveBytes:
            return "Memory Active"
        case .memoryWiredBytes:
            return "Memory Wired"
        case .memoryCacheBytes:
            return "Memory Cache"
        case .memoryAppBytes:
            return "Memory App"
        case .memoryPressureLevel:
            return "Memory Pressure"
        case .memoryPageInsBytesPerSec:
            return "Memory Page Ins"
        case .memoryPageOutsBytesPerSec:
            return "Memory Page Outs"
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
        case .cpuTotalPercent, .cpuUserPercent, .cpuSystemPercent, .cpuIdlePercent,
            .cpuCorePercent, .gpuProcessorPercent, .gpuMemoryPercent, .memoryPressureLevel:
            return .percent
        case .cpuLoadAverage1, .cpuLoadAverage5, .cpuLoadAverage15:
            return .scalar
        case .framesPerSecond:
            return .scalar
        case .uptimeSeconds:
            return .seconds
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
        case .memoryUsedBytes, .memoryFreeBytes, .memoryCompressedBytes, .memorySwapUsedBytes,
            .memorySwapTotalBytes, .memoryActiveBytes, .memoryWiredBytes, .memoryCacheBytes, .memoryAppBytes,
            .diskFreeBytes:
            return .bytes
        case .memoryPageInsBytesPerSec, .memoryPageOutsBytesPerSec,
            .networkInBytesPerSec, .networkOutBytesPerSec,
            .networkInterfaceInBytesPerSec, .networkInterfaceOutBytesPerSec,
            .diskThroughputBytesPerSec, .diskReadBytesPerSec, .diskWriteBytesPerSec:
            return .bytesPerSecond
        case .diskSMARTStatusCode:
            return .scalar
        }
    }

    public var storageKey: String {
        switch self {
        case .cpuTotalPercent:
            return "cpuTotalPercent"
        case .cpuUserPercent:
            return "cpuUserPercent"
        case .cpuSystemPercent:
            return "cpuSystemPercent"
        case .cpuIdlePercent:
            return "cpuIdlePercent"
        case .cpuCorePercent(let index):
            return "cpuCorePercent:\(index)"
        case .cpuLoadAverage1:
            return "cpuLoadAverage1"
        case .cpuLoadAverage5:
            return "cpuLoadAverage5"
        case .cpuLoadAverage15:
            return "cpuLoadAverage15"
        case .gpuProcessorPercent:
            return "gpuProcessorPercent"
        case .gpuMemoryPercent:
            return "gpuMemoryPercent"
        case .framesPerSecond:
            return "framesPerSecond"
        case .uptimeSeconds:
            return "uptimeSeconds"
        case .thermalStateLevel:
            return "thermalStateLevel"
        case .temperaturePrimaryCelsius:
            return "temperaturePrimaryCelsius"
        case .temperatureMaxCelsius:
            return "temperatureMaxCelsius"
        case .batteryChargePercent:
            return "batteryChargePercent"
        case .batteryCurrentMilliAmps:
            return "batteryCurrentMilliAmps"
        case .batteryTimeRemainingMinutes:
            return "batteryTimeRemainingMinutes"
        case .batteryHealthPercent:
            return "batteryHealthPercent"
        case .batteryCycleCount:
            return "batteryCycleCount"
        case .batteryIsCharging:
            return "batteryIsCharging"
        case .memoryUsedBytes:
            return "memoryUsedBytes"
        case .memoryFreeBytes:
            return "memoryFreeBytes"
        case .memoryCompressedBytes:
            return "memoryCompressedBytes"
        case .memorySwapUsedBytes:
            return "memorySwapUsedBytes"
        case .memorySwapTotalBytes:
            return "memorySwapTotalBytes"
        case .memoryActiveBytes:
            return "memoryActiveBytes"
        case .memoryWiredBytes:
            return "memoryWiredBytes"
        case .memoryCacheBytes:
            return "memoryCacheBytes"
        case .memoryAppBytes:
            return "memoryAppBytes"
        case .memoryPressureLevel:
            return "memoryPressureLevel"
        case .memoryPageInsBytesPerSec:
            return "memoryPageInsBytesPerSec"
        case .memoryPageOutsBytesPerSec:
            return "memoryPageOutsBytesPerSec"
        case .networkInBytesPerSec:
            return "networkInBytesPerSec"
        case .networkOutBytesPerSec:
            return "networkOutBytesPerSec"
        case .networkInterfaceInBytesPerSec(let interface):
            return "networkInterfaceInBytesPerSec:\(interface)"
        case .networkInterfaceOutBytesPerSec(let interface):
            return "networkInterfaceOutBytesPerSec:\(interface)"
        case .diskThroughputBytesPerSec:
            return "diskThroughputBytesPerSec"
        case .diskReadBytesPerSec:
            return "diskReadBytesPerSec"
        case .diskWriteBytesPerSec:
            return "diskWriteBytesPerSec"
        case .diskFreeBytes:
            return "diskFreeBytes"
        case .diskSMARTStatusCode:
            return "diskSMARTStatusCode"
        }
    }

    public init?(storageKey: String) {
        let components = storageKey.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let rawKey = String(components.first ?? "")
        let payload = components.count > 1 ? String(components[1]) : nil

        switch rawKey {
        case "cpuTotalPercent":
            self = .cpuTotalPercent
        case "cpuUserPercent":
            self = .cpuUserPercent
        case "cpuSystemPercent":
            self = .cpuSystemPercent
        case "cpuIdlePercent":
            self = .cpuIdlePercent
        case "cpuCorePercent":
            guard let payload, let index = Int(payload) else { return nil }
            self = .cpuCorePercent(index)
        case "cpuLoadAverage1":
            self = .cpuLoadAverage1
        case "cpuLoadAverage5":
            self = .cpuLoadAverage5
        case "cpuLoadAverage15":
            self = .cpuLoadAverage15
        case "gpuProcessorPercent":
            self = .gpuProcessorPercent
        case "gpuMemoryPercent":
            self = .gpuMemoryPercent
        case "framesPerSecond":
            self = .framesPerSecond
        case "uptimeSeconds":
            self = .uptimeSeconds
        case "thermalStateLevel":
            self = .thermalStateLevel
        case "temperaturePrimaryCelsius":
            self = .temperaturePrimaryCelsius
        case "temperatureMaxCelsius":
            self = .temperatureMaxCelsius
        case "batteryChargePercent":
            self = .batteryChargePercent
        case "batteryCurrentMilliAmps":
            self = .batteryCurrentMilliAmps
        case "batteryTimeRemainingMinutes":
            self = .batteryTimeRemainingMinutes
        case "batteryHealthPercent":
            self = .batteryHealthPercent
        case "batteryCycleCount":
            self = .batteryCycleCount
        case "batteryIsCharging":
            self = .batteryIsCharging
        case "memoryUsedBytes":
            self = .memoryUsedBytes
        case "memoryFreeBytes":
            self = .memoryFreeBytes
        case "memoryCompressedBytes":
            self = .memoryCompressedBytes
        case "memorySwapUsedBytes":
            self = .memorySwapUsedBytes
        case "memorySwapTotalBytes":
            self = .memorySwapTotalBytes
        case "memoryActiveBytes":
            self = .memoryActiveBytes
        case "memoryWiredBytes":
            self = .memoryWiredBytes
        case "memoryCacheBytes":
            self = .memoryCacheBytes
        case "memoryAppBytes":
            self = .memoryAppBytes
        case "memoryPressureLevel":
            self = .memoryPressureLevel
        case "memoryPageInsBytesPerSec":
            self = .memoryPageInsBytesPerSec
        case "memoryPageOutsBytesPerSec":
            self = .memoryPageOutsBytesPerSec
        case "networkInBytesPerSec":
            self = .networkInBytesPerSec
        case "networkOutBytesPerSec":
            self = .networkOutBytesPerSec
        case "networkInterfaceInBytesPerSec":
            guard let payload else { return nil }
            self = .networkInterfaceInBytesPerSec(payload)
        case "networkInterfaceOutBytesPerSec":
            guard let payload else { return nil }
            self = .networkInterfaceOutBytesPerSec(payload)
        case "diskThroughputBytesPerSec":
            self = .diskThroughputBytesPerSec
        case "diskReadBytesPerSec":
            self = .diskReadBytesPerSec
        case "diskWriteBytesPerSec":
            self = .diskWriteBytesPerSec
        case "diskFreeBytes":
            self = .diskFreeBytes
        case "diskSMARTStatusCode":
            self = .diskSMARTStatusCode
        default:
            return nil
        }
    }
}
