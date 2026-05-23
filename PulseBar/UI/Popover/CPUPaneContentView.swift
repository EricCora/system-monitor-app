import SwiftUI
import PulseBarCore

struct CPUPaneContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var historySnapshot: CPUHistorySnapshot?
    @State private var hoveredDate: Date?
    @State private var viewport = ChartViewport()
    @State private var zoomSelectionRect: CGRect?
    @State private var chartModel = PreparedTimeSeriesChartModel.empty
    @State private var hiddenLegendIDs = Set<String>()

    var body: some View {
        DetachedMetricsPaneShell(
            coordinator: coordinator,
            paneController: paneController,
            historyWindow: $coordinator.selectedCPUHistoryWindow,
            hoveredDate: $hoveredDate,
            viewport: $viewport,
            zoomSelectionRect: $zoomSelectionRect,
            sectionAccent: DashboardPalette.cpuChartAccent,
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
            accent: DashboardPalette.cpuChartAccent
        )
    }

    @ViewBuilder
    private var chartSection: some View {
        DashboardSectionLabel(title: activeChart.historyTitle, tint: DashboardPalette.secondaryText)

        if chartModel.isEmpty {
            DetachedPaneEmptyChartState(message: emptyStateMessage)
        } else {
            DashboardTimeSeriesChart(
                model: chartModel,
                window: coordinator.selectedCPUHistoryWindow,
                height: DetachedPaneLayout.standardPane.chartHeight,
                paneController: paneController,
                hiddenLegendIDs: hiddenLegendIDs,
                hoveredDate: $hoveredDate,
                viewport: $viewport,
                zoomSelectionRect: $zoomSelectionRect
            )
        }
    }

    private var emptyStateMessage: String {
        switch activeChart {
        case .usage: return "Collecting CPU history"
        case .loadAverage: return "Collecting load average history"
        case .gpu: return coordinator.latestGPUSummary?.statusMessage ?? "GPU telemetry unavailable"
        case .framesPerSecond: return "Collecting frames-per-second history"
        }
    }

    private var summaryRow: some View {
        HStack {
            switch activeChart {
            case .usage:
                if let snapshot = historySnapshot,
                   let point = ChartInteractionSupport.nearestPoint(in: snapshot.user, hoveredDate: hoveredDate)
                       ?? ChartInteractionSupport.nearestPoint(in: snapshot.system, hoveredDate: hoveredDate) {
                    let user = ChartInteractionSupport.nearestPoint(in: snapshot.user, hoveredDate: hoveredDate)?.value ?? 0
                    let system = ChartInteractionSupport.nearestPoint(in: snapshot.system, hoveredDate: hoveredDate)?.value ?? 0
                    let idle = ChartInteractionSupport.nearestPoint(in: snapshot.idle, hoveredDate: hoveredDate)?.value ?? max(0, 100 - user - system)
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
                if let snapshot = historySnapshot,
                   let point = ChartInteractionSupport.nearestPoint(in: snapshot.load1, hoveredDate: hoveredDate)
                       ?? ChartInteractionSupport.nearestPoint(in: snapshot.load5, hoveredDate: hoveredDate) {
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Spacer()
                    Text(
                        String(
                            format: "1m %.2f  5m %.2f  15m %.2f",
                            ChartInteractionSupport.nearestPoint(in: snapshot.load1, hoveredDate: hoveredDate)?.value ?? 0,
                            ChartInteractionSupport.nearestPoint(in: snapshot.load5, hoveredDate: hoveredDate)?.value ?? 0,
                            ChartInteractionSupport.nearestPoint(in: snapshot.load15, hoveredDate: hoveredDate)?.value ?? 0
                        )
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    emptySummary
                }
            case .gpu:
                if let snapshot = historySnapshot,
                   let point = ChartInteractionSupport.nearestPoint(in: snapshot.gpuProcessor, hoveredDate: hoveredDate)
                       ?? ChartInteractionSupport.nearestPoint(in: snapshot.gpuMemory, hoveredDate: hoveredDate) {
                    Text(point.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Spacer()
                    Text(
                        "Processor \(UnitsFormatter.format(ChartInteractionSupport.nearestPoint(in: snapshot.gpuProcessor, hoveredDate: hoveredDate)?.value ?? 0, unit: .percent))  Memory \(UnitsFormatter.format(ChartInteractionSupport.nearestPoint(in: snapshot.gpuMemory, hoveredDate: hoveredDate)?.value ?? 0, unit: .percent))"
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    emptySummary
                }
            case .framesPerSecond:
                if let snapshot = historySnapshot,
                   let point = ChartInteractionSupport.nearestPoint(in: snapshot.framesPerSecond, hoveredDate: hoveredDate) {
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
        guard let snapshot = historySnapshot else { return [] }
        switch activeChart {
        case .usage:
            return [
                ChartLegendItem(
                    id: "cpu.user",
                    label: "User",
                    color: DashboardPalette.cpuUserAccent,
                    valueText: ChartInteractionSupport.nearestPoint(in: snapshot.user, hoveredDate: hoveredDate).map { UnitsFormatter.format($0.value, unit: .percent) }
                ),
                ChartLegendItem(
                    id: "cpu.system",
                    label: "System",
                    color: DashboardPalette.cpuSystemAccent,
                    valueText: ChartInteractionSupport.nearestPoint(in: snapshot.system, hoveredDate: hoveredDate).map { UnitsFormatter.format($0.value, unit: .percent) }
                )
            ]
        case .loadAverage:
            return [
                ChartLegendItem(id: "load.1", label: "1 Minute", color: DashboardPalette.cpuUserAccent, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.load1, hoveredDate: hoveredDate).map { String(format: "%.2f", $0.value) }),
                ChartLegendItem(id: "load.5", label: "5 Minute", color: DashboardPalette.cpuSystemAccent, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.load5, hoveredDate: hoveredDate).map { String(format: "%.2f", $0.value) }),
                ChartLegendItem(id: "load.15", label: "15 Minute", color: DashboardPalette.tertiaryText, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.load15, hoveredDate: hoveredDate).map { String(format: "%.2f", $0.value) })
            ]
        case .gpu:
            return [
                ChartLegendItem(id: "gpu.processor", label: "Processor", color: DashboardPalette.cpuUserAccent, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.gpuProcessor, hoveredDate: hoveredDate).map { UnitsFormatter.format($0.value, unit: .percent) }),
                ChartLegendItem(id: "gpu.memory", label: "Memory", color: DashboardPalette.networkChartAccent, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.gpuMemory, hoveredDate: hoveredDate).map { UnitsFormatter.format($0.value, unit: .percent) })
            ]
        case .framesPerSecond:
            return [
                ChartLegendItem(id: "fps", label: "FPS", color: DashboardPalette.networkChartAccent, valueText: ChartInteractionSupport.nearestPoint(in: snapshot.framesPerSecond, hoveredDate: hoveredDate).map { String(format: "%.1f fps", $0.value) })
            ]
        }
    }

    private var currentValueText: String {
        guard let snapshot = historySnapshot else { return "--" }
        switch activeChart {
        case .usage:
            let total = (snapshot.user.last?.value ?? 0) + (snapshot.system.last?.value ?? 0)
            return UnitsFormatter.format(total, unit: .percent)
        case .loadAverage:
            guard let load = snapshot.load1.last?.value else { return "--" }
            return String(format: "%.2f", load)
        case .gpu:
            guard let processor = snapshot.gpuProcessor.last?.value else { return "--" }
            return UnitsFormatter.format(processor, unit: .percent)
        case .framesPerSecond:
            guard let fps = snapshot.framesPerSecond.last?.value else { return "--" }
            return String(format: "%.1f fps", fps)
        }
    }

    @ViewBuilder
    private var emptySummary: some View {
        Text(" ")
        Spacer()
        Text(" ")
    }

    private func refresh() async {
        coordinator.performanceDiagnosticsStore.recordDetachedPaneQuery()
        let start = ContinuousClock.now
        let window = coordinator.selectedCPUHistoryWindow
        let snapshot = await coordinator.cpuHistorySnapshot(window: window, maxPoints: 360)
        historySnapshot = snapshot

        chartModel = PreparedTimeSeriesChartModel.fromCPU(
            snapshot: snapshot,
            chart: activeChart,
            smoothingAlpha: coordinator.chartSmoothingAlpha
        )

        let elapsed = start.duration(to: ContinuousClock.now)
        coordinator.performanceDiagnosticsStore.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }

    private var contextRefreshID: String {
        "\(activeChart.rawValue)-\(coordinator.selectedCPUHistoryWindow.rawValue)"
    }

    private var refreshTriggerID: String {
        "\(contextRefreshID)-\(coordinator.metricHistoryRevision)"
    }

    private var isInteractionActive: Bool {
        ChartInteractionSupport.isChartInteractionActive(hoveredDate: hoveredDate, zoomSelectionRect: zoomSelectionRect)
    }
}

private extension CPUPaneChart {
    var title: String {
        switch self {
        case .usage: return "CPU"
        case .loadAverage: return "Load Average"
        case .gpu: return "Apple Silicon"
        case .framesPerSecond: return "Frames Per Second"
        }
    }

    var subtitle: String {
        switch self {
        case .usage: return "User and system CPU usage"
        case .loadAverage: return "1, 5, and 15 minute load averages"
        case .gpu: return "GPU processor and memory history"
        case .framesPerSecond: return "Display refresh sampling"
        }
    }

    var historyTitle: String {
        switch self {
        case .usage: return "Usage History"
        case .loadAverage: return "Load History"
        case .gpu: return "GPU History"
        case .framesPerSecond: return "Display History"
        }
    }
}
