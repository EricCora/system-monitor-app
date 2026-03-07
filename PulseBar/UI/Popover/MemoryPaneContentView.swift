import Charts
import SwiftUI
import PulseBarCore

struct MemoryPaneContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var compositionHistory: [MemoryHistoryPoint] = []
    @State private var pressureHistory: [MetricHistoryPoint] = []
    @State private var swapHistory: [MetricHistoryPoint] = []
    @State private var pageInHistory: [MetricHistoryPoint] = []
    @State private var pageOutHistory: [MetricHistoryPoint] = []
    @State private var hoveredDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HistoryWindowSegmentedControl(
                options: MemoryHistoryWindow.allCases,
                selection: $coordinator.selectedMemoryHistoryWindow,
                paneController: paneController,
                label: \.label
            )

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeChart.title)
                        .font(.headline)
                    Text(activeChart.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if paneController.pinnedTarget != nil {
                    Button("Unpin") {
                        paneController.unpin()
                    }
                    .buttonStyle(.bordered)
                }
            }

            chartBody
                .frame(maxWidth: .infinity, minHeight: 300)

            summaryRow
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .task {
            await refresh()
        }
        .onChange(of: paneController.hoveredTarget) { _ in
            hoveredDate = nil
            Task { await refresh() }
        }
        .onChange(of: paneController.pinnedTarget) { _ in
            hoveredDate = nil
            Task { await refresh() }
        }
        .onChange(of: coordinator.selectedMemoryHistoryWindow) { _ in
            hoveredDate = nil
            Task { await refresh() }
        }
        .onReceive(coordinator.$latestSamples) { _ in
            Task { await refresh() }
        }
    }

    private var activeChart: MemoryPaneChart {
        if case .memory(let chart)? = paneController.activeTarget {
            return chart
        }
        return coordinator.selectedMemoryPaneChart
    }

    @ViewBuilder
    private var chartBody: some View {
        switch activeChart {
        case .composition:
            if compositionHistory.isEmpty {
                emptyState("Collecting memory history")
            } else {
                MemoryCompositionChart(
                    history: compositionHistory,
                    hoveredDate: $hoveredDate
                )
            }
        case .pressure:
            if pressureHistory.isEmpty {
                emptyState("Collecting pressure history")
            } else {
                MetricLinePaneChart(
                    primarySeries: pressureHistory,
                    primaryColor: .cyan,
                    hoveredDate: $hoveredDate
                )
            }
        case .swap:
            if swapHistory.isEmpty {
                emptyState("Collecting swap history")
            } else {
                MetricLinePaneChart(
                    primarySeries: swapHistory,
                    primaryColor: .cyan,
                    hoveredDate: $hoveredDate
                )
            }
        case .pages:
            if pageInHistory.isEmpty && pageOutHistory.isEmpty {
                emptyState("Collecting paging history")
            } else {
                MetricLinePaneChart(
                    primarySeries: pageInHistory,
                    primaryLabel: "Page Ins",
                    primaryColor: .cyan,
                    secondarySeries: pageOutHistory,
                    secondaryLabel: "Page Outs",
                    secondaryColor: .orange,
                    hoveredDate: $hoveredDate
                )
            }
        }
    }

    private var summaryRow: some View {
        HStack {
            switch activeChart {
            case .composition:
                if let point = nearestCompositionPoint {
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        "W \(UnitsFormatter.format(point.wiredBytes, unit: .bytes))  A \(UnitsFormatter.format(point.activeBytes, unit: .bytes))  C \(UnitsFormatter.format(point.compressedBytes, unit: .bytes))  F \(UnitsFormatter.format(point.freeBytes, unit: .bytes))"
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    emptySummary
                }
            case .pressure:
                metricSummary(primary: nearestMetricPoint(in: pressureHistory))
            case .swap:
                metricSummary(primary: nearestMetricPoint(in: swapHistory))
            case .pages:
                if let point = nearestMetricPoint(in: pageInHistory) ?? nearestMetricPoint(in: pageOutHistory) {
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        "In \(UnitsFormatter.format(nearestMetricPoint(in: pageInHistory)?.value ?? 0, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))  Out \(UnitsFormatter.format(nearestMetricPoint(in: pageOutHistory)?.value ?? 0, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))"
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    emptySummary
                }
            }
        }
        .font(.caption)
        .frame(height: 18)
    }

    @ViewBuilder
    private func metricSummary(primary: MetricHistoryPoint?) -> some View {
        if let primary {
            Text(primary.timestamp.formatted(date: .omitted, time: .standard))
                .foregroundStyle(.secondary)
            Spacer()
            Text(UnitsFormatter.format(primary.value, unit: primary.unit, throughputUnit: coordinator.throughputUnit))
                .font(.caption.monospacedDigit())
        } else {
            emptySummary
        }
    }

    @ViewBuilder
    private var emptySummary: some View {
        Text(" ")
        Spacer()
        Text(" ")
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var nearestCompositionPoint: MemoryHistoryPoint? {
        if let hoveredDate {
            return compositionHistory.min(by: {
                abs($0.timestamp.timeIntervalSince(hoveredDate)) < abs($1.timestamp.timeIntervalSince(hoveredDate))
            })
        }
        return compositionHistory.last
    }

    private func nearestMetricPoint(in series: [MetricHistoryPoint]) -> MetricHistoryPoint? {
        if let hoveredDate {
            return series.min(by: {
                abs($0.timestamp.timeIntervalSince(hoveredDate)) < abs($1.timestamp.timeIntervalSince(hoveredDate))
            })
        }
        return series.last
    }

    private func refresh() async {
        compositionHistory = ChartSeriesSanitizer.memoryHistory(await coordinator.memoryHistorySeries(
            window: coordinator.selectedMemoryHistoryWindow,
            maxPoints: 900
        ))
        let historyWindow = coordinator.selectedMemoryHistoryWindow.asMetricHistoryWindow
        pressureHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .memoryPressureLevel, window: historyWindow, maxPoints: 900)
        )
        swapHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .memorySwapUsedBytes, window: historyWindow, maxPoints: 900)
        )
        pageInHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .memoryPageInsBytesPerSec, window: historyWindow, maxPoints: 900)
        )
        pageOutHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .memoryPageOutsBytesPerSec, window: historyWindow, maxPoints: 900)
        )
    }
}

