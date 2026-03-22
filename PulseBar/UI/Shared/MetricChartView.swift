import Charts
import SwiftUI
import PulseBarCore

struct MetricChartView: View {
    let title: String
    let samples: [MetricSample]
    let throughputUnit: ThroughputDisplayUnit
    var areaOpacity: Double = 0.18
    var diagnosticsStore: PerformanceDiagnosticsStore?
    var seriesColor: Color = DashboardPalette.cpuAccent

    @State private var hoveredSample: MetricSample?
    @State private var isHoveringChart = false
    @State private var chartModel = PreparedMetricChartModel.empty

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DashboardPalette.primaryText)

            if chartModel.sanitizedSamples.isEmpty {
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
                Chart(chartModel.chartPoints) { point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        yStart: .value("Baseline", chartModel.chartScale.areaBaseline),
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

                    if let hoveredSample {
                        RuleMark(x: .value("Hover Time", hoveredSample.timestamp))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(DashboardPalette.chartRule)
                    }
                }
                .chartYScale(domain: chartModel.chartScale.yDomain)
                .chartYAxis {
                    if isThermalStateChart {
                        AxisMarks(position: .leading, values: [0, 1, 2, 3]) { value in
                            AxisGridLine().foregroundStyle(DashboardPalette.chartGrid)
                            AxisTick().foregroundStyle(DashboardPalette.secondaryText)
                            AxisValueLabel {
                                if let numericValue = value.as(Double.self) {
                                    Text(axisLabel(for: numericValue))
                                        .foregroundStyle(DashboardPalette.secondaryText)
                                }
                            }
                        }
                    } else {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(DashboardPalette.chartGrid)
                            AxisTick().foregroundStyle(DashboardPalette.secondaryText)
                            AxisValueLabel {
                                if let numericValue = value.as(Double.self) {
                                    Text(axisLabel(for: numericValue))
                                        .foregroundStyle(DashboardPalette.secondaryText)
                                }
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(DashboardPalette.chartGrid.opacity(0.55))
                        AxisTick().foregroundStyle(DashboardPalette.secondaryText)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(DashboardPalette.tertiaryText)
                            }
                        }
                    }
                }
                .chartPlotStyle { plot in
                    plot
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DashboardPalette.insetFill)
                        )
                }
                .frame(height: 180)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    isHoveringChart = true
                                    let xPosition = location.x - geometry[proxy.plotAreaFrame].origin.x
                                    guard xPosition >= 0,
                                          xPosition <= proxy.plotAreaSize.width,
                                          let date: Date = proxy.value(atX: xPosition, as: Date.self) else {
                                        hoveredSample = nil
                                        return
                                    }
                                    hoveredSample = nearestSample(to: date)
                                case .ended:
                                    isHoveringChart = false
                                    hoveredSample = nil
                                }
                            }
                    }
                }

                hoverSummaryRow
            }
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .task(id: chartRefreshID) {
            rebuildChartModel()
        }
    }

    private var isThermalStateChart: Bool {
        chartModel.sanitizedSamples.first?.metricID == .thermalStateLevel
    }

    private var isBatteryChargeChart: Bool {
        chartModel.sanitizedSamples.first?.metricID == .batteryChargePercent
    }

    private var baselinePolicy: ChartBaselinePolicy {
        if isThermalStateChart {
            return .fixed(0...3)
        }
        if isBatteryChargeChart {
            return .fixed(0...100)
        }
        return .zero(minimumSpan: 1, paddingFraction: 0.1)
    }

    private var summarySample: MetricSample? {
        if isHoveringChart {
            return hoveredSample ?? chartModel.sanitizedSamples.last
        }
        return chartModel.sanitizedSamples.last
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

    private func nearestSample(to date: Date) -> MetricSample? {
        chartModel.sanitizedSamples.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        })
    }

    private func axisLabel(for value: Double) -> String {
        guard let unit = chartModel.sanitizedSamples.first?.unit else {
            return String(format: "%.0f", value)
        }

        switch unit {
        case .bytes:
            return UnitsFormatter.formatBytes(value)
        case .bytesPerSecond:
            return UnitsFormatter.format(value, unit: .bytesPerSecond, throughputUnit: throughputUnit)
        case .percent:
            return String(format: "%.0f%%", value)
        case .celsius:
            return String(format: "%.0f C", value)
        case .milliamps:
            return String(format: "%.0f mA", value)
        case .watts:
            return String(format: "%.1f W", value)
        case .minutes:
            return UnitsFormatter.format(value, unit: .minutes)
        case .seconds:
            return UnitsFormatter.format(value, unit: .seconds)
        case .scalar:
            if isThermalStateChart {
                return ThermalStateLevel.from(metricValue: value.rounded()).shortLabel
            }
            return String(format: "%.1f", value)
        }
    }

    private var chartRefreshID: String {
        let first = samples.first?.timestamp.timeIntervalSince1970 ?? 0
        let last = samples.last?.timestamp.timeIntervalSince1970 ?? 0
        let lastValue = samples.last?.value ?? 0
        return "\(title)-\(samples.count)-\(first)-\(last)-\(lastValue)"
    }

    private func rebuildChartModel() {
        let start = ContinuousClock.now
        chartModel = PreparedMetricChartModel(
            samples: samples,
            title: title,
            baselinePolicy: baselinePolicy,
            color: seriesColor
        )
        let elapsed = start.duration(to: ContinuousClock.now)
        diagnosticsStore?.recordChartPreparation(milliseconds: durationMilliseconds(elapsed))
    }
}

private struct PreparedMetricChartModel {
    let sanitizedSamples: [MetricSample]
    let chartPoints: [TimeSeriesChartPoint]
    let chartScale: ChartScale

    init(samples: [MetricSample], title: String, baselinePolicy: ChartBaselinePolicy, color: Color) {
        sanitizedSamples = ChartSeriesPipeline.sanitize(samples, timestamp: \.timestamp)
        chartPoints = ChartSeriesPipeline.metricSamples(
            sanitizedSamples,
            key: title,
            label: title,
            color: color
        )
        chartScale = ChartSeriesPipeline.scale(for: chartPoints, baseline: baselinePolicy)
    }

    static let empty = PreparedMetricChartModel(samples: [], title: "", baselinePolicy: .zero(), color: DashboardPalette.cpuAccent)
}
