import Foundation
import PulseBarCore
import SwiftUI

enum DashboardTimeSeriesRenderStyle: Equatable {
    case stackedArea
    case baselineAreaLine
    case lineOnly
}

/// Controls downsampling budget for chart data preparation.
enum ChartSampleBudget: Equatable {
    case fullChart
    case compactChart
    case compareLine
    case sparkline
    case menuBarHistory
    case menuBarBars
    case bidirectionalBars
}

/// Selects the Canvas mini-chart renderer; independent of sample budget.
enum DashboardMiniChartPresentation: Equatable {
    case timeSeries
    case indexedSparkline
    case menuBarHistory
    case menuBarBars
    case bidirectionalBars
}

struct PreparedTimeSeriesChartModel {
    let points: [TimeSeriesChartPoint]
    let scale: ChartScale
    let fallbackXDomain: ClosedRange<Date>
    let renderStyle: DashboardTimeSeriesRenderStyle
    let sampleBudget: ChartSampleBudget
    let miniPresentation: DashboardMiniChartPresentation?
    let primaryUnit: MetricUnit?
    let fixedYDomain: ClosedRange<Double>?
    let positiveValues: [Double]
    let negativeValues: [Double]

    var isEmpty: Bool { points.isEmpty && positiveValues.isEmpty && negativeValues.isEmpty }

    init(
        points: [TimeSeriesChartPoint],
        baseline: ChartBaselinePolicy,
        renderStyle: DashboardTimeSeriesRenderStyle,
        sampleBudget: ChartSampleBudget = .fullChart,
        miniPresentation: DashboardMiniChartPresentation? = nil,
        primaryUnit: MetricUnit? = nil,
        fixedYDomain: ClosedRange<Double>? = nil,
        positiveValues: [Double] = [],
        negativeValues: [Double] = []
    ) {
        self.points = points
        self.scale = ChartSeriesPipeline.scale(for: points, baseline: baseline)
        self.fallbackXDomain = Self.makeXDomain(from: points.map(\.timestamp))
        self.renderStyle = renderStyle
        self.sampleBudget = sampleBudget
        self.miniPresentation = miniPresentation
        self.primaryUnit = primaryUnit
        self.fixedYDomain = fixedYDomain
        self.positiveValues = positiveValues
        self.negativeValues = negativeValues
    }

    static let empty = PreparedTimeSeriesChartModel(
        points: [],
        baseline: .zero(),
        renderStyle: .baselineAreaLine
    )

