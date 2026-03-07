import SwiftUI
import PulseBarCore

struct MemoryTabView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            if let processStatus = coordinator.memoryProcessesStatusMessage {
                Text(processStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let historyStatus = coordinator.historyStoreStatusMessage ?? coordinator.memoryHistoryStoreStatusMessage {
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
        return Button {
            coordinator.selectedMemoryPaneChart = chart
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
            coordinator.selectedMemoryPaneChart = chart
            if hovering {
                if let parentWindow = currentParentWindow {
                    paneController.preview(target, coordinator: coordinator, parentWindow: parentWindow)
                }
            } else {
                paneController.clearPreview(target)
            }
        }
    }

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("PROCESSES")

            if coordinator.topMemoryProcesses.isEmpty {
                Text("Collecting process memory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.topMemoryProcesses.prefix(coordinator.memoryProcessCount)) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .lineLimit(1)
                        Spacer()
                        Text(UnitsFormatter.format(process.residentBytes, unit: .bytes))
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

    private var pressureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("PRESSURE")
            fractionBar(value: pressurePercent / 100.0, color: .cyan)
            keyValueRow(title: "Pressure", value: UnitsFormatter.format(pressurePercent, unit: .percent))
            keyValueRow(title: "App Memory", value: latestBytes(.memoryAppBytes))
            keyValueRow(title: "Wired", value: latestBytes(.memoryWiredBytes))
            keyValueRow(title: "Compressed", value: latestBytes(.memoryCompressedBytes))
            keyValueRow(title: "Cache", value: latestBytes(.memoryCacheBytes))
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("MEMORY")

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: proxy.size.width * wiredFraction)
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: proxy.size.width * activeFraction)
                    Rectangle()
                        .fill(Color.purple)
                        .frame(width: proxy.size.width * compressedFraction)
                    Rectangle()
                        .fill(Color.gray.opacity(0.45))
                        .frame(width: proxy.size.width * freeFraction)
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())

            memoryLegendRow(title: "Wired", color: .cyan, value: wiredBytes)
            memoryLegendRow(title: "Active", color: .red, value: activeBytes)
            memoryLegendRow(title: "Compressed", color: .purple, value: compressedBytes)
            memoryLegendRow(title: "Free", color: .gray, value: freeBytes)
        }
    }

    private var swapSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("SWAP MEMORY")
            fractionBar(value: swapUsedFraction, color: .cyan)
            Text("\(UnitsFormatter.format(swapUsedBytes, unit: .bytes)) of \(UnitsFormatter.format(swapTotalBytes, unit: .bytes))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var pagesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("PAGES")
            keyValueRow(
                title: "Page Ins",
                value: UnitsFormatter.format(
                    coordinator.latestValue(for: .memoryPageInsBytesPerSec)?.value ?? 0,
                    unit: .bytesPerSecond,
                    throughputUnit: coordinator.throughputUnit
                )
            )
            keyValueRow(
                title: "Page Outs",
                value: UnitsFormatter.format(
                    coordinator.latestValue(for: .memoryPageOutsBytesPerSec)?.value ?? 0,
                    unit: .bytesPerSecond,
                    throughputUnit: coordinator.throughputUnit
                )
            )
        }
    }

    private var pressurePercent: Double {
        coordinator.latestValue(for: .memoryPressureLevel)?.value ?? 0
    }

    private var wiredBytes: Double {
        coordinator.latestValue(for: .memoryWiredBytes)?.value ?? 0
    }

    private var activeBytes: Double {
        coordinator.latestValue(for: .memoryActiveBytes)?.value ?? 0
    }

    private var compressedBytes: Double {
        coordinator.latestValue(for: .memoryCompressedBytes)?.value ?? 0
    }

    private var freeBytes: Double {
        coordinator.latestValue(for: .memoryFreeBytes)?.value ?? 0
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
        coordinator.latestValue(for: .memorySwapUsedBytes)?.value ?? 0
    }

    private var swapTotalBytes: Double {
        max(swapUsedBytes, coordinator.latestValue(for: .memorySwapTotalBytes)?.value ?? 0)
    }

    private var swapUsedFraction: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return min(max(swapUsedBytes / swapTotalBytes, 0), 1)
    }

    private var currentParentWindow: NSWindow? {
        hostWindow ?? NSApp.keyWindow
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.cyan)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func fractionBar(value: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            Spacer()
            Text(UnitsFormatter.format(value, unit: .bytes))
                .font(.body.monospacedDigit())
        }
        .font(.subheadline)
    }

    private func latestBytes(_ metricID: MetricID) -> String {
        UnitsFormatter.format(coordinator.latestValue(for: metricID)?.value ?? 0, unit: .bytes)
    }
}
