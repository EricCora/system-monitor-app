import AppKit
import SwiftUI
import PulseBarCore

struct CPUTabView: View {
    let coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController
    let usageStore: CPUUsageSurfaceStore
    let loadStore: CPULoadSurfaceStore
    let processesStore: CPUProcessesSurfaceStore
    let gpuStore: CPUGPUSurfaceStore
    let fpsStore: CPUFPSSurfaceStore
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTabMetrics.sectionSpacing) {
            if showsCompactChartWindowPicker {
                ChartTabToolbar(
                    coordinator: coordinator,
                    historyWindow: Binding(
                        get: { coordinator.compactCPUChartWindow },
                        set: { coordinator.compactCPUChartWindow = $0 }
                    )
                )
            }

            ForEach(coordinator.cpuMenuLayout.visibleSections, id: \.self) { section in
                switch section {
                case .usage:
                    hoverableSection(chart: .usage) {
                        CPUUsageSection(store: usageStore, areaOpacity: coordinator.chartAreaOpacity)
                    }
                case .processes:
                    CPUProcessesSection(store: processesStore, processCount: coordinator.cpuProcessCount)
                case .appleSilicon:
                    hoverableSection(chart: .gpu) {
                        CPUGPUSection(store: gpuStore)
                    }
                case .framesPerSecond:
                    hoverableSection(chart: .framesPerSecond) {
                        CPUFPSSection(store: fpsStore)
                    }
                case .loadAverage:
                    hoverableSection(chart: .loadAverage) {
                        CPULoadSection(store: loadStore, areaOpacity: coordinator.chartAreaOpacity)
                    }
                case .uptime:
                    CPUUptimeSection(store: usageStore)
                }
            }

            if let processStatus = processesStore.snapshot.statusMessage {
                Text(processStatus)
                    .font(.caption2)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            if let gpuStatus = gpuStore.snapshot.summary?.statusMessage, gpuStore.snapshot.summary?.available == false {
                Text(gpuStatus)
                    .font(.caption2)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            if let fpsStatus = fpsStore.snapshot.statusMessage {
                Text(fpsStatus)
                    .font(.caption2)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }

            if let historyStatus = coordinator.historyStoreStatusMessage {
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
        .task {
            coordinator.refreshCPUCompactSurface(forceReload: false)
        }
        .task(id: coordinator.compactCPUChartWindow.rawValue) {
            coordinator.refreshCPUCompactSurface(forceReload: true)
        }
        .onHover { hovering in
            paneController.setMainListHovering(hovering)
        }
        .onDisappear {
            paneController.closeIfActive(family: .cpu)
        }
    }

    private func hoverableSection<Content: View>(
        chart: CPUPaneChart,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let target = DetachedMetricsPaneTarget.cpu(chart: chart)
        return HoverDetachSection(
            isActive: paneController.isActive(target),
            accent: DashboardPalette.cpuChartAccent,
            onPin: {
                coordinator.selectedCPUPaneChart = chart
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

    private var currentParentWindow: NSWindow? {
        hostWindow ?? NSApp.keyWindow
    }

    private var showsCompactChartWindowPicker: Bool {
        coordinator.cpuMenuLayout.visibleSections.contains(.usage)
            || coordinator.cpuMenuLayout.visibleSections.contains(.loadAverage)
    }
}

private struct CPUUsageSection: View {
    @ObservedObject var store: CPUUsageSurfaceStore
    let areaOpacity: Double

    var body: some View {
        let snapshot = store.snapshot
        VStack(alignment: .leading, spacing: 8) {
            CPUSectionTitle("CPU")

            HStack(alignment: .top, spacing: 8) {
                DashboardMiniChart(
                    model: PreparedTimeSeriesChartModel.fromCompactCPUUsage(
                        renderModel: snapshot.renderModel
                    ),
                    areaOpacity: areaOpacity,
                    showsPlotBackground: true
                )
                .frame(height: 92)

                CompactCPUBars(coreSamples: snapshot.coreSamples)
                    .frame(width: 78, height: 92)
            }

            CPULegendRow(title: "User", color: DashboardPalette.cpuUserAccent, value: snapshot.summary.userPercent)
            CPULegendRow(title: "System", color: DashboardPalette.cpuSystemAccent, value: snapshot.summary.systemPercent)
            CPULegendRow(title: "Idle", color: DashboardPalette.tertiaryText, value: snapshot.summary.idlePercent)
        }
    }
}

private struct CPUProcessesSection: View {
    @ObservedObject var store: CPUProcessesSurfaceStore
    let processCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CPUSectionTitle("PROCESSES")

            if store.snapshot.entries.isEmpty {
                Text("Collecting CPU processes")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            } else {
                ForEach(store.snapshot.entries.prefix(processCount)) { process in
                    ProcessListRow(entry: process)
                }
            }
        }
        .dashboardSurface()
    }
}

private struct CPUGPUSection: View {
    @ObservedObject var store: CPUGPUSurfaceStore

    var body: some View {
        let gpu = store.snapshot.summary
        return VStack(alignment: .leading, spacing: 8) {
            CPUSectionTitle(gpu?.deviceName.uppercased() ?? "APPLE SILICON")

            if let gpu, gpu.available {
                CPUMetricBarRow(title: "Processor", value: gpu.processorPercent ?? 0, color: DashboardPalette.cpuAccent)
                CPUMetricBarRow(title: "Memory", value: gpu.memoryPercent ?? 0, color: DashboardPalette.networkAccent)
            } else {
                CPUMetricBarRow(title: "Processor", value: 0, color: DashboardPalette.cpuAccent)
                CPUMetricBarRow(title: "Memory", value: 0, color: DashboardPalette.networkAccent)
                Text(gpu?.statusMessage ?? "GPU telemetry unavailable")
                    .font(.caption2)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
        }
    }
}

private struct CPUFPSSection: View {
    @ObservedObject var store: CPUFPSSurfaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CPUSectionTitle("FRAMES PER SECOND")
            HStack {
                Text("Frames Per Second")
                    .foregroundStyle(DashboardPalette.secondaryText)
                Spacer()
                if let fps = store.snapshot.framesPerSecond {
                    Text(String(format: "%.1f", fps))
                        .font(.body.monospacedDigit())
                } else {
                    Text("--")
                        .font(.body.monospacedDigit())
                }
            }
            .font(.subheadline)
        }
    }
}

private struct CPULoadSection: View {
    @ObservedObject var store: CPULoadSurfaceStore
    let areaOpacity: Double

    var body: some View {
        let snapshot = store.snapshot
        VStack(alignment: .leading, spacing: 8) {
            CPUSectionTitle("LOAD AVERAGE")

            DashboardMiniChart(
                model: PreparedTimeSeriesChartModel.fromCompactCPULoad(renderModel: snapshot.renderModel),
                areaOpacity: areaOpacity,
                showsPlotBackground: true
            )
            .frame(height: 92)

            HStack(spacing: 12) {
                CPULoadBadge(value: snapshot.loadAverages.one, color: DashboardPalette.cpuAccent)
                CPULoadBadge(value: snapshot.loadAverages.five, color: DashboardPalette.memoryAccent)
                CPULoadBadge(value: snapshot.loadAverages.fifteen, color: DashboardPalette.tertiaryText)
            }
        }
    }
}

private struct CPUUptimeSection: View {
    @ObservedObject var store: CPUUsageSurfaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CPUSectionTitle("UPTIME")
            Text(UnitsFormatter.format(store.snapshot.summary.uptimeSeconds, unit: .seconds))
                .font(.body.monospacedDigit())
        }
        .dashboardSurface(padding: 16, cornerRadius: 20)
    }
}