    static func fromCPUUsage(
        userHistory: [MetricHistoryPoint],
        systemHistory: [MetricHistoryPoint],
        window: ChartWindow? = nil,
        smoothingAlpha: Double = 1.0
    ) -> PreparedTimeSeriesChartModel {
        let maxPoints = ChartSeriesPipeline.targetPointCount(for: window, budget: .fullChart)
        let user = ChartSeriesPipeline.prepareMetricHistory(
            ChartSeriesPipeline.sanitize(userHistory, timestamp: \.timestamp),
            maxPoints: maxPoints,
            smoothingAlpha: smoothingAlpha
        )
        let system = ChartSeriesPipeline.prepareMetricHistory(
            ChartSeriesPipeline.sanitize(systemHistory, timestamp: \.timestamp),
            maxPoints: maxPoints,
            smoothingAlpha: smoothingAlpha
        )
        let descriptors = [
            ChartMetricSeriesDescriptor(key: "cpu.user", label: "User", color: DashboardPalette.cpuUserAccent, samples: user),
            ChartMetricSeriesDescriptor(key: "cpu.system", label: "System", color: DashboardPalette.cpuSystemAccent, samples: system)
        ]
        let points = ChartSeriesPipeline.metricHistory(series: descriptors)
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: .fixed(0 ... 100),
            renderStyle: .stackedArea,
            sampleBudget: .fullChart,
            primaryUnit: .percent,
            fixedYDomain: 0 ... 100
        )
    }

    static func fromMetricHistory(
        series: [ChartMetricSeriesDescriptor<MetricHistoryPoint>],
        baseline: ChartBaselinePolicy,
        renderStyle: DashboardTimeSeriesRenderStyle = .baselineAreaLine,
        window: ChartWindow? = nil,
        smoothingAlpha: Double = 1.0,
        sampleBudget: ChartSampleBudget = .fullChart
    ) -> PreparedTimeSeriesChartModel {
        let maxPoints = ChartSeriesPipeline.targetPointCount(for: window, budget: sampleBudget)
        let smoothed = series.map {
            ChartMetricSeriesDescriptor(
                key: $0.key,
                label: $0.label,
                color: $0.color,
                samples: ChartSeriesPipeline.prepareMetricHistory($0.samples, maxPoints: maxPoints, smoothingAlpha: smoothingAlpha)
            )
        }
        let points = ChartSeriesPipeline.metricHistory(series: smoothed)
        let unit = smoothed.lazy.flatMap(\.samples).first?.unit
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: baseline,
            renderStyle: renderStyle,
            sampleBudget: sampleBudget,
            primaryUnit: unit
        )
    }

    static func fromMetricSamples(
        samples: [MetricSample],
        key: String,
        label: String,
        color: Color,
        baseline: ChartBaselinePolicy,
        window: ChartWindow? = nil,
        smoothingAlpha: Double = 1.0,
        sampleBudget: ChartSampleBudget = .fullChart
    ) -> PreparedTimeSeriesChartModel {
        let maxPoints = ChartSeriesPipeline.targetPointCount(for: window, budget: sampleBudget)
        let smoothed = ChartSeriesPipeline.prepareMetricSamples(samples, maxPoints: maxPoints, smoothingAlpha: smoothingAlpha)
        let points = ChartSeriesPipeline.metricSamples(smoothed, key: key, label: label, color: color)
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: baseline,
            renderStyle: .baselineAreaLine,
            sampleBudget: sampleBudget,
            primaryUnit: smoothed.first?.unit
        )
    }

    static func fromMemoryComposition(
        history: [MemoryHistoryPoint],
        smoothingAlpha: Double = 1.0
    ) -> PreparedTimeSeriesChartModel {
        let points = ChartSeriesPipeline.memoryCompositionPoints(history: history, smoothingAlpha: smoothingAlpha)
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: .fixed(0 ... 100),
            renderStyle: .stackedArea,
            sampleBudget: .fullChart,
            fixedYDomain: 0 ... 100
        )
    }

    static func fromTemperatureHistory(
        series: [ChartMetricSeriesDescriptor<TemperatureHistoryPoint>],
        baseline: ChartBaselinePolicy,
        renderStyle: DashboardTimeSeriesRenderStyle = .baselineAreaLine,
        window: ChartWindow? = nil,
        smoothingAlpha: Double = 1.0,
        sampleBudget: ChartSampleBudget = .fullChart
    ) -> PreparedTimeSeriesChartModel {
        let maxPoints = ChartSeriesPipeline.targetPointCount(for: window, budget: sampleBudget)
        let smoothed = series.map {
            ChartMetricSeriesDescriptor(
                key: $0.key,
                label: $0.label,
                color: $0.color,
                samples: ChartSeriesPipeline.prepareTemperatureHistory($0.samples, maxPoints: maxPoints, smoothingAlpha: smoothingAlpha)
            )
        }
        let points = ChartSeriesPipeline.temperatureHistory(series: smoothed)
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: baseline,
            renderStyle: renderStyle,
            sampleBudget: sampleBudget,
            primaryUnit: .celsius
        )
    }

    static func fromTemperatureCompare(
        series: [ChartMetricSeriesDescriptor<TemperatureHistoryPoint>],
        window: ChartWindow? = nil,
        smoothingAlpha: Double = 1.0
    ) -> PreparedTimeSeriesChartModel {
        fromTemperatureHistory(
            series: series,
            baseline: .dataMin(minimumSpan: 1, paddingFraction: 0.12),
            renderStyle: .lineOnly,
            window: window,
            smoothingAlpha: smoothingAlpha,
            sampleBudget: .compareLine
        )
    }

    static func fromCompactCPUUsage(
        renderModel: CompactCPUUsageRenderModel
    ) -> PreparedTimeSeriesChartModel {
        let points = ChartSeriesPipeline.compactCPUUsagePoints(renderModel: renderModel)
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: .fixed(0 ... 100),
            renderStyle: .stackedArea,
            sampleBudget: .compactChart,
            miniPresentation: .timeSeries,
            primaryUnit: .percent,
            fixedYDomain: 0 ... 100
        )
    }

    static func fromCompactCPULoad(
        renderModel: CompactCPULoadRenderModel
    ) -> PreparedTimeSeriesChartModel {
        let descriptors: [(String, String, Color, [CompactChartSegment<CompactChartPoint>])] = [
            ("load.15", "15 Minute", DashboardPalette.tertiaryText, renderModel.fifteenMinuteSegments),
            ("load.5", "5 Minute", DashboardPalette.memoryChartAccent, renderModel.fiveMinuteSegments),
            ("load.1", "1 Minute", DashboardPalette.cpuChartAccent, renderModel.oneMinuteSegments)
        ]

        var points: [TimeSeriesChartPoint] = []
        for (key, label, color, segments) in descriptors {
            for segment in segments {
                let keys = ChartSeriesPipeline.continuityKeys(for: segment.points, seriesKey: key, timestamp: \.timestamp)
                for (point, continuityKey) in zip(segment.points, keys) {
                    points.append(
                        TimeSeriesChartPoint(
                            timestamp: point.timestamp,
                            value: point.value,
                            seriesKey: key,
                            seriesLabel: label,
                            continuityKey: continuityKey,
                            color: color
                        )
                    )
                }
            }
        }
        points.sort {
            if $0.timestamp == $1.timestamp {
                return $0.seriesKey < $1.seriesKey
            }
            return $0.timestamp < $1.timestamp
        }
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
            renderStyle: .baselineAreaLine,
            sampleBudget: .compactChart,
            miniPresentation: .timeSeries,
            primaryUnit: .scalar,
            fixedYDomain: renderModel.yDomain
        )
    }

    static func fromSparklineValues(
        _ values: [Double],
        color: Color = DashboardPalette.cpuChartAccent,
        maxPoints: Int = ChartSeriesPipeline.targetPointCount(for: nil, budget: .sparkline)
    ) -> PreparedTimeSeriesChartModel {
        let points = ChartSeriesPipeline.presentationIndexedPoints(
            values: values,
            key: "sparkline",
            label: "History",
            color: color,
            maxPoints: maxPoints
        )
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: .dataMin(minimumSpan: 0.001, paddingFraction: 0.08),
            renderStyle: .baselineAreaLine,
            sampleBudget: .sparkline,
            miniPresentation: .indexedSparkline,
            primaryUnit: .percent
        )
    }

    static func fromBidirectionalSparkline(
        positiveValues: [Double],
        negativeValues: [Double],
        positiveColor: Color = DashboardPalette.networkChartAccent,
        negativeColor: Color = DashboardPalette.diskChartAccent,
        maxPoints: Int = ChartSeriesPipeline.targetPointCount(for: nil, budget: .sparkline)
    ) -> PreparedTimeSeriesChartModel {
        PreparedTimeSeriesChartModel(
            points: [],
            baseline: .zero(minimumSpan: 1, paddingFraction: 0.1),
            renderStyle: .lineOnly,
            sampleBudget: .bidirectionalBars,
            miniPresentation: .bidirectionalBars,
            positiveValues: Array(positiveValues.suffix(maxPoints)),
            negativeValues: Array(negativeValues.suffix(maxPoints))
        )
    }

    static func fromMenuBarHistory(
        _ values: [Double],
        color: Color
    ) -> PreparedTimeSeriesChartModel {
        let maxPoints = ChartSeriesPipeline.targetPointCount(for: nil, budget: .menuBarHistory)
        let points = ChartSeriesPipeline.presentationIndexedPoints(
            values: values,
            key: "menubar.history",
            label: "History",
            color: color,
            maxPoints: maxPoints
        )
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: .dataMin(minimumSpan: 0.001, paddingFraction: 0.08),
            renderStyle: .lineOnly,
            sampleBudget: .menuBarHistory,
            miniPresentation: .menuBarHistory,
            primaryUnit: .percent
        )
    }

    static func fromMenuBarBars(
        _ values: [Double],
        color: Color
    ) -> PreparedTimeSeriesChartModel {
        let maxPoints = ChartSeriesPipeline.targetPointCount(for: nil, budget: .menuBarBars)
        let points = ChartSeriesPipeline.presentationIndexedPoints(
            values: values,
            key: "menubar.bars",
            label: "Bars",
            color: color,
            maxPoints: maxPoints
        )
        let peak = max(points.map(\.value).max() ?? 1, 1)
        return PreparedTimeSeriesChartModel(
            points: points,
            baseline: .zero(minimumSpan: 1, paddingFraction: 0.05),
            renderStyle: .baselineAreaLine,
            sampleBudget: .menuBarBars,
            miniPresentation: .menuBarBars,
            primaryUnit: .percent,
            fixedYDomain: 0 ... peak
        )
    }

    var hasRenderableCompareHistory: Bool {
        guard sampleBudget == .compareLine else { return !points.isEmpty }
        let grouped = Dictionary(grouping: points, by: \.seriesKey)
        return grouped.values.contains { $0.count > 1 }
    }

    private static func makeXDomain(from dates: [Date]) -> ClosedRange<Date> {
        let minDate = dates.min() ?? Date()
        let maxDate = dates.max() ?? minDate.addingTimeInterval(1)
        if minDate == maxDate {
            return minDate.addingTimeInterval(-30) ... maxDate.addingTimeInterval(30)
        }
        return minDate ... maxDate
    }
}

