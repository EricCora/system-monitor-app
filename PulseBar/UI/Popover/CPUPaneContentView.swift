import Charts
import SwiftUI
import PulseBarCore

struct CPUPaneContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var userHistory: [MetricHistoryPoint] = []
    @State private var systemHistory: [MetricHistoryPoint] = []
    @State private var idleHistory: [MetricHistoryPoint] = []
    @State private var load1History: [MetricHistoryPoint] = []
    @State private var load5History: [MetricHistoryPoint] = []
    @State private var load15History: [MetricHistoryPoint] = []
    @State private var gpuProcessorHistory: [MetricHistoryPoint] = []
    @State private var gpuMemoryHistory: [MetricHistoryPoint] = []
    @State private var fpsHistory: [MetricHistoryPoint] = []
    @State private var hoveredDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HistoryWindowSegmentedControl(
                options: MetricHistoryWindow.allCases,
                selection: $coordinator.selectedCPUHistoryWindow,
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
        .onChange(of: coordinator.selectedCPUHistoryWindow) { _ in
            hoveredDate = nil
            Task { await refresh() }
        }
        .onReceive(coordinator.$latestSamples) { _ in
            Task { await refresh() }
        }
    }

    private var activeChart: CPUPaneChart {
        if case .cpu(let chart)? = paneController.activeTarget {
            return chart
        }
        return coordinator.selectedCPUPaneChart
    }

    @ViewBuilder
    private var chartBody: some View {
        switch activeChart {
        case .usage:
            if userHistory.isEmpty && systemHistory.isEmpty {
                emptyState("Collecting CPU history")
            } else {
                CPUUsagePaneChart(
                    userHistory: userHistory,
                    systemHistory: systemHistory,
                    hoveredDate: $hoveredDate
                )
            }
        case .loadAverage:
            if load1History.isEmpty && load5History.isEmpty && load15History.isEmpty {
                emptyState("Collecting load average history")
            } else {
                MultiSeriesLinePaneChart(
                    series: [
                        ("1 Minute", load1History, Color.cyan),
                        ("5 Minute", load5History, Color.red),
                        ("15 Minute", load15History, Color.gray)
                    ],
                    hoveredDate: $hoveredDate
                )
            }
        case .gpu:
            if coordinator.latestGPUSummary?.available == false && gpuProcessorHistory.isEmpty && gpuMemoryHistory.isEmpty {
                emptyState(coordinator.latestGPUSummary?.statusMessage ?? "GPU telemetry unavailable")
            } else {
                MultiSeriesLinePaneChart(
                    series: [
                        ("Processor", gpuProcessorHistory, Color.cyan),
                        ("Memory", gpuMemoryHistory, Color.blue)
                    ],
                    hoveredDate: $hoveredDate
                )
            }
        case .framesPerSecond:
            if fpsHistory.isEmpty {
                emptyState("Collecting frames-per-second history")
            } else {
                MultiSeriesLinePaneChart(
                    series: [("FPS", fpsHistory, Color.cyan)],
                    hoveredDate: $hoveredDate
                )
            }
        }
    }

    private var summaryRow: some View {
        HStack {
            switch activeChart {
            case .usage:
                if let point = nearestPoint(in: userHistory) ?? nearestPoint(in: systemHistory) {
                    let user = nearestPoint(in: userHistory)?.value ?? 0
                    let system = nearestPoint(in: systemHistory)?.value ?? 0
                    let idle = nearestPoint(in: idleHistory)?.value ?? max(0, 100 - user - system)
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        "User \(UnitsFormatter.format(user, unit: .percent))  System \(UnitsFormatter.format(system, unit: .percent))  Idle \(UnitsFormatter.format(idle, unit: .percent))"
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    emptySummary
                }
            case .loadAverage:
                if let point = nearestPoint(in: load1History) ?? nearestPoint(in: load5History) ?? nearestPoint(in: load15History) {
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        String(
                            format: "1m %.2f  5m %.2f  15m %.2f",
                            nearestPoint(in: load1History)?.value ?? 0,
                            nearestPoint(in: load5History)?.value ?? 0,
                            nearestPoint(in: load15History)?.value ?? 0
                        )
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    emptySummary
                }
            case .gpu:
                if let point = nearestPoint(in: gpuProcessorHistory) ?? nearestPoint(in: gpuMemoryHistory) {
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        "Processor \(UnitsFormatter.format(nearestPoint(in: gpuProcessorHistory)?.value ?? 0, unit: .percent))  Memory \(UnitsFormatter.format(nearestPoint(in: gpuMemoryHistory)?.value ?? 0, unit: .percent))"
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    emptySummary
                }
            case .framesPerSecond:
                if let point = nearestPoint(in: fpsHistory) {
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f fps", point.value))
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
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private func nearestPoint(in series: [MetricHistoryPoint]) -> MetricHistoryPoint? {
        if let hoveredDate {
            return series.min(by: {
                abs($0.timestamp.timeIntervalSince(hoveredDate)) < abs($1.timestamp.timeIntervalSince(hoveredDate))
            })
        }
        return series.last
    }

    private func refresh() async {
        userHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .cpuUserPercent, window: coordinator.selectedCPUHistoryWindow, maxPoints: 900)
        )
        systemHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .cpuSystemPercent, window: coordinator.selectedCPUHistoryWindow, maxPoints: 900)
        )
        idleHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .cpuIdlePercent, window: coordinator.selectedCPUHistoryWindow, maxPoints: 900)
        )
        load1History = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .cpuLoadAverage1, window: coordinator.selectedCPUHistoryWindow, maxPoints: 900)
        )
        load5History = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .cpuLoadAverage5, window: coordinator.selectedCPUHistoryWindow, maxPoints: 900)
        )
        load15History = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .cpuLoadAverage15, window: coordinator.selectedCPUHistoryWindow, maxPoints: 900)
        )
        gpuProcessorHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .gpuProcessorPercent, window: coordinator.selectedCPUHistoryWindow, maxPoints: 900)
        )
        gpuMemoryHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .gpuMemoryPercent, window: coordinator.selectedCPUHistoryWindow, maxPoints: 900)
        )
        fpsHistory = ChartSeriesSanitizer.metricHistory(
            await coordinator.metricHistorySeries(for: .framesPerSecond, window: coordinator.selectedCPUHistoryWindow, maxPoints: 900)
        )
    }
}

