import SwiftUI
import PulseBarCore

struct MetricChartView: View {
    let title: String
    let samples: [MetricSample]
    let throughputUnit: ThroughputDisplayUnit
    var seriesColor: Color = DashboardPalette.cpuChartAccent
    var displayOptions = ChartDisplayOptions()
    var diagnosticsStore: PerformanceDiagnosticsStore?

    @State private var chartModel = PreparedTimeSeriesChartModel.empty
    @State private var hiddenLegendIDs: Set<String> = []
    @State private var hoveredDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DashboardPalette.primaryText)

            if chartModel.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(DashboardPalette.secondaryText)
                    Text("Collecting Samples")
                        .font(.subheadline)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .dashboardInset()
            } else {
                DashboardTimeSeriesChart(
                    model: chartModel,
                    plotCornerRadius: DashboardChartTheme.tabPlotCornerRadius,
                    height: 180,
                    throughputUnit: throughputUnit,
                    hiddenLegendIDs: hiddenLegendIDs,
                    yAxisValues: isThermalStateChart ? [0, 1, 2, 3] : nil,
                    yAxisLabel: isThermalStateChart ? thermalAxisLabel : nil,
                    hoveredDate: $hoveredDate,
                    viewport: .constant(ChartViewport()),
                    zoomSelectionRect: .constant(nil)
                )
                .environment(\.dashboardChartDisplayOptions, effectiveDisplayOptions)

                ChartLegendStrip(items: legendItems, hiddenItemIDs: hiddenLegendIDs) { item in
                    ChartInteractionSupport.toggleLegendItem(item.id, hiddenLegendIDs: &hiddenLegendIDs)
                }
                hoverSummaryRow
            }
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .task(id: chartRefreshID) {
            rebuildChartModel()
        }
    }

    @Environment(\.dashboardChartDisplayOptions) private var environmentDisplayOptions

    private var effectiveDisplayOptions: ChartDisplayOptions {
        var options = displayOptions
        if isBatteryChargeChart && isNearConstantSeries {
            let base = options.areaOpacity ?? environmentDisplayOptions.resolvedAreaOpacity
            options.areaOpacity = base * 0.32
        }
        return options
    }

    private var isNearConstantSeries: Bool {
        guard samples.count >= 2 else { return samples.count <= 1 }
        let values = samples.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return true }
        return (maxValue - minValue) < 1.0
    }

    private var isThermalStateChart: Bool {
        samples.first?.metricID == .thermalStateLevel
    }

    private var isBatteryChargeChart: Bool {
        samples.first?.metricID == .batteryChargePercent
    }

    private var isTemperatureChart: Bool {
        samples.first?.metricID == .temperaturePrimaryCelsius
            || samples.first?.metricID == .temperatureMaxCelsius
            || samples.first?.unit == .celsius
    }

    private var baselinePolicy: ChartBaselinePolicy {
        if isThermalStateChart {
            return .fixed(0 ... 3)
        }
        if isBatteryChargeChart {
            return .fixed(0 ... 100)
        }
        if isTemperatureChart {
            return .dataMin(minimumSpan: 1, paddingFraction: 0.1)
        }
        return .zero(minimumSpan: 1, paddingFraction: 0.1)
    }

    private var summarySample: MetricSample? {
        ChartInteractionSupport.nearestPoint(in: samples, hoveredDate: hoveredDate)
    }

    private var legendItems: [ChartLegendItem] {
        [
            ChartLegendItem(
                id: title,
                label: title,
                color: seriesColor,
                valueText: summarySample.map {
                    UnitsFormatter.format($0.value, unit: $0.unit, throughputUnit: throughputUnit)
                }
            )
        ]
    }

    @ViewBuilder
    private var hoverSummaryRow: some View {
        HStack {
            if let summarySample {
                Text(summarySample.timestamp.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(DashboardPalette.secondaryText)
                Spacer()
                Text(UnitsFormatter.format(
                    summarySample.value,
                    unit: summarySample.unit,
                    throughputUnit: throughputUnit
                ))
            } else {
                Text(" ")
                Spacer()
                Text(" ")
            }
        }
        .font(.caption)
        .frame(height: 18)
    }

    private func thermalAxisLabel(_ value: Double) -> String {
        ThermalStateLevel.from(metricValue: value.rounded()).shortLabel
    }

    private var chartRefreshID: String {
        let first = samples.first?.timestamp.timeIntervalSince1970 ?? 0
        let last = samples.last?.timestamp.timeIntervalSince1970 ?? 0
        let lastValue = samples.last?.value ?? 0
        return "\(title)-\(samples.count)-\(first)-\(last)-\(lastValue)-\(displayOptions.smoothingAlpha)-\(displayOptions.showsMinorGrid)"
    }

    private func rebuildChartModel() {
        let start = ContinuousClock.now
        chartModel = PreparedTimeSeriesChartModel.fromMetricSamples(
            samples: samples,
            key: title,
            label: title,
            color: seriesColor,
            baseline: baselinePolicy,
            smoothingAlpha: displayOptions.normalizedSmoothingAlpha
        )
        let elapsed = start.duration(to: ContinuousClock.now)
        diagnosticsStore?.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }
}
