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
    @State private var hiddenLegendIDs = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: $coordinator.selectedCPUHistoryWindow,
                paneController: paneController,
                style: .detached
            )
            ChartToolsStrip(
                smoothingAlpha: $coordinator.chartSmoothingAlpha,
                showsMinorGrid: $coordinator.chartMinorGridEnabled,
                style: .detached
            )

            paneHeader

            HStack(spacing: 8) {
                if viewport.isZoomed {
                    Button("Reset Zoom") {
                        viewport.reset()
                        zoomSelectionRect = nil
                        hoveredDate = nil
                    }
                    .buttonStyle(.bordered)
                }

                if paneController.pinnedTarget != nil {
                    Button("Unpin") {
                        paneController.unpin()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 10) {
                DashboardSectionLabel(title: activeChart.historyTitle, tint: DashboardPalette.secondaryText)
                chartBody
                    .frame(maxWidth: .infinity, minHeight: 300)
                ChartLegendStrip(items: legendItems, hiddenItemIDs: hiddenLegendIDs) { item in
                    toggleLegend(item.id)
                }
                summaryRow
            }
            .padding(12)
            .dashboardInset(cornerRadius: 16)
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .dashboardSurface(padding: 14, cornerRadius: 18)
        .task(id: refreshTriggerID) {
            if lastRefreshContextID != contextRefreshID {
                hoveredDate = nil
                viewport.reset()
                zoomSelectionRect = nil
                hiddenLegendIDs = []
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

    private var paneHeader: some View {
        DetachedPaneHeaderCard(
            sectionTitle: "CPU Detail",
            title: activeChart.title,
            subtitle: activeChart.subtitle,
            valueText: currentValueText,
            badgeText: paneController.pinnedTarget != nil ? "Pinned" : "Hover Preview",
            accent: DashboardPalette.cpuAccent
        )
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
                    window: coordinator.selectedCPUHistoryWindow,
                    areaOpacity: coordinator.chartAreaOpacity,
                    paneController: paneController,
                    hiddenLegendIDs: hiddenLegendIDs,
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
                    window: coordinator.selectedCPUHistoryWindow,
                    areaOpacity: coordinator.chartAreaOpacity,
                    throughputUnit: coordinator.throughputUnit,
                    paneController: paneController,
                    hiddenLegendIDs: hiddenLegendIDs,
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
                    window: coordinator.selectedCPUHistoryWindow,
                    areaOpacity: coordinator.chartAreaOpacity,
                    throughputUnit: coordinator.throughputUnit,
                    paneController: paneController,
                    hiddenLegendIDs: hiddenLegendIDs,
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
                    window: coordinator.selectedCPUHistoryWindow,
                    areaOpacity: coordinator.chartAreaOpacity,
                    throughputUnit: coordinator.throughputUnit,
                    paneController: paneController,
                    hiddenLegendIDs: hiddenLegendIDs,
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

    private var legendItems: [ChartLegendItem] {
        switch activeChart {
        case .usage:
            return [
                ChartLegendItem(
                    id: "cpu.user",
                    label: "User",
                    color: DashboardPalette.cpuAccent,
                    valueText: nearestPoint(in: userHistory).map { UnitsFormatter.format($0.value, unit: .percent) }
                ),
                ChartLegendItem(
                    id: "cpu.system",
                    label: "System",
                    color: DashboardPalette.memoryAccent,
                    valueText: nearestPoint(in: systemHistory).map { UnitsFormatter.format($0.value, unit: .percent) }
                )
            ]
        case .loadAverage:
            return [
                ChartLegendItem(
                    id: "load.1",
                    label: "1 Minute",
                    color: .cyan,
                    valueText: nearestPoint(in: load1History).map { String(format: "%.2f", $0.value) }
                ),
                ChartLegendItem(
                    id: "load.5",
                    label: "5 Minute",
                    color: .red,
                    valueText: nearestPoint(in: load5History).map { String(format: "%.2f", $0.value) }
                ),
                ChartLegendItem(
                    id: "load.15",
                    label: "15 Minute",
                    color: .gray,
                    valueText: nearestPoint(in: load15History).map { String(format: "%.2f", $0.value) }
                )
            ]
        case .gpu:
            return [
                ChartLegendItem(
                    id: "gpu.processor",
                    label: "Processor",
                    color: .cyan,
                    valueText: nearestPoint(in: gpuProcessorHistory).map { UnitsFormatter.format($0.value, unit: .percent) }
                ),
                ChartLegendItem(
                    id: "gpu.memory",
                    label: "Memory",
                    color: .blue,
                    valueText: nearestPoint(in: gpuMemoryHistory).map { UnitsFormatter.format($0.value, unit: .percent) }
                )
            ]
        case .framesPerSecond:
            return [
                ChartLegendItem(
                    id: "fps",
                    label: "FPS",
                    color: .cyan,
                    valueText: nearestPoint(in: fpsHistory).map { String(format: "%.1f fps", $0.value) }
                )
            ]
        }
    }

    private var currentValueText: String {
        switch activeChart {
        case .usage:
            guard userHistory.last != nil || systemHistory.last != nil else { return "--" }
            let total = (userHistory.last?.value ?? 0) + (systemHistory.last?.value ?? 0)
            return UnitsFormatter.format(total, unit: .percent)
        case .loadAverage:
            guard let load = load1History.last?.value else { return "--" }
            return String(format: "%.2f", load)
        case .gpu:
            guard let processor = gpuProcessorHistory.last?.value else { return "--" }
            return UnitsFormatter.format(processor, unit: .percent)
        case .framesPerSecond:
            guard let fps = fpsHistory.last?.value else { return "--" }
            return String(format: "%.1f fps", fps)
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
                .foregroundStyle(DashboardPalette.secondaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DashboardPalette.secondaryText)
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

            usageChartModel = PreparedCPUUsageChartModel(
                userHistory: userHistory,
                systemHistory: systemHistory,
                smoothingAlpha: coordinator.chartSmoothingAlpha
            )
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
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
                smoothingAlpha: coordinator.chartSmoothingAlpha
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
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
                smoothingAlpha: coordinator.chartSmoothingAlpha
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
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
                smoothingAlpha: coordinator.chartSmoothingAlpha
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

    private func toggleLegend(_ id: String) {
        if hiddenLegendIDs.contains(id) {
            hiddenLegendIDs.remove(id)
        } else {
            hiddenLegendIDs.insert(id)
        }
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

    var historyTitle: String {
        switch self {
        case .usage:
            return "Usage History"
        case .loadAverage:
            return "Load History"
        case .gpu:
            return "GPU History"
        case .framesPerSecond:
            return "Display History"
        }
    }
}

private struct CPUUsagePaneChart: View {
    let model: PreparedCPUUsageChartModel
    let window: ChartWindow
    let areaOpacity: Double
    let paneController: DetachedMetricsPaneController
    let hiddenLegendIDs: Set<String>
    @Environment(\.dashboardChartDisplayOptions) private var displayOptions
    @Binding var hoveredDate: Date?
    @Binding var viewport: ChartViewport
    @Binding var zoomSelectionRect: CGRect?

    var body: some View {
        Chart(visiblePoints) { point in
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
                    .foregroundStyle(DashboardPalette.chartRule)
            }
        }
        .chartXScale(
            domain: viewport.xDomain ?? DashboardChartStyle.visibleXDomain(
                dataDomain: model.xDomain,
                window: window
            )
        )
        .chartYScale(domain: viewport.yDomain ?? (0...100))
        .chartYAxis {
            DashboardChartStyle.leadingNumericAxis(values: [0, 25, 50, 75, 100], showsMinorGrid: displayOptions.showsMinorGrid) { value in
                String(format: "%.0f%%", value)
            }
        }
        .chartXAxis {
            DashboardChartStyle.timeXAxis(showsMinorGrid: displayOptions.showsMinorGrid)
        }
        .chartXScale(range: .plotDimension(startPadding: DashboardChartStyle.xAxisStartPadding, endPadding: DashboardChartStyle.xAxisEndPadding))
        .chartPlotStyle { plot in
            plot
                .background(DashboardPalette.chartPlotBackground(cornerRadius: 14, showsMinorGrid: displayOptions.showsMinorGrid))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .id("minor-grid-\(displayOptions.showsMinorGrid)")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plotFrame = geometry[proxy.plotAreaFrame]

                ZStack(alignment: .topLeading) {
                    DetachedChartInteractionOverlay(
                        proxy: proxy,
                        geometry: geometry,
                        paneController: paneController,
                        zoomMode: .bothAxes,
                        hoveredDate: $hoveredDate,
                        viewport: $viewport,
                        selectionRect: $zoomSelectionRect
                    )

                    ChartZoomSelectionOverlay(
                        selectionRect: zoomSelectionRect,
                        plotFrame: plotFrame,
                        cornerRadius: 14
                    )
                }
            }
        }
        .frame(height: 300)
    }

    private var visiblePoints: [CPUUsageSeriesPoint] {
        model.points.filter { !hiddenLegendIDs.contains("cpu.\($0.series.rawValue)") }
    }
}

private struct MultiSeriesLinePaneChart: View {
    let model: PreparedCPUMetricChartModel
    let window: ChartWindow
    let areaOpacity: Double
    let throughputUnit: ThroughputDisplayUnit
    let paneController: DetachedMetricsPaneController
    let hiddenLegendIDs: Set<String>
    @Environment(\.dashboardChartDisplayOptions) private var displayOptions
    @Binding var hoveredDate: Date?
    @Binding var viewport: ChartViewport
    @Binding var zoomSelectionRect: CGRect?

    var body: some View {
        Chart(visiblePoints) { point in
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
                    .foregroundStyle(DashboardPalette.chartRule)
            }
        }
        .chartXScale(
            domain: viewport.xDomain ?? DashboardChartStyle.visibleXDomain(
                dataDomain: model.scale.xDomain ?? model.fallbackXDomain,
                window: window
            )
        )
        .chartYScale(domain: viewport.yDomain ?? model.scale.yDomain)
        .chartYAxis {
            DashboardChartStyle.leadingNumericAxis(showsMinorGrid: displayOptions.showsMinorGrid) { value in
                DashboardChartStyle.valueLabel(for: value, unit: model.primaryUnit, throughputUnit: throughputUnit)
            }
        }
        .chartXAxis {
            DashboardChartStyle.timeXAxis(showsMinorGrid: displayOptions.showsMinorGrid)
        }
        .chartXScale(range: .plotDimension(startPadding: DashboardChartStyle.xAxisStartPadding, endPadding: DashboardChartStyle.xAxisEndPadding))
        .chartPlotStyle { plot in
            plot
                .background(DashboardPalette.chartPlotBackground(cornerRadius: 14, showsMinorGrid: displayOptions.showsMinorGrid))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .id("minor-grid-\(displayOptions.showsMinorGrid)")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plotFrame = geometry[proxy.plotAreaFrame]

                ZStack(alignment: .topLeading) {
                    DetachedChartInteractionOverlay(
                        proxy: proxy,
                        geometry: geometry,
                        paneController: paneController,
                        zoomMode: .bothAxes,
                        hoveredDate: $hoveredDate,
                        viewport: $viewport,
                        selectionRect: $zoomSelectionRect
                    )

                    ChartZoomSelectionOverlay(
                        selectionRect: zoomSelectionRect,
                        plotFrame: plotFrame,
                        cornerRadius: 14
                    )
                }
            }
        }
        .frame(height: 300)
    }

    private var visiblePoints: [TimeSeriesChartPoint] {
        model.points.filter { !hiddenLegendIDs.contains($0.seriesKey) }
    }
}

private struct CPUUsageSeriesPoint: Identifiable {
    enum Series: String {
        case user
        case system

        var color: Color {
            switch self {
            case .user:
                return DashboardPalette.cpuAccent
            case .system:
                return DashboardPalette.memoryAccent
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

    init(userHistory: [MetricHistoryPoint], systemHistory: [MetricHistoryPoint], smoothingAlpha: Double = 1.0) {
        let sanitizedUserHistory = ChartSeriesPipeline.lowPass(
            ChartSeriesPipeline.sanitize(userHistory, timestamp: \.timestamp),
            alpha: smoothingAlpha
        )
        let sanitizedSystemHistory = ChartSeriesPipeline.lowPass(
            ChartSeriesPipeline.sanitize(systemHistory, timestamp: \.timestamp),
            alpha: smoothingAlpha
        )
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
    let primaryUnit: MetricUnit?

    init(series: [ChartMetricSeriesDescriptor<MetricHistoryPoint>], baseline: ChartBaselinePolicy, smoothingAlpha: Double = 1.0) {
        let smoothedSeries = series.map {
            ChartMetricSeriesDescriptor(
                key: $0.key,
                label: $0.label,
                color: $0.color,
                samples: ChartSeriesPipeline.lowPass($0.samples, alpha: smoothingAlpha)
            )
        }
        points = ChartSeriesPipeline.metricHistory(series: smoothedSeries)
        scale = ChartSeriesPipeline.scale(for: points, baseline: baseline)
        fallbackXDomain = Self.makeXDomain(from: points.map(\.timestamp))
        primaryUnit = smoothedSeries
            .lazy
            .flatMap(\.samples)
            .first?
            .unit
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