private extension CPUPaneChart {
    var title: String {
        switch self {
        case .usage:
            return "CPU"
        case .loadAverage:
            return "Load Average"
        case .gpu:
            return "Apple Silicon"
        case .framesPerSecond:
            return "Frames Per Second"
        }
    }

    var subtitle: String {
        switch self {
        case .usage:
            return "User and system CPU usage"
        case .loadAverage:
            return "1, 5, and 15 minute load averages"
        case .gpu:
            return "GPU processor and memory history"
        case .framesPerSecond:
            return "Display refresh sampling"
        }
    }
}

private struct CPUUsagePaneChart: View {
    let userHistory: [MetricHistoryPoint]
    let systemHistory: [MetricHistoryPoint]
    @Binding var hoveredDate: Date?

    private var chartPoints: [CPUUsageSeriesPoint] {
        let sanitizedUserHistory = ChartSeriesSanitizer.metricHistory(userHistory)
        let sanitizedSystemHistory = ChartSeriesSanitizer.metricHistory(systemHistory)
        var output: [CPUUsageSeriesPoint] = []
        output.reserveCapacity(userHistory.count + systemHistory.count)
        output.append(contentsOf: sanitizedUserHistory.map { CPUUsageSeriesPoint(timestamp: $0.timestamp, series: .user, value: $0.value) })
        output.append(contentsOf: sanitizedSystemHistory.map { CPUUsageSeriesPoint(timestamp: $0.timestamp, series: .system, value: $0.value) })
        return output.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        Chart(chartPoints) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Percent", point.value),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Series", point.series.rawValue))
            .interpolationMethod(.linear)

            if let hoveredDate {
                RuleMark(x: .value("Hover", hoveredDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: 0...100)
        .chartForegroundStyleScale([
            CPUUsageSeriesPoint.Series.user.rawValue: Color.cyan,
            CPUUsageSeriesPoint.Series.system.rawValue: Color.red
        ])
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

private struct MultiSeriesLinePaneChart: View {
    let series: [(label: String, points: [MetricHistoryPoint], color: Color)]
    @Binding var hoveredDate: Date?

    private var sanitizedSeries: [(label: String, points: [MetricHistoryPoint], color: Color)] {
        series.map { seriesEntry in
            (
                label: seriesEntry.label,
                points: ChartSeriesSanitizer.metricHistory(seriesEntry.points),
                color: seriesEntry.color
            )
        }
    }

    var body: some View {
        Chart {
            ForEach(Array(sanitizedSeries.enumerated()), id: \.offset) { _, seriesEntry in
                ForEach(seriesEntry.points, id: \.timestamp) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value(seriesEntry.label, point.value)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(seriesEntry.color)
                }
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
        let values = sanitizedSeries.flatMap { $0.points.map(\.value) }
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

private struct CPUUsageSeriesPoint: Identifiable {
    enum Series: String {
        case user
        case system
    }

    let timestamp: Date
    let series: Series
    let value: Double

    var id: String { "\(timestamp.timeIntervalSince1970)-\(series.rawValue)" }
}