extension PreparedTimeSeriesChartModel {
    static func fromCPU(
        snapshot: CPUHistorySnapshot,
        chart: CPUPaneChart,
        smoothingAlpha: Double
    ) -> PreparedTimeSeriesChartModel {
        switch chart {
        case .usage:
            return fromCPUUsage(
                userHistory: snapshot.user,
                systemHistory: snapshot.system,
                smoothingAlpha: smoothingAlpha
            )
        case .loadAverage:
            return fromMetricHistory(
                series: [
                    ChartMetricSeriesDescriptor(key: "load.1", label: "1 Minute", color: DashboardPalette.cpuUserAccent, samples: snapshot.load1),
                    ChartMetricSeriesDescriptor(key: "load.5", label: "5 Minute", color: DashboardPalette.cpuSystemAccent, samples: snapshot.load5),
                    ChartMetricSeriesDescriptor(key: "load.15", label: "15 Minute", color: DashboardPalette.tertiaryText, samples: snapshot.load15)
                ],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
                smoothingAlpha: smoothingAlpha
            )
        case .gpu:
            return fromMetricHistory(
                series: [
                    ChartMetricSeriesDescriptor(key: "gpu.processor", label: "Processor", color: DashboardPalette.cpuUserAccent, samples: snapshot.gpuProcessor),
                    ChartMetricSeriesDescriptor(key: "gpu.memory", label: "Memory", color: DashboardPalette.networkChartAccent, samples: snapshot.gpuMemory)
                ],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
                smoothingAlpha: smoothingAlpha
            )
        case .framesPerSecond:
            return fromMetricHistory(
                series: [
                    ChartMetricSeriesDescriptor(key: "fps", label: "FPS", color: DashboardPalette.networkChartAccent, samples: snapshot.framesPerSecond)
                ],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
                smoothingAlpha: smoothingAlpha
            )
        }
    }

