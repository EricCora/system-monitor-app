import SwiftUI
import PulseBarCore

struct MenuBarSummaryView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: itemSpacing) {
            ForEach(enabledMetrics, id: \.self) { metric in
                MenuBarMetricChip(
                    metric: metric,
                    style: coordinator.menuBarMetricStyle(for: metric),
                    displayMode: coordinator.menuBarDisplayMode,
                    valueText: MenuBarMetricSummaryFormatter.valueText(
                        for: metric,
                        latestSamples: coordinator.latestSamples,
                        thermalState: coordinator.latestThermalState(),
                        throughputUnit: coordinator.throughputUnit
                    ),
                    fullText: MenuBarMetricSummaryFormatter.text(
                        for: metric,
                        latestSamples: coordinator.latestSamples,
                        thermalState: coordinator.latestThermalState(),
                        throughputUnit: coordinator.throughputUnit
                    ),
                    sparklineValues: coordinator.menuBarSparklineValues(for: metric)
                )
            }
        }
        .font(font)
    }

    private var enabledMetrics: [MenuBarMetricID] {
        MenuBarMetricID.allCases.filter { metric in
            switch metric {
            case .cpu:
                return coordinator.showCPUInMenu
            case .memory:
                return coordinator.showMemoryInMenu
            case .battery:
                return coordinator.showBatteryInMenu
            case .network:
                return coordinator.showNetworkInMenu
            case .disk:
                return coordinator.showDiskInMenu
            case .temperature:
                return coordinator.showTemperatureInMenu
            }
        }
    }

    private var itemSpacing: CGFloat {
        switch coordinator.menuBarDisplayMode {
        case .compact:
            return 6
        case .balanced:
            return 8
        case .dense:
            return 4
        }
    }

    private var font: Font {
        switch coordinator.menuBarDisplayMode {
        case .compact:
            return .system(size: 11, weight: .medium, design: .rounded)
        case .balanced:
            return .system(size: 11.5, weight: .semibold, design: .rounded)
        case .dense:
            return .system(size: 10.5, weight: .medium, design: .rounded)
        }
    }
}

private struct MenuBarMetricChip: View {
    let metric: MenuBarMetricID
    let style: MenuBarMetricStyle
    let displayMode: MenuBarDisplayMode
    let valueText: String
    let fullText: String
    let sparklineValues: [Double]

    var body: some View {
        Group {
            switch style {
            case .text:
                Text(fullText)
                    .lineLimit(1)
            case .iconText:
                HStack(spacing: 4) {
                    Image(systemName: metric.systemImage)
                        .font(iconFont)
                    Text(valueText)
                        .lineLimit(1)
                }
            case .sparklineValue:
                HStack(spacing: 5) {
                    MenuBarSparkline(values: sparklineValues, tint: tintColor)
                    Text(valueText)
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(tintColor)
    }

    private var iconFont: Font {
        switch displayMode {
        case .compact:
            return .system(size: 10, weight: .semibold)
        case .balanced:
            return .system(size: 10.5, weight: .semibold)
        case .dense:
            return .system(size: 9.5, weight: .semibold)
        }
    }

    private var tintColor: Color {
        switch metric {
        case .cpu:
            return .blue
        case .memory:
            return .pink
        case .battery:
            return .green
        case .network:
            return .cyan
        case .disk:
            return .orange
        case .temperature:
            return .red
        }
    }
}

private struct MenuBarSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let values = Array(values.suffix(18))
            if values.count < 2 {
                Capsule()
                    .fill(tint.opacity(0.2))
            } else {
                let maxValue = max(values.max() ?? 1, 1)
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Capsule()
                            .fill(tint)
                            .frame(height: max(2, CGFloat(value / maxValue) * proxy.size.height))
                    }
                }
            }
        }
        .frame(width: 28, height: 12)
    }
}
