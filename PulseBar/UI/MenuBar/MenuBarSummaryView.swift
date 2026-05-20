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
            case .value:
                Text(valueText)
                    .lineLimit(1)
            case .label:
                Text(metric.shortMenuLabel)
                    .lineLimit(1)
            case .icon:
                Image(systemName: metric.systemImage)
                    .font(iconFont)
            case .iconText:
                HStack(spacing: 4) {
                    Image(systemName: metric.systemImage)
                        .font(iconFont)
                    Text(valueText)
                        .lineLimit(1)
                }
            case .pieValue:
                HStack(spacing: 4) {
                    MenuBarPieGauge(value: gaugeValue, tint: tintColor)
                    Text(valueText)
                        .lineLimit(1)
                }
            case .graph:
                MenuBarBarGraph(values: sparklineValues, tint: tintColor)
            case .sparklineValue:
                HStack(spacing: 5) {
                    MenuBarBarGraph(values: sparklineValues, tint: tintColor)
                    Text(valueText)
                        .lineLimit(1)
                }
            case .history:
                MenuBarHistoryGraph(values: sparklineValues, tint: tintColor)
            case .historyValue:
                HStack(spacing: 5) {
                    MenuBarHistoryGraph(values: sparklineValues, tint: tintColor)
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

    private var gaugeValue: Double {
        guard let value = sparklineValues.last else { return 0 }
        switch metric {
        case .cpu, .battery:
            return min(max(value / 100, 0), 1)
        case .temperature:
            return min(max(value / 100, 0), 1)
        case .memory, .network, .disk:
            let maxValue = max(sparklineValues.max() ?? 1, 1)
            return min(max(value / maxValue, 0), 1)
        }
    }
}

private struct MenuBarPieGauge: View {
    let value: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 13, height: 13)
    }
}

private struct MenuBarBarGraph: View {
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

private struct MenuBarHistoryGraph: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let values = Array(values.suffix(28))
            if values.count < 2 {
                Capsule()
                    .fill(tint.opacity(0.2))
            } else {
                let maxValue = max(values.max() ?? 1, 1)
                let minValue = values.min() ?? 0
                let span = max(maxValue - minValue, 1)
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = proxy.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                        let normalized = (value - minValue) / span
                        let y = proxy.size.height - (CGFloat(normalized) * proxy.size.height)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
            }
        }
        .frame(width: 30, height: 13)
    }
}

private extension MenuBarMetricID {
    var shortMenuLabel: String {
        switch self {
        case .cpu:
            return "CPU"
        case .memory:
            return "MEM"
        case .battery:
            return "BAT"
        case .network:
            return "NET"
        case .disk:
            return "DSK"
        case .temperature:
            return "TEMP"
        }
    }
}