    static func fromMemory(
        snapshot: MemoryHistorySnapshot,
        chart: MemoryPaneChart,
        smoothingAlpha: Double
    ) -> PreparedTimeSeriesChartModel {
        switch chart {
        case .composition:
            return fromMemoryComposition(history: snapshot.composition, smoothingAlpha: smoothingAlpha)
        case .pressure:
            return fromMetricHistory(
                series: [
                    ChartMetricSeriesDescriptor(key: "memory.pressure", label: "Pressure", color: DashboardPalette.networkChartAccent, samples: snapshot.pressure)
                ],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
                smoothingAlpha: smoothingAlpha
            )
        case .swap:
            return fromMetricHistory(
                series: [
                    ChartMetricSeriesDescriptor(key: "memory.swap", label: "Swap Used", color: DashboardPalette.networkChartAccent, samples: snapshot.swap)
                ],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
                smoothingAlpha: smoothingAlpha
            )
        case .pages:
            return fromMetricHistory(
                series: [
                    ChartMetricSeriesDescriptor(key: "memory.pageIns", label: "Page Ins", color: DashboardPalette.networkChartAccent, samples: snapshot.pageIns),
                    ChartMetricSeriesDescriptor(key: "memory.pageOuts", label: "Page Outs", color: DashboardPalette.diskChartAccent, samples: snapshot.pageOuts)
                ],
                baseline: .zero(minimumSpan: 1, paddingFraction: 0.12),
                smoothingAlpha: smoothingAlpha
            )
        }
    }
}
