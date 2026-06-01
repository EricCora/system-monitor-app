import SwiftUI
import PulseBarCore

struct MemoryTabView: View {
    let coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController
    @ObservedObject var featureStore: MemoryFeatureStore
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTabMetrics.sectionSpacing) {
            ChartTabToolbar(
                coordinator: coordinator,
                historyWindow: Binding(
                    get: { coordinator.selectedMemoryHistoryWindow },
                    set: { coordinator.selectedMemoryHistoryWindow = $0 }
                )
            )

            ForEach(coordinator.memoryMenuLayout.visibleSections, id: \.self) { section in
                switch section {
                case .pressure:
                    hoverableSection(chart: .pressure) {
                        pressureSection
                    }
                case .memory:
                    hoverableSection(chart: .composition) {
                        memorySection
                    }
                case .processes:
                    processesSection
                case .swapMemory:
                    hoverableSection(chart: .swap) {
                        swapSection
                    }
                case .pages:
                    hoverableSection(chart: .pages) {
                        pagesSection
                    }
                }
            }

            if let processStatus = featureStore.processesStatusMessage {
                Text(processStatus)
                    .font(.caption2)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            if let historyStatus = coordinator.historyStoreStatusMessage ?? coordinator.memoryHistoryStoreStatusMessage {
                Text(historyStatus)
                    .font(.caption2)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverWindowAccessor { window in
                if hostWindow !== window {
                    hostWindow = window
                }
            }
        )
        .onHover { hovering in
            paneController.setMainListHovering(hovering)
        }
        .onDisappear {
            paneController.closeIfActive(family: .memory)
        }
    }

    private func hoverableSection<Content: View>(
        chart: MemoryPaneChart,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let target = DetachedMetricsPaneTarget.memory(chart: chart)
        return HoverDetachSection(
            isActive: paneController.isActive(target),
            accent: DashboardPalette.memoryChartAccent,
            onPin: {
                coordinator.selectedMemoryPaneChart = chart
                if let parentWindow = currentParentWindow {
                    paneController.pin(target, coordinator: coordinator, parentWindow: parentWindow)
                }
            },
            onPreview: { hovering in
                if hovering, let parentWindow = currentParentWindow {
                    paneController.preview(target, coordinator: coordinator, parentWindow: parentWindow)
                } else {
                    paneController.clearPreview(target)
                }
            },
            content: content
        )
    }

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("PROCESSES")

            if featureStore.topProcesses.isEmpty {
                Text("Collecting process memory")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            } else {
                ForEach(featureStore.topProcesses.prefix(coordinator.memoryProcessCount)) { process in
                    ProcessListRow(entry: process)
                }
            }
        }
        .dashboardSurface(padding: 16, cornerRadius: 20)
    }

    private var pressureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("PRESSURE")
            fractionBar(value: pressurePercent / 100.0, color: DashboardPalette.networkAccent)
            keyValueRow(title: "Pressure", value: UnitsFormatter.format(pressurePercent, unit: .percent))
            keyValueRow(title: "App Memory", value: latestBytes(.memoryAppBytes))
            keyValueRow(title: "Wired", value: latestBytes(.memoryWiredBytes))
            keyValueRow(title: "Compressed", value: latestBytes(.memoryCompressedBytes))
            keyValueRow(title: "Cache", value: latestBytes(.memoryCacheBytes))
        }
    }

    private var compositionChartRefreshID: String {
        "\(coordinator.selectedMemoryHistoryWindow.rawValue)-\(coordinator.memoryHistoryRevision)-\(coordinator.chartSmoothingAlpha)"
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("MEMORY")

            CompactChartSection(refreshID: compositionChartRefreshID) {
                let history = await coordinator.memoryHistorySeries(
                    window: coordinator.selectedMemoryHistoryWindow,
                    maxPoints: ChartSeriesPipeline.targetPointCount(
                        for: coordinator.selectedMemoryHistoryWindow,
                        budget: .compactChart
                    )
                )
                return PreparedTimeSeriesChartModel.fromCompactMemoryComposition(
                    history: history,
                    window: coordinator.selectedMemoryHistoryWindow,
                    smoothingAlpha: coordinator.chartSmoothingAlpha
                )
            }

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(DashboardPalette.networkAccent)
                        .frame(width: proxy.size.width * wiredFraction)
                    Rectangle()
                        .fill(DashboardPalette.memoryAccent)
                        .frame(width: proxy.size.width * activeFraction)
                    Rectangle()
                        .fill(DashboardPalette.temperatureAccent)
                        .frame(width: proxy.size.width * compressedFraction)
                    Rectangle()
                        .fill(DashboardPalette.tertiaryText.opacity(0.55))
                        .frame(width: proxy.size.width * freeFraction)
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())

            memoryLegendRow(title: "Wired", color: DashboardPalette.networkAccent, value: wiredBytes)
            memoryLegendRow(title: "Active", color: DashboardPalette.memoryAccent, value: activeBytes)
            memoryLegendRow(title: "Compressed", color: DashboardPalette.temperatureAccent, value: compressedBytes)
            memoryLegendRow(title: "Free", color: DashboardPalette.tertiaryText, value: freeBytes)
        }
    }

    private var swapSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("SWAP MEMORY")
            fractionBar(value: swapUsedFraction, color: DashboardPalette.networkAccent)
            Text("\(UnitsFormatter.format(swapUsedBytes, unit: .bytes)) of \(UnitsFormatter.format(swapTotalBytes, unit: .bytes))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(DashboardPalette.secondaryText)
        }
    }

    private var pagesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("PAGES")
            keyValueRow(
                title: "Page Ins",
                value: UnitsFormatter.format(
                    featureStore.pageInsBytesPerSecond,
                    unit: .bytesPerSecond,
                    throughputUnit: coordinator.throughputUnit
                )
            )
            keyValueRow(
                title: "Page Outs",
                value: UnitsFormatter.format(
                    featureStore.pageOutsBytesPerSecond,
                    unit: .bytesPerSecond,
                    throughputUnit: coordinator.throughputUnit
                )
            )
        }
    }

    private var pressurePercent: Double {
        featureStore.pressurePercent
    }

    private var wiredBytes: Double {
        featureStore.wiredBytes
    }

    private var activeBytes: Double {
        featureStore.activeBytes
    }

    private var compressedBytes: Double {
        featureStore.compressedBytes
    }

    private var freeBytes: Double {
        featureStore.freeBytes
    }

    private var totalMemoryBytes: Double {
        max(1, wiredBytes + activeBytes + compressedBytes + freeBytes)
    }

    private var wiredFraction: Double {
        min(max(wiredBytes / totalMemoryBytes, 0), 1)
    }

    private var activeFraction: Double {
        min(max(activeBytes / totalMemoryBytes, 0), 1)
    }

    private var compressedFraction: Double {
        min(max(compressedBytes / totalMemoryBytes, 0), 1)
    }

    private var freeFraction: Double {
        min(max(freeBytes / totalMemoryBytes, 0), 1)
    }

    private var swapUsedBytes: Double {
        featureStore.swapUsedBytes
    }

    private var swapTotalBytes: Double {
        featureStore.swapTotalBytes
    }

    private var swapUsedFraction: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return min(max(swapUsedBytes / swapTotalBytes, 0), 1)
    }

    private var currentParentWindow: NSWindow? {
        hostWindow ?? NSApp.keyWindow
    }

    private func sectionTitle(_ text: String) -> some View {
        DashboardSectionLabel(title: text, tint: DashboardPalette.memoryAccent)
    }

    private func fractionBar(value: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DashboardPalette.insetFill)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 12)
    }

    private func keyValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(DashboardPalette.secondaryText)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
        }
        .font(.subheadline)
    }

    private func memoryLegendRow(title: String, color: Color, value: Double) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .foregroundStyle(DashboardPalette.secondaryText)
            Spacer()
            Text(UnitsFormatter.format(value, unit: .bytes))
                .font(.body.monospacedDigit())
        }
        .font(.subheadline)
    }

    private func latestBytes(_ metricID: MetricID) -> String {
        let value: Double
        switch metricID {
        case .memoryAppBytes:
            value = featureStore.appBytes
        case .memoryWiredBytes:
            value = featureStore.wiredBytes
        case .memoryCompressedBytes:
            value = featureStore.compressedBytes
        case .memoryCacheBytes:
            value = featureStore.cacheBytes
        default:
            value = 0
        }
        return UnitsFormatter.format(value, unit: .bytes)
    }
}
