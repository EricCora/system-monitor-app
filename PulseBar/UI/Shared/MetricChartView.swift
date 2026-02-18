import Charts
import SwiftUI
import PulseBarCore

struct MetricChartView: View {
    let title: String
    let samples: [MetricSample]
    let throughputUnit: ThroughputDisplayUnit

    @State private var hoveredSample: MetricSample?
    @State private var isHoveringChart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if samples.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Collecting Samples")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(samples, id: \.timestamp) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Value", sample.value)
                    )
                    .interpolationMethod(.catmullRom)

                    if let hoveredSample {
                        RuleMark(x: .value("Hover Time", hoveredSample.timestamp))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    if isThermalStateChart {
                        AxisMarks(position: .leading, values: [0, 1, 2, 3]) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let numericValue = value.as(Double.self) {
                                    Text(axisLabel(for: numericValue))
                                }
                            }
                        }
                    } else {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let numericValue = value.as(Double.self) {
                                    Text(axisLabel(for: numericValue))
                                }
                            }
                        }
                    }
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
    }

    private var isThermalStateChart: Bool {
        samples.first?.metricID == .thermalStateLevel
    }

    private var yDomain: ClosedRange<Double> {
        if isThermalStateChart {
            return 0...3
        }

        let values = samples.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        if minValue == maxValue {
            let delta = max(1, abs(minValue * 0.1))
            return (minValue - delta)...(maxValue + delta)
        }

        let padding = (maxValue - minValue) * 0.1
        return max(0, minValue - padding)...(maxValue + padding)
    }

    private var summarySample: MetricSample? {
        if isHoveringChart {
            return hoveredSample ?? samples.last
        }
        return samples.last
    }

    @ViewBuilder
    private var hoverSummaryRow: some View {
        HStack {
            if let summarySample {
                Text(summarySample.timestamp.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(.secondary)
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
        samples.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        })
    }

    private func axisLabel(for value: Double) -> String {
        guard let unit = samples.first?.unit else {
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
        case .scalar:
            if isThermalStateChart {
                return ThermalStateLevel.from(metricValue: value.rounded()).shortLabel
            }
            return String(format: "%.1f", value)
        }
    }
}