private extension MemoryPaneChart {
    var title: String {
        switch self {
        case .pressure:
            return "Pressure"
        case .composition:
            return "Memory"
        case .swap:
            return "Swap Memory"
        case .pages:
            return "Pages"
        }
    }

    var subtitle: String {
        switch self {
        case .pressure:
            return "Memory pressure over time"
        case .composition:
            return "Wired, active, compressed, and free memory"
        case .swap:
            return "Swap used over time"
        case .pages:
            return "Page-ins and page-outs throughput"
        }
    }
}

private extension MemoryHistoryWindow {
    var asMetricHistoryWindow: MetricHistoryWindow {
        switch self {
        case .oneHour:
            return .oneHour
        case .twentyFourHours:
            return .twentyFourHours
        case .sevenDays:
            return .sevenDays
        case .thirtyDays:
            return .thirtyDays
        }
    }
}

private struct MemoryCompositionChart: View {
    let history: [MemoryHistoryPoint]
    @Binding var hoveredDate: Date?

    private var chartPoints: [MemoryCompositionSeriesPoint] {
        ChartSeriesSanitizer.memoryHistory(history).flatMap { point in
            let total = max(1, point.totalBytes)
            return [
                MemoryCompositionSeriesPoint(timestamp: point.timestamp, component: .wired, percent: min(max((point.wiredBytes / total) * 100, 0), 100)),
                MemoryCompositionSeriesPoint(timestamp: point.timestamp, component: .active, percent: min(max((point.activeBytes / total) * 100, 0), 100)),
                MemoryCompositionSeriesPoint(timestamp: point.timestamp, component: .compressed, percent: min(max((point.compressedBytes / total) * 100, 0), 100)),
                MemoryCompositionSeriesPoint(timestamp: point.timestamp, component: .free, percent: min(max((point.freeBytes / total) * 100, 0), 100))
            ]
        }
    }

