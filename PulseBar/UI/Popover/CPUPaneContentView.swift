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
    @State private var viewport = ChartViewport()
    @State private var zoomSelectionRect: CGRect?
    @State private var lastRefreshContextID = ""
    @State private var usageChartModel: PreparedCPUUsageChartModel?
    @State private var loadAverageChartModel: PreparedCPUMetricChartModel?
    @State private var gpuChartModel: PreparedCPUMetricChartModel?
    @State private var fpsChartModel: PreparedCPUMetricChartModel?
    @State private var deferredRefreshTriggerID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: $coordinator.selectedCPUHistoryWindow,
                paneController: paneController,
                style: .detached
            )

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeChart.title)
                        .font(.headline)
                    Text(activeChart.subtitle)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }

                Spacer()

                if paneController.pinnedTarget != nil {
                    Button("Unpin") {
                        paneController.unpin()
                    }
                    .buttonStyle(.bordered)
                }

                if viewport.isZoomed {
                    Button("Reset Zoom") {
                        viewport.reset()
                        zoomSelectionRect = nil
                        hoveredDate = nil
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
                .fill(DashboardPalette.sectionFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                )
        )
        .task(id: refreshTriggerID) {
            if lastRefreshContextID != contextRefreshID {
                hoveredDate = nil
                viewport.reset()
                zoomSelectionRect = nil
                lastRefreshContextID = contextRefreshID
            }
            if isInteractionActive {
                deferredRefreshTriggerID = refreshTriggerID
                return
            }
            await refresh()
        }
        .onChange(of: isInteractionActive) { isActive in
            guard !isActive, deferredRefreshTriggerID != nil else { return }
            deferredRefreshTriggerID = nil
            Task {
                await refresh()
            }
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
                    model: usageChartModel ?? PreparedCPUUsageChartModel.empty,
                    areaOpacity: coordinator.chartAreaOpacity,
                    paneController: paneController,
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    zoomSelectionRect: $zoomSelectionRect
                )
            }
        case .loadAverage:
            if load1History.isEmpty && load5History.isEmpty && load15History.isEmpty {
                emptyState("Collecting load average history")
            } else {
                MultiSeriesLinePaneChart(
                    model: loadAverageChartModel ?? PreparedCPUMetricChartModel.empty,
                    areaOpacity: coordinator.chartAreaOpacity,
                    paneController: paneController,
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    zoomSelectionRect: $zoomSelectionRect
                )
            }
        case .gpu:
            if coordinator.latestGPUSummary?.available == false && gpuProcessorHistory.isEmpty && gpuMemoryHistory.isEmpty {
                emptyState(coordinator.latestGPUSummary?.statusMessage ?? "GPU telemetry unavailable")
            } else {
                MultiSeriesLinePaneChart(
                    model: gpuChartModel ?? PreparedCPUMetricChartModel.empty,
                    areaOpacity: coordinator.chartAreaOpacity,
                    paneController: paneController,
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    zoomSelectionRect: $zoomSelectionRect
                )
            }
        case .framesPerSecond:
            if fpsHistory.isEmpty {
                emptyState("Collecting frames-per-second history")
            } else {
                MultiSeriesLinePaneChart(
                    model: fpsChartModel ?? PreparedCPUMetricChartModel.empty,
                    areaOpacity: coordinator.chartAreaOpacity,
                    paneController: paneController,
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    zoomSelectionRect: $zoomSelectionRect
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
                        .foregroundStyle(DashboardPalette.secondaryText)
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
                        .foregroundStyle(DashboardPalette.secondaryText)
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
                        .foregroundStyle(DashboardPalette.secondaryText)
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
                        .foregroundStyle(DashboardPalette.secondaryText)
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
        coordinator.performanceDiagnosticsStore.recordDetachedPaneQuery()
        let start = ContinuousClock.now
        let window = coordinator.selectedCPUHistoryWindow
        let maxPoints = 360

        switch activeChart {
        case .usage:
            async let user = coordinator.metricHistorySeries(for: .cpuUserPercent, window: window, maxPoints: maxPoints)
            async let system = coordinator.metricHistorySeries(for: .cpuSystemPercent, window: window, maxPoints: maxPoints)

            userHistory = await user
            systemHistory = await system
            idleHistory = []
            load1History = []
            load5History = []
            load15History = []
            gpuProcessorHistory = []
            gpuMemoryHistory = []
            fpsHistory = []

            usageChartModel = PreparedCPUUsageChartModel(userHistory: userHistory, systemHistory: systemHistory)
            loadAverageChartModel = nil
            gpuChartModel = nil
            fpsChartModel = nil

        case .loadAverage:
            async let load1 = coordinator.metricHistorySeries(for: .cpuLoadAverage1, window: window, maxPoints: maxPoints)
            async let load5 = coordinator.metricHistorySeries(for: .cpuLoadAverage5, window: window, maxPoints: maxPoints)
            async let load15 = coordinator.metricHistorySeries(for: .cpuLoadAverage15, window: window, maxPoints: maxPoints)

            load1History = await load1
            load5History = await load5
            load15History = await load15
            userHistory = []
            systemHistory = []
            idleHistory = []
            gpuProcessorHistory = []
            gpuMemoryHistory = []
            fpsHistory = []

            loadAverageChartModel = PreparedCPUMetricChartModel(
                series: [
                    ChartMetricSeriesDescriptor(key: "load.1", label: "1 Minute", color: .cyan, samples: load1History),
                    ChartMetricSeriesDescriptor(key: "load.5", label: "5 Minute", color: .red, samples: load5History),
                    ChartMetricSeriesDescriptor(key: "load.15", label: "15 Minute", color: .gray, samples: load15History)
                ],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12)
            )
            usageChartModel = nil
            gpuChartModel = nil
            fpsChartModel = nil

        case .gpu:
            async let gpuProcessor = coordinator.metricHistorySeries(for: .gpuProcessorPercent, window: window, maxPoints: maxPoints)
            async let gpuMemory = coordinator.metricHistorySeries(for: .gpuMemoryPercent, window: window, maxPoints: maxPoints)

            gpuProcessorHistory = await gpuProcessor
            gpuMemoryHistory = await gpuMemory
            userHistory = []
            systemHistory = []
            idleHistory = []
            load1History = []
            load5History = []
            load15History = []
            fpsHistory = []

            gpuChartModel = PreparedCPUMetricChartModel(
                series: [
                    ChartMetricSeriesDescriptor(key: "gpu.processor", label: "Processor", color: .cyan, samples: gpuProcessorHistory),
                    ChartMetricSeriesDescriptor(key: "gpu.memory", label: "Memory", color: .blue, samples: gpuMemoryHistory)
                ],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12)
            )
            usageChartModel = nil
            loadAverageChartModel = nil
            fpsChartModel = nil

        case .framesPerSecond:
            fpsHistory = await coordinator.metricHistorySeries(for: .framesPerSecond, window: window, maxPoints: maxPoints)
            userHistory = []
            systemHistory = []
            idleHistory = []
            load1History = []
            load5History = []
            load15History = []
            gpuProcessorHistory = []
            gpuMemoryHistory = []

            fpsChartModel = PreparedCPUMetricChartModel(
                series: [ChartMetricSeriesDescriptor(key: "fps", label: "FPS", color: .cyan, samples: fpsHistory)],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12)
            )
            usageChartModel = nil
            loadAverageChartModel = nil
            gpuChartModel = nil
        }
        let elapsed = start.duration(to: ContinuousClock.now)
        coordinator.performanceDiagnosticsStore.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }

    private var contextRefreshID: String {
        "\(activeChart.rawValue)-\(coordinator.selectedCPUHistoryWindow.rawValue)"
    }

    private var historyRefreshID: String {
        "\(contextRefreshID)-\(coordinator.metricHistoryRevision)"
    }

    private var refreshTriggerID: String {
        historyRefreshID
    }

    private var isInteractionActive: Bool {
        hoveredDate != nil || zoomSelectionRect != nil
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
    let model: PreparedCPUUsageChartModel
    let areaOpacity: Double
    let paneController: DetachedMetricsPaneController
    @Binding var hoveredDate: Date?
    @Binding var viewport: ChartViewport
    @Binding var zoomSelectionRect: CGRect?

    var body: some View {
        Chart(model.points) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Percent", point.value),
                series: .value("Segment", point.continuityKey),
                stacking: .standard
            )
            .foregroundStyle(point.series.color)
            .opacity(areaOpacity)
            .interpolationMethod(.linear)

            if let hoveredDate {
                RuleMark(x: .value("Hover", hoveredDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: viewport.xDomain ?? model.xDomain)
        .chartYScale(domain: viewport.yDomain ?? (0...100))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                DetachedChartInteractionOverlay(
                    proxy: proxy,
                    geometry: geometry,
                    paneController: paneController,
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    selectionRect: $zoomSelectionRect
                )
            }
        }
        .overlay(ChartZoomSelectionOverlay(selectionRect: zoomSelectionRect))
        .frame(height: 300)
    }
}

