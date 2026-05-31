import SwiftUI
import PulseBarCore

struct CPUPaneContentView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @State private var hoveredDate: Date?
    @State private var viewport = ChartViewport()
    @State private var zoomSelectionRect: CGRect?
    @State private var chartModel = PreparedTimeSeriesChartModel.empty
    @State private var hiddenLegendIDs = Set<String>()

    var body: some View {
        let hoverReadout = ChartInteractionSupport.preparedReadout(
            in: chartModel.points,
            hoveredDate: hoveredDate
        )
        let latestReadout = ChartInteractionSupport.preparedReadout(
            in: chartModel.points,
            hoveredDate: nil
        )

        DetachedMetricsPaneShell(
            coordinator: coordinator,
            paneController: paneController,
            historyWindow: $coordinator.selectedCPUHistoryWindow,
            hoveredDate: $hoveredDate,
            viewport: $viewport,
            zoomSelectionRect: $zoomSelectionRect,
            sectionAccent: DashboardPalette.cpuChartAccent,
            header: { paneHeader(valueReadout: latestReadout) },
            chart: { chartSection },
            footer: {
                ChartLegendStrip(items: legendItems(readout: hoverReadout), hiddenItemIDs: hiddenLegendIDs) { item in
                    ChartInteractionSupport.toggleLegendItem(item.id, hiddenLegendIDs: &hiddenLegendIDs)
                }
                summaryRow(readout: hoverReadout)
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

    private func paneHeader(valueReadout: PreparedChartReadout?) -> some View {
        DetachedPaneHeaderCard(
            sectionTitle: "CPU Detail",
            title: activeChart.title,
            subtitle: activeChart.subtitle,
            valueText: currentValueText(readout: valueReadout),
            badgeText: paneController.pinnedTarget != nil ? "Pinned" : "Hover Preview",
            accent: DashboardPalette.cpuChartAccent
        )
    }

    private var chartSection: some View {
        DetachedPaneChartSection(
            historyTitle: activeChart.historyTitle,
            emptyMessage: emptyStateMessage,
            model: chartModel,
            window: coordinator.selectedCPUHistoryWindow,
            paneController: paneController,
            hiddenLegendIDs: hiddenLegendIDs,
            hoveredDate: $hoveredDate,
            viewport: $viewport,
            zoomSelectionRect: $zoomSelectionRect
        )
    }

    private var emptyStateMessage: String {
        switch activeChart {
        case .usage: return "Collecting CPU history"
        case .loadAverage: return "Collecting load average history"
        case .gpu: return coordinator.latestGPUSummary?.statusMessage ?? "GPU telemetry unavailable"
        case .framesPerSecond: return "Collecting frames-per-second history"
        }
    }

    private func summaryRow(readout: PreparedChartReadout?) -> some View {
        HStack {
            switch activeChart {
            case .usage:
                if let readout,
                   let user = readout.value(forSeriesKey: "cpu.user"),
                   let system = readout.value(forSeriesKey: "cpu.system") {
                    let idle = max(0, 100 - user - system)
                    Text(readout.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Spacer()
                    Text(
                        "User \(UnitsFormatter.format(user, unit: .percent))  System \(UnitsFormatter.format(system, unit: .percent))  Idle \(UnitsFormatter.format(idle, unit: .percent))"
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    DetachedPaneSummaryRow.placeholder()
                }
            case .loadAverage:
                if let readout,
                   let load1 = readout.value(forSeriesKey: "load.1"),
                   let load5 = readout.value(forSeriesKey: "load.5"),
                   let load15 = readout.value(forSeriesKey: "load.15") {
                    Text(readout.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Spacer()
                    Text(String(format: "1m %.2f  5m %.2f  15m %.2f", load1, load5, load15))
                    .font(.caption.monospacedDigit())
                } else {
                    DetachedPaneSummaryRow.placeholder()
                }
            case .gpu:
                if let readout,
                   let processor = readout.value(forSeriesKey: "gpu.processor"),
                   let memory = readout.value(forSeriesKey: "gpu.memory") {
                    Text(readout.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Spacer()
                    Text(
                        "Processor \(UnitsFormatter.format(processor, unit: .percent))  Memory \(UnitsFormatter.format(memory, unit: .percent))"
                    )
                    .font(.caption.monospacedDigit())
                } else {
                    DetachedPaneSummaryRow.placeholder()
                }
            case .framesPerSecond:
                if let readout,
                   let fps = readout.value(forSeriesKey: "fps") {
                    Text(readout.timestamp.formatted(date: .omitted, time: .standard))
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Spacer()
                    Text(String(format: "%.1f fps", fps))
                        .font(.caption.monospacedDigit())
                } else {
                    DetachedPaneSummaryRow.placeholder()
                }
            }
        }
        .font(.caption)
        .frame(height: 18)
    }

    private func legendItems(readout: PreparedChartReadout?) -> [ChartLegendItem] {
        guard let readout else { return [] }
        switch activeChart {
        case .usage:
            return [
                ChartLegendItem(
                    id: "cpu.user",
                    label: "User",
                    color: DashboardPalette.cpuUserAccent,
                    valueText: readout.value(forSeriesKey: "cpu.user").map { UnitsFormatter.format($0, unit: .percent) }
                ),
                ChartLegendItem(
                    id: "cpu.system",
                    label: "System",
                    color: DashboardPalette.cpuSystemAccent,
                    valueText: readout.value(forSeriesKey: "cpu.system").map { UnitsFormatter.format($0, unit: .percent) }
                )
            ]
        case .loadAverage:
            return [
                ChartLegendItem(id: "load.1", label: "1 Minute", color: DashboardPalette.cpuUserAccent, valueText: readout.value(forSeriesKey: "load.1").map { String(format: "%.2f", $0) }),
                ChartLegendItem(id: "load.5", label: "5 Minute", color: DashboardPalette.cpuSystemAccent, valueText: readout.value(forSeriesKey: "load.5").map { String(format: "%.2f", $0) }),
                ChartLegendItem(id: "load.15", label: "15 Minute", color: DashboardPalette.tertiaryText, valueText: readout.value(forSeriesKey: "load.15").map { String(format: "%.2f", $0) })
            ]
        case .gpu:
            return [
                ChartLegendItem(id: "gpu.processor", label: "Processor", color: DashboardPalette.cpuUserAccent, valueText: readout.value(forSeriesKey: "gpu.processor").map { UnitsFormatter.format($0, unit: .percent) }),
                ChartLegendItem(id: "gpu.memory", label: "Memory", color: DashboardPalette.networkChartAccent, valueText: readout.value(forSeriesKey: "gpu.memory").map { UnitsFormatter.format($0, unit: .percent) })
            ]
        case .framesPerSecond:
            return [
                ChartLegendItem(id: "fps", label: "FPS", color: DashboardPalette.networkChartAccent, valueText: readout.value(forSeriesKey: "fps").map { String(format: "%.1f fps", $0) })
            ]
        }
    }

    private func currentValueText(readout: PreparedChartReadout?) -> String {
        guard let readout else { return "--" }
        switch activeChart {
        case .usage:
            let user = readout.value(forSeriesKey: "cpu.user") ?? 0
            let system = readout.value(forSeriesKey: "cpu.system") ?? 0
            return UnitsFormatter.format(user + system, unit: .percent)
        case .loadAverage:
            guard let load = readout.value(forSeriesKey: "load.1") else { return "--" }
            return String(format: "%.2f", load)
        case .gpu:
            guard let processor = readout.value(forSeriesKey: "gpu.processor") else { return "--" }
            return UnitsFormatter.format(processor, unit: .percent)
        case .framesPerSecond:
            guard let fps = readout.value(forSeriesKey: "fps") else { return "--" }
            return String(format: "%.1f fps", fps)
        }
    }

    private func refresh() async {
        coordinator.performanceDiagnosticsStore.recordDetachedPaneQuery()
        let start = ContinuousClock.now
        let window = coordinator.selectedCPUHistoryWindow
        let maxPoints = DetachedPaneLayout.detachedHistoryMaxPoints(window: window)
        let snapshot = await coordinator.cpuHistorySnapshot(window: window, maxPoints: maxPoints)
        chartModel = PreparedTimeSeriesChartModel.fromCPU(
            snapshot: snapshot,
            chart: activeChart,
            window: window,
            smoothingAlpha: coordinator.chartSmoothingAlpha
        )

        let elapsed = start.duration(to: ContinuousClock.now)
        coordinator.performanceDiagnosticsStore.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }

    private var contextRefreshID: String {
        "\(activeChart.rawValue)-\(coordinator.selectedCPUHistoryWindow.rawValue)"
    }

    private var refreshTriggerID: String {
        "\(contextRefreshID)-\(coordinator.metricHistoryRevision)-\(coordinator.chartSmoothingAlpha)"
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