private struct CPUSectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        DashboardSectionLabel(title: text, tint: DashboardPalette.cpuAccent)
    }
}

private struct CPULegendRow: View {
    let title: String
    let color: Color
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .foregroundStyle(DashboardPalette.secondaryText)
            Spacer()
            Text(UnitsFormatter.format(value, unit: .percent))
                .font(.body.monospacedDigit())
        }
        .font(.subheadline)
    }
}

private struct CPUMetricBarRow: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(DashboardPalette.secondaryText)
                Spacer()
                Text(UnitsFormatter.format(value, unit: .percent))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardPalette.insetFill)
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(max(value / 100.0, 0), 1))
                }
            }
            .frame(height: 12)
        }
    }
}

private struct CPULoadBadge: View {
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(String(format: "%.2f", value))
                .font(.caption.monospacedDigit())
        }
    }
}

private struct CompactCPUBars: View {
    let coreSamples: [MetricSample]

    var body: some View {
        GeometryReader { proxy in
            let barCount = max(1, coreSamples.count)
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(max(0, barCount - 1))
            let barWidth = max(3, (proxy.size.width - totalSpacing) / CGFloat(barCount))

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DashboardPalette.insetFill.opacity(0.72))

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(coreSamples, id: \.metricID) { sample in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(DashboardPalette.cpuAccent.opacity(0.95))
                            .frame(width: barWidth, height: max(4, proxy.size.height * CGFloat(min(max(sample.value / 100.0, 0), 1))))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
