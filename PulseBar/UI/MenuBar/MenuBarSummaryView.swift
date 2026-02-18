import SwiftUI
import PulseBarCore

struct MenuBarSummaryView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 8) {
            if coordinator.showCPUInMenu {
                Text(cpuText)
            }
            if coordinator.showMemoryInMenu {
                Text(memoryText)
            }
            if coordinator.showNetworkInMenu {
                Text(networkText)
            }
            if coordinator.showDiskInMenu {
                Text(diskText)
            }
            if coordinator.showTemperatureInMenu {
                Text(temperatureText)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
    }

    private var cpuText: String {
        guard let sample = coordinator.latestValue(for: .cpuTotalPercent) else {
            return "CPU --"
        }
        return "CPU \(UnitsFormatter.format(sample.value, unit: .percent))"
    }

    private var memoryText: String {
        guard let sample = coordinator.latestValue(for: .memoryUsedBytes) else {
            return "MEM --"
        }
        return "MEM \(UnitsFormatter.format(sample.value, unit: .bytes))"
    }

    private var networkText: String {
        let inValue = coordinator.latestValue(for: .networkInBytesPerSec)?.value ?? 0
        let outValue = coordinator.latestValue(for: .networkOutBytesPerSec)?.value ?? 0
        let inText = UnitsFormatter.format(inValue, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit)
        let outText = UnitsFormatter.format(outValue, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit)
        return "NET ↓\(inText) ↑\(outText)"
    }

    private var diskText: String {
        guard let sample = coordinator.latestValue(for: .diskThroughputBytesPerSec) else {
            return "DSK --"
        }
        let value = UnitsFormatter.format(sample.value, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit)
        return "DSK \(value)"
    }

    private var temperatureText: String {
        if let sample = coordinator.latestValue(for: .temperaturePrimaryCelsius) {
            return "TMP \(UnitsFormatter.format(sample.value, unit: .celsius))"
        }
        return "TMP \(coordinator.latestThermalState().shortLabel)"
    }
}