    var body: some View {
        Chart(chartPoints) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Percent", point.percent),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Component", point.component.rawValue))
            .interpolationMethod(.linear)

            if let hoveredDate {
                RuleMark(x: .value("Hover", hoveredDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: 0...100)
        .chartForegroundStyleScale([
            MemoryCompositionSeriesPoint.Component.wired.rawValue: Color.cyan,
            MemoryCompositionSeriesPoint.Component.active.rawValue: Color.red,
            MemoryCompositionSeriesPoint.Component.compressed.rawValue: Color.purple,
            MemoryCompositionSeriesPoint.Component.free.rawValue: Color.gray.opacity(0.55)
        ])
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text(String(format: "%.0f%%", percent))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let xPosition = location.x - geometry[proxy.plotAreaFrame].origin.x
                            guard xPosition >= 0,
                                  xPosition <= proxy.plotAreaSize.width,
                                  let date: Date = proxy.value(atX: xPosition, as: Date.self) else {
                                hoveredDate = nil
                                return
                            }
                            hoveredDate = date
                        case .ended:
                            hoveredDate = nil
                        }
                    }
            }
        }
        .frame(height: 300)
    }
}

private struct MetricLinePaneChart: View {
    let primarySeries: [MetricHistoryPoint]
    var primaryLabel: String = "Series"
    let primaryColor: Color
    var secondarySeries: [MetricHistoryPoint] = []
    var secondaryLabel: String = ""
    var secondaryColor: Color = .secondary
    @Binding var hoveredDate: Date?

    private var sanitizedPrimarySeries: [MetricHistoryPoint] {
        ChartSeriesSanitizer.metricHistory(primarySeries)
    }

    private var sanitizedSecondarySeries: [MetricHistoryPoint] {
        ChartSeriesSanitizer.metricHistory(secondarySeries)
    }

    var body: some View {
        Chart {
            ForEach(sanitizedPrimarySeries, id: \.timestamp) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value(primaryLabel, point.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(primaryColor)
            }

            ForEach(sanitizedSecondarySeries, id: \.timestamp) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value(secondaryLabel, point.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(secondaryColor)
            }

            if let hoveredDate {
                RuleMark(x: .value("Hover", hoveredDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: yDomain)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let xPosition = location.x - geometry[proxy.plotAreaFrame].origin.x
                            guard xPosition >= 0,
                                  xPosition <= proxy.plotAreaSize.width,
                                  let date: Date = proxy.value(atX: xPosition, as: Date.self) else {
                                hoveredDate = nil
                                return
                            }
                            hoveredDate = date
                        case .ended:
                            hoveredDate = nil
                        }
                    }
            }
        }
        .frame(height: 300)
    }

    private var yDomain: ClosedRange<Double> {
        let values = (sanitizedPrimarySeries + sanitizedSecondarySeries).map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }
        if minValue == maxValue {
            let delta = max(1, abs(minValue * 0.1))
            return max(0, minValue - delta)...(maxValue + delta)
        }
        let padding = (maxValue - minValue) * 0.12
        return max(0, minValue - padding)...(maxValue + padding)
    }
}

private struct MemoryCompositionSeriesPoint: Identifiable {
    enum Component: String {
        case wired
        case active
        case compressed
        case free
    }

    let timestamp: Date
    let component: Component
    let percent: Double

    var id: String { "\(timestamp.timeIntervalSince1970)-\(component.rawValue)" }
}
