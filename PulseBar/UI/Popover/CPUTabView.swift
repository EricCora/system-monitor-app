import Charts
import SwiftUI
import PulseBarCore

struct CPUTabView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController
    @State private var hostWindow: NSWindow?
    @State private var userSamples: [MetricSample] = []
    @State private var systemSamples: [MetricSample] = []
    @State private var loadSamples: [MetricSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(coordinator.cpuMenuLayout.visibleSections, id: \.self) { section in
                switch section {
                case .usage:
                    hoverableSection(chart: .usage) {
                        usageSection
                    }
                case .processes:
                    processesSection
                case .appleSilicon:
                    hoverableSection(chart: .gpu) {
                        appleSiliconSection
                    }
                case .framesPerSecond:
                    hoverableSection(chart: .framesPerSecond) {
                        framesPerSecondSection
                    }
                case .loadAverage:
                    hoverableSection(chart: .loadAverage) {
                        loadAverageSection
                    }
                case .uptime:
                    uptimeSection
                }
            }

            if let processStatus = coordinator.cpuProcessesStatusMessage {
                Text(processStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let gpuStatus = coordinator.latestGPUSummary?.statusMessage, coordinator.latestGPUSummary?.available == false {
                Text(gpuStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let fpsStatus = coordinator.fpsStatusMessage {
                Text(fpsStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let historyStatus = coordinator.historyStoreStatusMessage {
                Text(historyStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PopoverWindowAccessor { window in
                if hostWindow !== window {
                    hostWindow = window
                }
            }
        )
        .task {
            await refresh()
        }
        .onReceive(coordinator.$latestSamples) { _ in
            Task { await refresh() }
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
        return Button {
            coordinator.selectedCPUPaneChart = chart
            if let parentWindow = currentParentWindow {
                paneController.pin(target, coordinator: coordinator, parentWindow: parentWindow)
            }
        } label: {
            content()
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(paneController.isActive(target) ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            coordinator.selectedCPUPaneChart = chart
            if hovering {
                if let parentWindow = currentParentWindow {
                    paneController.preview(target, coordinator: coordinator, parentWindow: parentWindow)
                }
            } else {
                paneController.clearPreview(target)
            }
        }
    }

    private var usageSection: some View {
        let summary = coordinator.cpuSummarySnapshot()
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("CPU")

            HStack(alignment: .top, spacing: 8) {
                CompactCPUUsageChart(userSamples: userSamples, systemSamples: systemSamples)
                    .frame(height: 92)

                CompactCPUBars(coreSamples: coordinator.latestCPUCores())
                    .frame(width: 78, height: 92)
            }

            cpuLegendRow(title: "User", color: .cyan, value: summary.userPercent)
            cpuLegendRow(title: "System", color: .red, value: summary.systemPercent)
            cpuLegendRow(title: "Idle", color: .gray, value: summary.idlePercent)
        }
    }

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("PROCESSES")

            if coordinator.topCPUProcesses.isEmpty {
                Text("Collecting CPU processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.topCPUProcesses.prefix(coordinator.cpuProcessCount)) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%%", process.cpuPercent))
                            .font(.body.monospacedDigit())
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var appleSiliconSection: some View {
        let gpu = coordinator.latestGPUSummary
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle(gpu?.deviceName.uppercased() ?? "APPLE SILICON")

            if let gpu, gpu.available {
                cpuMetricBarRow(title: "Processor", value: gpu.processorPercent ?? 0, color: .cyan)
                cpuMetricBarRow(title: "Memory", value: gpu.memoryPercent ?? 0, color: .blue)
            } else {
                cpuMetricBarRow(title: "Processor", value: 0, color: .cyan)
                cpuMetricBarRow(title: "Memory", value: 0, color: .blue)
                Text(gpu?.statusMessage ?? "GPU telemetry unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var framesPerSecondSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("FRAMES PER SECOND")
            HStack {
                Text("Frames Per Second")
                    .foregroundStyle(.secondary)
                Spacer()
                if let fps = coordinator.latestValue(for: .framesPerSecond)?.value {
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

    private var loadAverageSection: some View {
        let summary = coordinator.cpuSummarySnapshot()
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("LOAD AVERAGE")

            CompactLoadAverageChart(samples: loadSamples)
                .frame(height: 92)

            HStack(spacing: 12) {
                loadBadge(value: summary.loadAverages.one, color: .cyan)
                loadBadge(value: summary.loadAverages.five, color: .red)
                loadBadge(value: summary.loadAverages.fifteen, color: .gray)
            }
        }
    }

    private var uptimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("UPTIME")
            Text(UnitsFormatter.format(coordinator.cpuSummarySnapshot().uptimeSeconds, unit: .seconds))
                .font(.body.monospacedDigit())
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var currentParentWindow: NSWindow? {
        hostWindow ?? NSApp.keyWindow
    }

    private func refresh() async {
        userSamples = await coordinator.series(for: .cpuUserPercent, maxPoints: 60)
        systemSamples = await coordinator.series(for: .cpuSystemPercent, maxPoints: 60)
        loadSamples = await coordinator.series(for: .cpuLoadAverage1, maxPoints: 60)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.cyan)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func cpuLegendRow(title: String, color: Color, value: Double) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(UnitsFormatter.format(value, unit: .percent))
                .font(.body.monospacedDigit())
        }
        .font(.subheadline)
    }

    private func cpuMetricBarRow(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(UnitsFormatter.format(value, unit: .percent))
                    .font(.body.monospacedDigit())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(max(value / 100.0, 0), 1))
                }
            }
            .frame(height: 12)
        }
    }

    private func loadBadge(value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(String(format: "%.2f", value))
                .font(.caption.monospacedDigit())
        }
    }
}

private struct CompactCPUUsageChart: View {
    let userSamples: [MetricSample]
    let systemSamples: [MetricSample]

    private var points: [CompactCPUUsagePoint] {
        let sanitizedUserSamples = ChartSeriesSanitizer.metricSamples(userSamples)
        let sanitizedSystemSamples = ChartSeriesSanitizer.metricSamples(systemSamples)
        var output: [CompactCPUUsagePoint] = []
        output.append(contentsOf: sanitizedUserSamples.map { CompactCPUUsagePoint(timestamp: $0.timestamp, series: .user, value: $0.value) })
        output.append(contentsOf: sanitizedSystemSamples.map { CompactCPUUsagePoint(timestamp: $0.timestamp, series: .system, value: $0.value) })
        return output.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Percent", point.value),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Series", point.series.rawValue))
            .interpolationMethod(.linear)
        }
        .chartYScale(domain: 0...100)
        .chartForegroundStyleScale([
            CompactCPUUsagePoint.Series.user.rawValue: Color.cyan,
            CompactCPUUsagePoint.Series.system.rawValue: Color.red
        ])
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
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

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(coreSamples, id: \.metricID) { sample in
                    Rectangle()
                        .fill(Color.cyan.opacity(0.9))
                        .frame(width: barWidth, height: proxy.size.height * CGFloat(min(max(sample.value / 100.0, 0), 1)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

private struct CompactLoadAverageChart: View {
    let samples: [MetricSample]

    var body: some View {
        Chart(ChartSeriesSanitizer.metricSamples(samples), id: \.timestamp) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Load", sample.value)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(.cyan)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

private struct CompactCPUUsagePoint: Identifiable {
    enum Series: String {
        case user
        case system
    }

    let timestamp: Date
    let series: Series
    let value: Double

    var id: String { "\(timestamp.timeIntervalSince1970)-\(series.rawValue)" }
}
