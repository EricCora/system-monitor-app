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
    @State private var viewport = ChartViewport()
    @State private var zoomSelectionRect: CGRect?
    @State private var lastRefreshContextID = ""
    @State private var compositionChartModel: PreparedMemoryCompositionChartModel?
    @State private var pressureChartModel: PreparedMetricLineChartModel?
    @State private var swapChartModel: PreparedMetricLineChartModel?
    @State private var pagesChartModel: PreparedMetricLineChartModel?
    @State private var deferredRefreshTriggerID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: $coordinator.selectedMemoryHistoryWindow,
                paneController: paneController,
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
                ChartLegendStrip(items: legendItems)
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

    private var activeChart: MemoryPaneChart {
        if case .memory(let chart)? = paneController.activeTarget {
            return chart
        }
        return coordinator.selectedMemoryPaneChart
    }

    private var paneHeader: some View {
        DetachedPaneHeaderCard(
            sectionTitle: "Memory Detail",
            title: activeChart.title,
            subtitle: activeChart.subtitle,
            valueText: currentValueText,
            badgeText: paneController.pinnedTarget != nil ? "Pinned" : "Hover Preview",
            accent: DashboardPalette.memoryAccent
        )
    }

    @ViewBuilder
    private var chartBody: some View {
        switch activeChart {
        case .composition:
            if compositionHistory.isEmpty {
                emptyState("Collecting memory history")
            } else {
                MemoryCompositionChart(
                    model: compositionChartModel ?? PreparedMemoryCompositionChartModel.empty,
                    paneController: paneController,
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    zoomSelectionRect: $zoomSelectionRect
                )
            }
        case .pressure:
            if pressureHistory.isEmpty {
                emptyState("Collecting pressure history")
            } else {
                MetricLinePaneChart(
                    model: pressureChartModel ?? PreparedMetricLineChartModel.empty,
                    areaOpacity: coordinator.chartAreaOpacity,
                    throughputUnit: coordinator.throughputUnit,
                    paneController: paneController,
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    zoomSelectionRect: $zoomSelectionRect
                )
            }
        case .swap:
            if swapHistory.isEmpty {
                emptyState("Collecting swap history")
            } else {
                MetricLinePaneChart(
                    model: swapChartModel ?? PreparedMetricLineChartModel.empty,
                    areaOpacity: coordinator.chartAreaOpacity,
                    throughputUnit: coordinator.throughputUnit,
                    paneController: paneController,
                    hoveredDate: $hoveredDate,
                    viewport: $viewport,
                    zoomSelectionRect: $zoomSelectionRect
                )
            }
        case .pages:
            if pageInHistory.isEmpty && pageOutHistory.isEmpty {
                emptyState("Collecting paging history")
            } else {
                MetricLinePaneChart(
                    model: pagesChartModel ?? PreparedMetricLineChartModel.empty,
                    areaOpacity: coordinator.chartAreaOpacity,
                    throughputUnit: coordinator.throughputUnit,
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
            case .composition:
                if let point = nearestCompositionPoint {
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(DashboardPalette.secondaryText)
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

    private var legendItems: [ChartLegendItem] {
        switch activeChart {
        case .composition:
            let point = nearestCompositionPoint
            return [
                ChartLegendItem(
                    id: "memory.wired",
                    label: "Wired",
                    color: MemoryCompositionSeriesPoint.Component.wired.color,
                    valueText: point.map { UnitsFormatter.format($0.wiredBytes, unit: .bytes) }
                ),
                ChartLegendItem(
                    id: "memory.active",
                    label: "Active",
                    color: MemoryCompositionSeriesPoint.Component.active.color,
                    valueText: point.map { UnitsFormatter.format($0.activeBytes, unit: .bytes) }
                ),
                ChartLegendItem(
                    id: "memory.compressed",
                    label: "Compressed",
                    color: MemoryCompositionSeriesPoint.Component.compressed.color,
                    valueText: point.map { UnitsFormatter.format($0.compressedBytes, unit: .bytes) }
                ),
                ChartLegendItem(
                    id: "memory.free",
                    label: "Free",
                    color: MemoryCompositionSeriesPoint.Component.free.color,
                    valueText: point.map { UnitsFormatter.format($0.freeBytes, unit: .bytes) }
                )
            ]
        case .pressure:
            return [
                ChartLegendItem(
                    id: "memory.pressure",
                    label: "Pressure",
                    color: .cyan,
                    valueText: nearestMetricPoint(in: pressureHistory).map { UnitsFormatter.format($0.value, unit: $0.unit, throughputUnit: coordinator.throughputUnit) }
                )
            ]
        case .swap:
            return [
                ChartLegendItem(
                    id: "memory.swap",
                    label: "Swap Used",
                    color: .cyan,
                    valueText: nearestMetricPoint(in: swapHistory).map { UnitsFormatter.format($0.value, unit: $0.unit, throughputUnit: coordinator.throughputUnit) }
                )
            ]
        case .pages:
            return [
                ChartLegendItem(
                    id: "memory.pageIns",
                    label: "Page Ins",
                    color: .cyan,
                    valueText: nearestMetricPoint(in: pageInHistory).map { UnitsFormatter.format($0.value, unit: $0.unit, throughputUnit: coordinator.throughputUnit) }
                ),
                ChartLegendItem(
                    id: "memory.pageOuts",
                    label: "Page Outs",
                    color: .orange,
                    valueText: nearestMetricPoint(in: pageOutHistory).map { UnitsFormatter.format($0.value, unit: $0.unit, throughputUnit: coordinator.throughputUnit) }
                )
            ]
        }
    }

    private var currentValueText: String {
        switch activeChart {
        case .composition:
            guard let point = compositionHistory.last else { return "--" }
            let usedBytes = point.wiredBytes + point.activeBytes + point.compressedBytes
            return UnitsFormatter.format(usedBytes, unit: .bytes)
        case .pressure:
            guard let value = pressureHistory.last?.value else { return "--" }
            return UnitsFormatter.format(value, unit: .percent)
        case .swap:
            guard let value = swapHistory.last?.value else { return "--" }
            return UnitsFormatter.format(value, unit: .bytes)
        case .pages:
            guard pageInHistory.last != nil || pageOutHistory.last != nil else { return "--" }
            let total = (pageInHistory.last?.value ?? 0) + (pageOutHistory.last?.value ?? 0)
            return UnitsFormatter.format(total, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit)
        }
    }

    @ViewBuilder
    private func metricSummary(primary: MetricHistoryPoint?) -> some View {
        if let primary {
            Text(primary.timestamp.formatted(date: .omitted, time: .standard))
                .foregroundStyle(DashboardPalette.secondaryText)
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
                .foregroundStyle(DashboardPalette.secondaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DashboardPalette.secondaryText)
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
        coordinator.performanceDiagnosticsStore.recordDetachedPaneQuery()
        let start = ContinuousClock.now
        let window = coordinator.selectedMemoryHistoryWindow
        let maxPoints = 360

        switch activeChart {
        case .composition:
            compositionHistory = await coordinator.memoryHistorySeries(window: window, maxPoints: maxPoints)
            pressureHistory = []
            swapHistory = []
            pageInHistory = []
            pageOutHistory = []

            compositionChartModel = PreparedMemoryCompositionChartModel(history: compositionHistory)
            pressureChartModel = nil
            swapChartModel = nil
            pagesChartModel = nil

        case .pressure:
            pressureHistory = await coordinator.metricHistorySeries(for: .memoryPressureLevel, window: window, maxPoints: maxPoints)
            compositionHistory = []
            swapHistory = []
            pageInHistory = []
            pageOutHistory = []

            pressureChartModel = PreparedMetricLineChartModel(
                series: [ChartMetricSeriesDescriptor(key: "Series", label: "Series", color: .cyan, samples: pressureHistory)],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12)
            )
            compositionChartModel = nil
            swapChartModel = nil
            pagesChartModel = nil

        case .swap:
            swapHistory = await coordinator.metricHistorySeries(for: .memorySwapUsedBytes, window: window, maxPoints: maxPoints)
            compositionHistory = []
            pressureHistory = []
            pageInHistory = []
            pageOutHistory = []

            swapChartModel = PreparedMetricLineChartModel(
                series: [ChartMetricSeriesDescriptor(key: "Series", label: "Series", color: .cyan, samples: swapHistory)],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12)
            )
            compositionChartModel = nil
            pressureChartModel = nil
            pagesChartModel = nil

        case .pages:
            async let pageIns = coordinator.metricHistorySeries(for: .memoryPageInsBytesPerSec, window: window, maxPoints: maxPoints)
            async let pageOuts = coordinator.metricHistorySeries(for: .memoryPageOutsBytesPerSec, window: window, maxPoints: maxPoints)

            pageInHistory = await pageIns
            pageOutHistory = await pageOuts
            compositionHistory = []
            pressureHistory = []
            swapHistory = []

            pagesChartModel = PreparedMetricLineChartModel(
                series: [
                    ChartMetricSeriesDescriptor(key: "Page Ins", label: "Page Ins", color: .cyan, samples: pageInHistory),
                    ChartMetricSeriesDescriptor(key: "Page Outs", label: "Page Outs", color: .orange, samples: pageOutHistory)
                ],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12)
            )
            compositionChartModel = nil
            pressureChartModel = nil
            swapChartModel = nil
        }
        let elapsed = start.duration(to: ContinuousClock.now)
        coordinator.performanceDiagnosticsStore.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }

    private var contextRefreshID: String {
        "\(activeChart.rawValue)-\(coordinator.selectedMemoryHistoryWindow.rawValue)"
    }

    private var historyRefreshID: String {
        "\(contextRefreshID)-\(coordinator.metricHistoryRevision)-\(coordinator.memoryHistoryRevision)"
    }

    private var refreshTriggerID: String {
        historyRefreshID
    }

    private var isInteractionActive: Bool {
        hoveredDate != nil || zoomSelectionRect != nil
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

    var historyTitle: String {
        switch self {
        case .pressure:
            return "Pressure History"
        case .composition:
            return "Composition History"
        case .swap:
            return "Swap History"
        case .pages:
            return "Paging History"
        }
    }
}

private struct MemoryCompositionChart: View {
    let model: PreparedMemoryCompositionChartModel
    let paneController: DetachedMetricsPaneController
    @Binding var hoveredDate: Date?
    @Binding var viewport: ChartViewport
    @Binding var zoomSelectionRect: CGRect?

    var body: some View {
        Chart(model.points) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Percent", point.percent),
                series: .value("Segment", point.continuityKey),
                stacking: .standard
            )
            .foregroundStyle(point.component.color)
            .interpolationMethod(.linear)

            if let hoveredDate {
                RuleMark(x: .value("Hover", hoveredDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(DashboardPalette.chartRule)
            }
        }
        .chartXScale(domain: viewport.xDomain ?? model.xDomain)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            DashboardChartStyle.leadingNumericAxis(values: [0, 25, 50, 75, 100]) { percent in
                String(format: "%.0f%%", percent)
            }
        }
        .chartXAxis {
            DashboardChartStyle.timeXAxis()
        }
        .chartPlotStyle { plot in
            plot
                .background(DashboardPalette.chartPlotBackground(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plotFrame = geometry[proxy.plotAreaFrame]

                ZStack(alignment: .topLeading) {
                    DetachedChartInteractionOverlay(
                        proxy: proxy,
                        geometry: geometry,
                        paneController: paneController,
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
}

private struct MetricLinePaneChart: View {
    let model: PreparedMetricLineChartModel
    let areaOpacity: Double
    let throughputUnit: ThroughputDisplayUnit
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
                    .foregroundStyle(DashboardPalette.chartRule)
            }
        }
        .chartXScale(domain: viewport.xDomain ?? model.scale.xDomain ?? model.fallbackXDomain)
        .chartYScale(domain: viewport.yDomain ?? model.scale.yDomain)
        .chartYAxis {
            DashboardChartStyle.leadingNumericAxis { value in
                DashboardChartStyle.valueLabel(for: value, unit: model.primaryUnit, throughputUnit: throughputUnit)
            }
        }
        .chartXAxis {
            DashboardChartStyle.timeXAxis()
        }
        .chartPlotStyle { plot in
            plot
                .background(DashboardPalette.chartPlotBackground(cornerRadius: 14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plotFrame = geometry[proxy.plotAreaFrame]

                ZStack(alignment: .topLeading) {
                    DetachedChartInteractionOverlay(
                        proxy: proxy,
                        geometry: geometry,
                        paneController: paneController,
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
}

private struct MemoryCompositionSeriesPoint: Identifiable {
    enum Component: String {
        case wired
        case active
        case compressed
        case free

        var color: Color {
            switch self {
            case .wired:
                return DashboardPalette.networkAccent
            case .active:
                return DashboardPalette.memoryAccent
            case .compressed:
                return DashboardPalette.temperatureAccent
            case .free:
                return DashboardPalette.tertiaryText.opacity(0.7)
            }
        }
    }

    let timestamp: Date
    let component: Component
    let continuityKey: String
    let percent: Double

    var id: String { "\(continuityKey)-\(timestamp.timeIntervalSince1970)" }
}

private struct PreparedMemoryCompositionChartModel {
    let points: [MemoryCompositionSeriesPoint]
    let xDomain: ClosedRange<Date>

    init(history: [MemoryHistoryPoint]) {
        let sanitizedHistory = ChartSeriesPipeline.sanitize(history, timestamp: \.timestamp)
        let continuityKeys = ChartSeriesPipeline.continuityKeys(for: sanitizedHistory, seriesKey: "memory.composition", timestamp: \.timestamp)
        points = zip(sanitizedHistory, continuityKeys).flatMap { point, continuityKey in
            let total = max(1, point.totalBytes)
            return [
                MemoryCompositionSeriesPoint(timestamp: point.timestamp, component: .wired, continuityKey: "\(continuityKey).wired", percent: min(max((point.wiredBytes / total) * 100, 0), 100)),
                MemoryCompositionSeriesPoint(timestamp: point.timestamp, component: .active, continuityKey: "\(continuityKey).active", percent: min(max((point.activeBytes / total) * 100, 0), 100)),
                MemoryCompositionSeriesPoint(timestamp: point.timestamp, component: .compressed, continuityKey: "\(continuityKey).compressed", percent: min(max((point.compressedBytes / total) * 100, 0), 100)),
                MemoryCompositionSeriesPoint(timestamp: point.timestamp, component: .free, continuityKey: "\(continuityKey).free", percent: min(max((point.freeBytes / total) * 100, 0), 100))
            ]
        }
        xDomain = Self.makeXDomain(from: points.map(\.timestamp))
    }

    static let empty = PreparedMemoryCompositionChartModel(history: [])

    private static func makeXDomain(from dates: [Date]) -> ClosedRange<Date> {
        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? minDate.addingTimeInterval(1)
        if minDate == maxDate {
            return minDate.addingTimeInterval(-30)...maxDate.addingTimeInterval(30)
        }
        return minDate...maxDate
    }
}

private struct PreparedMetricLineChartModel {
    let points: [TimeSeriesChartPoint]
    let scale: ChartScale
    let fallbackXDomain: ClosedRange<Date>
    let primaryUnit: MetricUnit?

    init(series: [ChartMetricSeriesDescriptor<MetricHistoryPoint>], baseline: ChartBaselinePolicy) {
        points = ChartSeriesPipeline.metricHistory(series: series.filter { !$0.label.isEmpty })
        scale = ChartSeriesPipeline.scale(for: points, baseline: baseline)
        fallbackXDomain = Self.makeXDomain(from: points.map(\.timestamp))
        primaryUnit = series
            .lazy
            .flatMap(\.samples)
            .first?
            .unit
    }

    static let empty = PreparedMetricLineChartModel(series: [], baseline: .zero())

    private static func makeXDomain(from dates: [Date]) -> ClosedRange<Date> {
        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? minDate.addingTimeInterval(1)
        if minDate == maxDate {
            return minDate.addingTimeInterval(-30)...maxDate.addingTimeInterval(30)
        }
        return minDate...maxDate
    }
}
