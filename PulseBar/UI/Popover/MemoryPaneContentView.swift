import SwiftUI
import PulseBarCore

struct MemoryPaneContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var historySnapshot: MemoryHistorySnapshot?
    @State private var hoveredDate: Date?
    @State private var viewport = ChartViewport()
    @State private var zoomSelectionRect: CGRect?
    @State private var chartModel = PreparedTimeSeriesChartModel.empty
    @State private var hiddenLegendIDs = Set<String>()

    var body: some View {
        DetachedMetricsPaneShell(
            coordinator: coordinator,
            paneController: paneController,
            historyWindow: $coordinator.selectedMemoryHistoryWindow,
            hoveredDate: $hoveredDate,
            viewport: $viewport,
            zoomSelectionRect: $zoomSelectionRect,
            sectionAccent: DashboardPalette.memoryChartAccent,
            header: { paneHeader },
            chart: { chartSection },
            footer: {
                ChartLegendStrip(items: legendItems, hiddenItemIDs: hiddenLegendIDs) { item in
                    ChartInteractionSupport.toggleLegendItem(item.id, hiddenLegendIDs: &hiddenLegendIDs)
                }
                summaryRow
            }
        )
        .detachedPaneHistoryRefresh(
            contextRefreshID: contextRefreshID,
            refreshTriggerID: refreshTriggerID,
            isInteractionActive: isInteractionActive,
            onContextChange: {
                hoveredDate = nil
                viewport.reset()
                zoomSelectionRect = nil
                hiddenLegendIDs = []
            },
            refresh: { await refresh() }
        )
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
            accent: DashboardPalette.memoryChartAccent
        )
    }

    private var chartSection: some View {
        DetachedPaneChartSection(
            historyTitle: activeChart.historyTitle,
            emptyMessage: emptyStateMessage,
            model: chartModel,
            window: coordinator.selectedMemoryHistoryWindow,
            throughputUnit: coordinator.throughputUnit,
            paneController: paneController,
            hiddenLegendIDs: hiddenLegendIDs,
            hoveredDate: $hoveredDate,
            viewport: $viewport,
            zoomSelectionRect: $zoomSelectionRect
        )
    }

    private var emptyStateMessage: String {
        switch activeChart {
        case .composition: return "Collecting memory history"
        case .pressure: return "Collecting pressure history"
        case .swap: return "Collecting swap history"
        case .pages: return "Collecting paging history"
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
                    DetachedPaneSummaryRow.placeholder()
                }
            case .pressure:
                metricSummary(primary: ChartInteractionSupport.nearestPoint(in: historySnapshot?.pressure ?? [], hoveredDate: hoveredDate))
            case .swap:
                metricSummary(primary: ChartInteractionSupport.nearestPoint(in: historySnapshot?.swap ?? [], hoveredDate: hoveredDate))
            case .pages:
                if let point = ChartInteractionSupport.nearestPoint(in: historySnapshot?.pageIns ?? [], hoveredDate: hoveredDate)
                    ?? ChartInteractionSupport.nearestPoint(in: historySnapshot?.pageOuts ?? [], hoveredDate: hoveredDate) {
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Spacer()
                    Text(
                        "In \(UnitsFormatter.format(ChartInteractionSupport.nearestPoint(in: historySnapshot?.pageIns ?? [], hoveredDate: hoveredDate)?.value ?? 0, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))  Out \(UnitsFormatter.format(ChartInteractionSupport.nearestPoint(in: historySnapshot?.pageOuts ?? [], hoveredDate: hoveredDate)?.value ?? 0, unit: .bytesPerSecond, throughputUnit: coordinator.throughputUnit))"
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    DetachedPaneSummaryRow.placeholder()
                }
            }
        }
        .font(.caption)
        .frame(height: 18)
    }

    private var legendItems: [ChartLegendItem] {
        guard let snapshot = historySnapshot else { return [] }
        switch activeChart {
        case .composition:
            let point = nearestCompositionPoint
            return [
                ChartLegendItem(id: "memory.wired", label: "Wired", color: DashboardPalette.networkChartAccent, valueText: point.map { UnitsFormatter.format($0.wiredBytes, unit: .bytes) }),
                ChartLegendItem(id: "memory.active", label: "Active", color: DashboardPalette.memoryChartAccent, valueText: point.map { UnitsFormatter.format($0.activeBytes, unit: .bytes) }),
                ChartLegendItem(id: "memory.compressed", label: "Compressed", color: DashboardPalette.temperatureChartAccent, valueText: point.map { UnitsFormatter.format($0.compressedBytes, unit: .bytes) }),
                ChartLegendItem(id: "memory.free", label: "Free", color: DashboardPalette.tertiaryText.opacity(0.7), valueText: point.map { UnitsFormatter.format($0.freeBytes, unit: .bytes) })
            ]
        case .pressure:
            return [
                ChartLegendItem(id: "memory.pressure", label: "Pressure", color: DashboardPalette.networkChartAccent, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.pressure, hoveredDate: hoveredDate).map { UnitsFormatter.format($0.value, unit: $0.unit, throughputUnit: coordinator.throughputUnit) })
            ]
        case .swap:
            return [
                ChartLegendItem(id: "memory.swap", label: "Swap Used", color: DashboardPalette.networkChartAccent, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.swap, hoveredDate: hoveredDate).map { UnitsFormatter.format($0.value, unit: $0.unit, throughputUnit: coordinator.throughputUnit) })
            ]
        case .pages:
            return [
                ChartLegendItem(id: "memory.pageIns", label: "Page Ins", color: DashboardPalette.networkChartAccent, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.pageIns, hoveredDate: hoveredDate).map { UnitsFormatter.format($0.value, unit: $0.unit, throughputUnit: coordinator.throughputUnit) }),
                ChartLegendItem(id: "memory.pageOuts", label: "Page Outs", color: DashboardPalette.diskChartAccent, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.pageOuts, hoveredDate: hoveredDate).map { UnitsFormatter.format($0.value, unit: $0.unit, throughputUnit: coordinator.throughputUnit) })
            ]
        }
    }

    private var currentValueText: String {
        guard let snapshot = historySnapshot else { return "--" }
        switch activeChart {
        case .composition:
            guard let point = snapshot.composition.last else { return "--" }
            let usedBytes = point.wiredBytes + point.activeBytes + point.compressedBytes
            return UnitsFormatter.format(usedBytes, unit: .bytes)
        case .pressure:
            guard let value = snapshot.pressure.last?.value else { return "--" }
            return UnitsFormatter.format(value, unit: .percent)
        case .swap:
            guard let value = snapshot.swap.last?.value else { return "--" }
            return UnitsFormatter.format(value, unit: .bytes)
        case .pages:
            let total = (snapshot.pageIns.last?.value ?? 0) + (snapshot.pageOuts.last?.value ?? 0)
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
            DetachedPaneSummaryRow.placeholder()
        }
    }

    private var nearestCompositionPoint: MemoryHistoryPoint? {
        guard let snapshot = historySnapshot else { return nil }
        return ChartInteractionSupport.nearestPoint(in: snapshot.composition, hoveredDate: hoveredDate)
    }

    private func refresh() async {
        coordinator.performanceDiagnosticsStore.recordDetachedPaneQuery()
        let start = ContinuousClock.now
        let window = coordinator.selectedMemoryHistoryWindow
        let maxPoints = DetachedPaneLayout.detachedHistoryMaxPoints(window: window)
        let snapshot = await coordinator.memoryHistorySnapshot(window: window, maxPoints: maxPoints)
        historySnapshot = snapshot
        chartModel = PreparedTimeSeriesChartModel.fromMemory(
            snapshot: snapshot,
            chart: activeChart,
            smoothingAlpha: coordinator.chartSmoothingAlpha
        )

        let elapsed = start.duration(to: ContinuousClock.now)
        coordinator.performanceDiagnosticsStore.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }

    private var contextRefreshID: String {
        "\(activeChart.rawValue)-\(coordinator.selectedMemoryHistoryWindow.rawValue)"
    }

    private var refreshTriggerID: String {
        "\(contextRefreshID)-\(coordinator.metricHistoryRevision)-\(coordinator.memoryHistoryRevision)"
    }

    private var isInteractionActive: Bool {
        ChartInteractionSupport.isChartInteractionActive(hoveredDate: hoveredDate, zoomSelectionRect: zoomSelectionRect)
    }
}

private extension MemoryPaneChart {
    var title: String {
        switch self {
        case .pressure: return "Pressure"
        case .composition: return "Memory"
        case .swap: return "Swap Memory"
        case .pages: return "Pages"
        }
    }

    var subtitle: String {
        switch self {
        case .pressure: return "Memory pressure over time"
        case .composition: return "Wired, active, compressed, and free memory"
        case .swap: return "Swap used over time"
        case .pages: return "Page-ins and page-outs throughput"
        }
    }

    var historyTitle: String {
        switch self {
        case .pressure: return "Pressure History"
        case .composition: return "Composition History"
        case .swap: return "Swap History"
        case .pages: return "Paging History"
        }
    }
}