private struct MultiSeriesLinePaneChart: View {
    let model: PreparedCPUMetricChartModel
    let areaOpacity: Double
    let paneController: DetachedMetricsPaneController
    @Binding var hoveredDate: Date?
    @Binding var viewport: ChartViewport
    @Binding var zoomSelectionRect: CGRect?

    var body: some View {
        Chart(model.points) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                yStart: .value("Baseline", model.scale.renderedAreaBaseline(viewport: viewport)),
                yEnd: .value("Value", point.value),
                series: .value("Segment", point.continuityKey)
            )
            .foregroundStyle(point.color)
            .opacity(areaOpacity)
            .interpolationMethod(.linear)

            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value),
                series: .value("Segment", point.continuityKey)
            )
            .foregroundStyle(point.color)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.linear)

            if let hoveredDate {
                RuleMark(x: .value("Hover", hoveredDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: viewport.xDomain ?? model.scale.xDomain ?? model.fallbackXDomain)
        .chartYScale(domain: viewport.yDomain ?? model.scale.yDomain)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                DetachedChartInteractionOverlay(
                    proxy: proxy,
                    geometry: geometry,
                    paneController: paneController,
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    selectionRect: $zoomSelectionRect
                )
            }
        }
        .overlay(ChartZoomSelectionOverlay(selectionRect: zoomSelectionRect))
        .frame(height: 300)
    }
}

