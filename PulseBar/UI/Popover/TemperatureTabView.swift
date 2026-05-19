import AppKit
import SwiftUI
import PulseBarCore

struct TemperatureTabView: View {
    let coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController
    @ObservedObject var featureStore: TemperatureFeatureStore
    @State private var hostWindow: NSWindow?
    @State private var primaryTemperatureSamples: [MetricSample] = []
    @State private var maximumTemperatureSamples: [MetricSample] = []
    @State private var thermalStateSamples: [MetricSample] = []
    @State private var compareModeEnabled = false
    @State private var compareSelectionRevision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if featureStore.usingPersistedSnapshot, let capturedAt = featureStore.latestCapturedAt {
                DashboardInfoBanner(
                    text: "Showing last known sensors from \(capturedAt.formatted(date: .omitted, time: .standard)).",
                    tint: DashboardPalette.secondaryText,
                    fill: DashboardPalette.insetFill
                )
            }

            if let gateMessage = featureStore.fanParityGateMessage {
                DashboardInfoBanner(
                    text: gateMessage,
                    tint: featureStore.fanParityGateBlocked ? DashboardPalette.danger : DashboardPalette.secondaryText,
                    fill: featureStore.fanParityGateBlocked
                        ? DashboardPalette.danger.opacity(0.10)
                        : DashboardPalette.insetFill
                )
            }

            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: Binding(
                    get: { coordinator.selectedTemperatureHistoryWindow },
                    set: { coordinator.selectedTemperatureHistoryWindow = $0 }
                )
            )
            ChartToolsStrip(
                smoothingAlpha: Binding(
                    get: { coordinator.chartSmoothingAlpha },
                    set: { coordinator.chartSmoothingAlpha = $0 }
                ),
                showsMinorGrid: Binding(
                    get: { coordinator.chartMinorGridEnabled },
                    set: { coordinator.chartMinorGridEnabled = $0 }
                )
            )

            headerPanel
            sensorListPanel
            chartPanel
            diagnosticsPanel

            if coordinator.privilegedTemperatureEnabled && !featureStore.privilegedTemperatureHealthy {
                Button("Retry Privileged Sampling") {
                    coordinator.retryPrivilegedTemperatureNow()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            PopoverWindowAccessor { window in
                if hostWindow !== window {
                    hostWindow = window
                }
            }
        )
        .task {
            synchronizeSelectionAndPane()
        }
        .task(id: featureStore.visibleSensors.map(\.id).joined(separator: ",")) {
            synchronizeSelectionAndPane()
        }
        .task(id: chartRefreshID) {
            await refreshCharts()
        }
        .onDisappear {
            paneController.closeIfActive(family: .temperature)
        }
    }

    private var headerPanel: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                DashboardSectionLabel(title: "Temperature Focus", tint: DashboardPalette.temperatureAccent)
                Text(focusSensor?.displayName ?? "Thermal overview")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardPalette.primaryText)
                    .lineLimit(1)

                Text(focusSensor.map { TemperatureHistoryHelpers.valueText(for: $0) } ?? latestPrimaryTemperatureText)
                    .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)

                Text(selectionStatusText)
                    .font(.subheadline)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    summaryMetric(title: "Thermal State", value: coordinator.latestThermalState().label)
                    summaryMetric(title: "Primary Temp", value: latestPrimaryTemperatureText)
                }

                HStack(alignment: .top, spacing: 14) {
                    summaryMetric(title: "Maximum Temp", value: latestMaximumTemperatureText)
                    summaryMetric(title: "Source", value: sourceLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardSurface(padding: 18, cornerRadius: 20)
    }

    private var sensorListPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DashboardSectionLabel(title: "Sensors", tint: DashboardPalette.secondaryText)
                Spacer()
                Text("\(displayedSensorCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DashboardPalette.secondaryText)
                Button {
                    compareModeEnabled.toggle()
                    if compareModeEnabled {
                        presentComparePane()
                    }
                } label: {
                    Label("Compare", systemImage: "chart.line.uptrend.xyaxis")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(compareModeEnabled ? DashboardPalette.temperatureAccent : DashboardPalette.secondaryText)
            }

            if compareModeEnabled {
                compareSelectionStrip
            }

            if !coordinator.hiddenTemperatureSensorIDs.isEmpty {
                Button("Show Hidden Sensors (\(coordinator.hiddenTemperatureSensorIDs.count))") {
                    coordinator.resetHiddenTemperatureSensors()
                    synchronizeSelectionAndPane()
                }
                .buttonStyle(.bordered)
            }

            if hasAggregateRows {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(featureStore.groupedSensors) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                DashboardSectionLabel(title: group.category.label.uppercased(), tint: DashboardPalette.secondaryText)
                                Rectangle()
                                    .fill(DashboardPalette.divider)
                                    .frame(height: 1)
                            }

                            ForEach(group.aggregateRows, id: \.id) { row in
                                aggregateRow(row, group: group)
                            }
                        }
                    }
                }
            } else if !fallbackRows.isEmpty {
                DashboardInfoBanner(
                    text: "Using aggregate temperature metrics until privileged per-sensor sampling is available.",
                    tint: DashboardPalette.secondaryText,
                    fill: DashboardPalette.insetFill
                )

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fallbackRows, id: \.name) { sensor in
                        fallbackSensorRow(sensor)
                    }
                }
            } else {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .dashboardSurface(padding: 16, cornerRadius: 20)
        .onHover { hovering in
            paneController.setMainListHovering(hovering)
        }
    }

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    DashboardSectionLabel(title: "History Overview", tint: DashboardPalette.secondaryText)
                    Text("Primary, maximum, and thermal-state context")
                        .font(.subheadline)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
                Spacer()
                Text(coordinator.selectedTemperatureHistoryWindow.label)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)
            }

            MetricChartView(
                title: "Primary Temperature",
                samples: primaryTemperatureSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.temperatureAccent,
                displayOptions: ChartDisplayOptions(showsMinorGrid: coordinator.chartMinorGridEnabled, smoothingAlpha: coordinator.chartSmoothingAlpha)
            )

            MetricChartView(
                title: "Maximum Temperature",
                samples: maximumTemperatureSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.memoryAccent,
                displayOptions: ChartDisplayOptions(showsMinorGrid: coordinator.chartMinorGridEnabled, smoothingAlpha: coordinator.chartSmoothingAlpha)
            )

            MetricChartView(
                title: "Thermal State Level",
                samples: thermalStateSamples,
                throughputUnit: coordinator.throughputUnit,
                areaOpacity: coordinator.chartAreaOpacity,
                diagnosticsStore: coordinator.performanceDiagnosticsStore,
                seriesColor: DashboardPalette.cpuAccent,
                displayOptions: ChartDisplayOptions(showsMinorGrid: coordinator.chartMinorGridEnabled, smoothingAlpha: coordinator.chartSmoothingAlpha)
            )
        }
        .dashboardSurface(padding: 16, cornerRadius: 20)
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardSectionLabel(title: "Source Diagnostics", tint: DashboardPalette.secondaryText)

            if featureStore.privilegedSourceDiagnostics.isEmpty {
                Text("No diagnostics yet.")
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            } else {
                ForEach(Array(featureStore.privilegedSourceDiagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    HStack(alignment: .firstTextBaseline) {
                        Circle()
                            .fill(diagnostic.healthy ? DashboardPalette.success : DashboardPalette.danger)
                            .frame(width: 7, height: 7)
                        Text("\(diagnostic.source): \(diagnostic.message ?? (diagnostic.healthy ? "ok" : "failed"))")
                            .font(.caption)
                            .foregroundStyle(DashboardPalette.secondaryText)
                    }
                }
            }

            if let historyStatus = featureStore.temperatureHistoryStoreStatusMessage {
                Text(historyStatus)
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
        }
        .dashboardSurface(padding: 16, cornerRadius: 20)
    }

    private var displayedSensorCount: Int {
        let aggregateRowCount = featureStore.groupedSensors.flatMap(\.aggregateRows).count
        if aggregateRowCount > 0 {
            return aggregateRowCount
        }
        return fallbackRows.count
    }

    private var hasAggregateRows: Bool {
        featureStore.groupedSensors.contains { !$0.aggregateRows.isEmpty }
    }

    private var fallbackRows: [TemperatureSensorReading] {
        coordinator.fallbackTemperatureRows()
    }

    private var focusSensor: SensorReading? {
        coordinator.selectedSensorReading()
            ?? featureStore.visibleSensors.first
    }

    private var comparedSensorIDs: [String] {
        _ = compareSelectionRevision
        return coordinator.comparedTemperatureSensorIDs
    }

    private var comparedRows: [TemperatureAggregateRow] {
        _ = compareSelectionRevision
        return coordinator.comparedTemperatureRows()
    }

    private var compareSelectionStrip: some View {
        HStack(spacing: 8) {
            Text("\(comparedRows.count) selected")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(comparedRows.isEmpty ? DashboardPalette.secondaryText : DashboardPalette.primaryText)

            HStack(spacing: 5) {
                ForEach(Array(comparedRows.enumerated()), id: \.element.id) { index, row in
                    Circle()
                        .fill(compareColor(for: index))
                        .frame(width: 8, height: 8)
                        .help(row.displayName)
                }
            }

            Spacer()

            Text("Max \(coordinator.maxComparedTemperatureSensors)")
                .font(.caption)
                .foregroundStyle(DashboardPalette.tertiaryText)

            if !comparedRows.isEmpty {
                Button("Clear") {
                    coordinator.clearComparedTemperatureSensors()
                    compareSelectionRevision += 1
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DashboardPalette.insetFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                )
        )
    }

    private var latestPrimaryTemperatureText: String {
        if let latest = coordinator.latestValue(for: .temperaturePrimaryCelsius) {
            return UnitsFormatter.format(latest.value, unit: .celsius)
        }
        return "--"
    }

    private var latestMaximumTemperatureText: String {
        if let latest = coordinator.latestValue(for: .temperatureMaxCelsius) {
            return UnitsFormatter.format(latest.value, unit: .celsius)
        }
        return "--"
    }

    private var sourceLabel: String {
        if featureStore.usingPersistedSnapshot {
            return "Last Known"
        }
        if coordinator.privilegedTemperatureHealthy {
            return "Privileged"
        }
        return "Standard"
    }

    private var selectionStatusText: String {
        if let focusSensor {
            return "\(focusSensor.category.label) groups collapse to one row when max, average, and minimum would be identical."
        }
        return "Select a group row to inspect its live history."
    }

    private var emptyStateText: String {
        if coordinator.privilegedTemperatureEnabled && !featureStore.privilegedTemperatureHealthy {
            return "Privileged mode is unavailable right now. Falling back to standard thermal state history."
        }
        if !coordinator.hiddenTemperatureSensorIDs.isEmpty {
            return "All current sensors are hidden."
        }
        return "Temperature traces remain available from standard thermal state history."
    }

    private var currentParentWindow: NSWindow? {
        hostWindow ?? NSApp.keyWindow
    }

    private var chartRefreshID: String {
        "\(coordinator.selectedTemperatureHistoryWindow.rawValue)-\(coordinator.metricHistoryRevision)-\(coordinator.historyStoreStatusMessage ?? "")"
    }

    private func synchronizeSelectionAndPane() {
        if coordinator.selectedSensorReading() == nil {
            coordinator.selectedTemperatureSensorID = featureStore.visibleSensors.first?.id ?? ""
        }

        coordinator.comparedTemperatureSensorIDs = coordinator.comparedTemperatureSensorIDs
        compareSelectionRevision += 1
        paneController.reconcileTemperatureSensors(Set(featureStore.visibleSensors.map(\.id)))
        if featureStore.visibleSensors.isEmpty {
            paneController.closePanel(clearSelection: false)
        }
    }

    private func refreshCharts() async {
        async let primary = coordinator.series(for: .temperaturePrimaryCelsius, window: coordinator.selectedTemperatureHistoryWindow, maxPoints: 240)
        async let maximum = coordinator.series(for: .temperatureMaxCelsius, window: coordinator.selectedTemperatureHistoryWindow, maxPoints: 240)
        async let thermal = coordinator.series(for: .thermalStateLevel, window: coordinator.selectedTemperatureHistoryWindow, maxPoints: 240)

        primaryTemperatureSamples = await primary
        maximumTemperatureSamples = await maximum
        thermalStateSamples = await thermal
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardSectionLabel(title: title, tint: DashboardPalette.secondaryText)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(DashboardPalette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DashboardPalette.insetFill.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                )
        )
    }

    private func aggregateRow(_ row: TemperatureAggregateRow, group: TemperatureSensorGroup) -> some View {
        Button {
            if compareModeEnabled {
                coordinator.toggleComparedTemperatureSensor(sensorID: row.id)
                compareSelectionRevision += 1
                presentComparePane()
            } else {
                coordinator.comparedTemperatureSensorIDs = [row.id]
                compareSelectionRevision += 1
                if let parentWindow = currentParentWindow {
                    paneController.pin(.temperatureCompare, coordinator: coordinator, parentWindow: parentWindow)
                }
            }
        } label: {
            HStack(spacing: 8) {
                aggregateRowMarker(for: row)

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.displayName)
                        .font(.subheadline)
                        .foregroundStyle(DashboardPalette.primaryText)
                        .lineLimit(1)

                    Text(channelCountText(for: row))
                        .font(.caption2)
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(UnitsFormatter.format(row.value, unit: .celsius))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)
                    .frame(minWidth: 68, alignment: .trailing)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DashboardPalette.insetFill)
                        Capsule()
                            .fill(DashboardPalette.temperatureAccent)
                            .frame(width: barWidth(for: row, group: group, totalWidth: proxy.size.width))
                    }
                }
                .frame(width: 90, height: 10)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(for: row))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(borderColor(for: row), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func fallbackSensorRow(_ sensor: TemperatureSensorReading) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DashboardPalette.temperatureAccent)
                .frame(width: 8, height: 8)

            Text(sensor.name)
                .font(.subheadline)
                .foregroundStyle(DashboardPalette.primaryText)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(UnitsFormatter.format(sensor.celsius, unit: .celsius))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(DashboardPalette.primaryText)
                .frame(minWidth: 68, alignment: .trailing)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DashboardPalette.insetFill)
                    Capsule()
                        .fill(DashboardPalette.temperatureAccent)
                        .frame(width: proxy.size.width * CGFloat(min(max(sensor.celsius / fallbackScaleMax, 0), 1)))
                }
            }
            .frame(width: 90, height: 10)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardPalette.insetFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                )
        )
    }

    private var fallbackScaleMax: Double {
        max(45, fallbackRows.map(\.celsius).max() ?? 45)
    }

    private func backgroundColor(for row: TemperatureAggregateRow) -> Color {
        if paneController.isActive(.temperatureCompare), comparedSensorIDs.contains(row.id) {
            return DashboardPalette.selectionFill
        }
        return DashboardPalette.insetFill
    }

    private func borderColor(for row: TemperatureAggregateRow) -> Color {
        if compareModeEnabled,
           let comparedIndex = comparedSensorIDs.firstIndex(of: row.id) {
            return compareColor(for: comparedIndex).opacity(0.65)
        }
        if paneController.isActive(.temperatureCompare), comparedSensorIDs.contains(row.id) {
            return DashboardPalette.temperatureAccent.opacity(0.55)
        }
        return DashboardPalette.divider
    }

    private func barWidth(for row: TemperatureAggregateRow, group: TemperatureSensorGroup, totalWidth: CGFloat) -> CGFloat {
        totalWidth * group.barWidthRatio(for: row)
    }

    private func channelCountText(for row: TemperatureAggregateRow) -> String {
        row.sourceSensorCount == 1 ? "1 channel" : "\(row.sourceSensorCount) channels"
    }

    private func aggregateRowMarker(for row: TemperatureAggregateRow) -> some View {
        Group {
            if compareModeEnabled {
                if let comparedIndex = comparedSensorIDs.firstIndex(of: row.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(compareColor(for: comparedIndex))
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            } else {
                Circle()
                    .fill(DashboardPalette.temperatureAccent)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 12, height: 12)
    }

    private func presentComparePane() {
        guard !coordinator.comparedTemperatureRows().isEmpty,
              let parentWindow = currentParentWindow else { return }
        paneController.pin(.temperatureCompare, coordinator: coordinator, parentWindow: parentWindow)
    }

    private func compareColor(for index: Int) -> Color {
        Self.compareColors[index % Self.compareColors.count]
    }

    private static let compareColors: [Color] = [
        DashboardPalette.temperatureAccent,
        DashboardPalette.cpuAccent,
        DashboardPalette.memoryAccent,
        DashboardPalette.diskAccent,
        DashboardPalette.networkAccent,
        DashboardPalette.success
    ]
}