private struct CPUUsageSeriesPoint: Identifiable {
    enum Series: String {
        case user
        case system

        var color: Color {
            switch self {
            case .user:
                return .cyan
            case .system:
                return .red
            }
        }
    }

    let timestamp: Date
    let series: Series
    let continuityKey: String
    let value: Double

    var id: String { "\(continuityKey)-\(timestamp.timeIntervalSince1970)" }
}

private struct PreparedCPUUsageChartModel {
    let points: [CPUUsageSeriesPoint]
    let xDomain: ClosedRange<Date>

    init(userHistory: [MetricHistoryPoint], systemHistory: [MetricHistoryPoint]) {
        let sanitizedUserHistory = ChartSeriesPipeline.sanitize(userHistory, timestamp: \.timestamp)
        let sanitizedSystemHistory = ChartSeriesPipeline.sanitize(systemHistory, timestamp: \.timestamp)
        let userKeys = ChartSeriesPipeline.continuityKeys(for: sanitizedUserHistory, seriesKey: "cpu.user", timestamp: \.timestamp)
        let systemKeys = ChartSeriesPipeline.continuityKeys(for: sanitizedSystemHistory, seriesKey: "cpu.system", timestamp: \.timestamp)
        var output: [CPUUsageSeriesPoint] = []
        output.reserveCapacity(userHistory.count + systemHistory.count)
        output.append(contentsOf: zip(sanitizedUserHistory, userKeys).map {
            CPUUsageSeriesPoint(timestamp: $0.0.timestamp, series: .user, continuityKey: $0.1, value: $0.0.value)
        })
        output.append(contentsOf: zip(sanitizedSystemHistory, systemKeys).map {
            CPUUsageSeriesPoint(timestamp: $0.0.timestamp, series: .system, continuityKey: $0.1, value: $0.0.value)
        })
        points = output.sorted { $0.timestamp < $1.timestamp }
        xDomain = Self.makeXDomain(from: points.map(\.timestamp))
    }

    static let empty = PreparedCPUUsageChartModel(userHistory: [], systemHistory: [])

    private static func makeXDomain(from dates: [Date]) -> ClosedRange<Date> {
        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? minDate.addingTimeInterval(1)
        if minDate == maxDate {
            return minDate.addingTimeInterval(-30)...maxDate.addingTimeInterval(30)
        }
        return minDate...maxDate
    }
}

private struct PreparedCPUMetricChartModel {
    let points: [TimeSeriesChartPoint]
    let scale: ChartScale
    let fallbackXDomain: ClosedRange<Date>

    init(series: [ChartMetricSeriesDescriptor<MetricHistoryPoint>], baseline: ChartBaselinePolicy) {
        points = ChartSeriesPipeline.metricHistory(series: series)
        scale = ChartSeriesPipeline.scale(for: points, baseline: baseline)
        fallbackXDomain = Self.makeXDomain(from: points.map(\.timestamp))
    }

    static let empty = PreparedCPUMetricChartModel(series: [], baseline: .zero())

    private static func makeXDomain(from dates: [Date]) -> ClosedRange<Date> {
        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? minDate.addingTimeInterval(1)
        if minDate == maxDate {
            return minDate.addingTimeInterval(-30)...maxDate.addingTimeInterval(30)
        }
        return minDate...maxDate
    }
}
