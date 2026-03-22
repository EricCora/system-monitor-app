import Charts
import PulseBarCore
import SwiftUI

struct TimeSeriesChartPoint: Identifiable {
    let timestamp: Date
    let value: Double
    let seriesKey: String
    let seriesLabel: String
    let continuityKey: String
    let color: Color

    var id: String {
        "\(continuityKey)-\(timestamp.timeIntervalSince1970)"
    }
}

enum ChartBaselinePolicy: Equatable {
    case zero(minimumSpan: Double = 1, paddingFraction: Double = 0.12)
    case dataMin(minimumSpan: Double = 1, paddingFraction: Double = 0.12)
    case fixed(ClosedRange<Double>)
}

struct ChartScale: Equatable {
    let xDomain: ClosedRange<Date>?
    let yDomain: ClosedRange<Double>
    let areaBaseline: Double

    func renderedAreaBaseline(viewport: ChartViewport) -> Double {
        viewport.yDomain?.lowerBound ?? areaBaseline
    }
}

struct ChartViewport: Equatable {
    var xDomain: ClosedRange<Date>?
    var yDomain: ClosedRange<Double>?

    var isZoomed: Bool {
        xDomain != nil || yDomain != nil
    }

    mutating func apply(xDomain: ClosedRange<Date>?, yDomain: ClosedRange<Double>?) {
        self.xDomain = xDomain
        self.yDomain = yDomain
    }

    mutating func reset() {
        xDomain = nil
        yDomain = nil
    }
}

struct ChartMetricSeriesDescriptor<Sample> {
    let key: String
    let label: String
    let color: Color
    let samples: [Sample]

    init(key: String, label: String, color: Color, samples: [Sample]) {
        self.key = key
        self.label = label
        self.color = color
        self.samples = samples
    }
}

enum ChartSeriesPipeline {
    static func metricSamples(
        _ samples: [MetricSample],
        key: String,
        label: String,
        color: Color
    ) -> [TimeSeriesChartPoint] {
        metricSamples(series: [
            ChartMetricSeriesDescriptor(key: key, label: label, color: color, samples: samples)
        ])
    }

    static func metricSamples(
        series: [ChartMetricSeriesDescriptor<MetricSample>]
    ) -> [TimeSeriesChartPoint] {
        flatten(series: series) { entry in
            segmented(
                sanitize(entry.samples, timestamp: \.timestamp),
                seriesKey: entry.key,
                timestamp: \.timestamp
            ) { sample, continuityKey in
                TimeSeriesChartPoint(
                    timestamp: sample.timestamp,
                    value: sample.value,
                    seriesKey: entry.key,
                    seriesLabel: entry.label,
                    continuityKey: continuityKey,
                    color: entry.color
                )
            }
        }
    }

    static func metricHistory(
        series: [ChartMetricSeriesDescriptor<MetricHistoryPoint>]
    ) -> [TimeSeriesChartPoint] {
        flatten(series: series) { entry in
            segmented(
                sanitize(entry.samples, timestamp: \.timestamp),
                seriesKey: entry.key,
                timestamp: \.timestamp
            ) { point, continuityKey in
                TimeSeriesChartPoint(
                    timestamp: point.timestamp,
                    value: point.value,
                    seriesKey: entry.key,
                    seriesLabel: entry.label,
                    continuityKey: continuityKey,
                    color: entry.color
                )
            }
        }
    }

    static func temperatureHistory(
        _ points: [TemperatureHistoryPoint],
        key: String,
        label: String,
        color: Color
    ) -> [TimeSeriesChartPoint] {
        flatten(
            series: [ChartMetricSeriesDescriptor(key: key, label: label, color: color, samples: points)]
        ) { entry in
            segmented(
                sanitize(entry.samples, timestamp: \.timestamp),
                seriesKey: entry.key,
                timestamp: \.timestamp
            ) { point, continuityKey in
                TimeSeriesChartPoint(
                    timestamp: point.timestamp,
                    value: point.value,
                    seriesKey: entry.key,
                    seriesLabel: entry.label,
                    continuityKey: continuityKey,
                    color: entry.color
                )
            }
        }
    }

    static func sanitize<T>(_ values: [T], timestamp: KeyPath<T, Date>) -> [T] {
        var latestByTimestamp: [Date: T] = [:]
        for value in values {
            latestByTimestamp[value[keyPath: timestamp]] = value
        }
        return latestByTimestamp.values.sorted {
            $0[keyPath: timestamp] < $1[keyPath: timestamp]
        }
    }

    static func continuityKeys<Sample>(
        for values: [Sample],
        seriesKey: String,
        timestamp: KeyPath<Sample, Date>
    ) -> [String] {
        guard !values.isEmpty else { return [] }

        let cadence = inferredCadence(for: values, timestamp: timestamp)
        let gapThreshold = max(cadence * 1.9, cadence + 1)
        var segmentIndex = 0
        var previousTimestamp: Date?

        return values.map { value in
            let currentTimestamp = value[keyPath: timestamp]
            if let previousTimestamp,
               currentTimestamp.timeIntervalSince(previousTimestamp) > gapThreshold {
                segmentIndex += 1
            }
            previousTimestamp = currentTimestamp
            return "\(seriesKey)#\(segmentIndex)"
        }
    }

    static func scale(
        for points: [TimeSeriesChartPoint],
        baseline: ChartBaselinePolicy
    ) -> ChartScale {
        switch baseline {
        case .fixed(let range):
            return ChartScale(
                xDomain: xDomain(for: points),
                yDomain: range,
                areaBaseline: range.lowerBound
            )
        case .zero(let minimumSpan, let paddingFraction):
            let domain = paddedDomain(
                for: points.map(\.value),
                minimumSpan: minimumSpan,
                paddingFraction: paddingFraction,
                includeZero: true
            )
            return ChartScale(
                xDomain: xDomain(for: points),
                yDomain: domain,
                areaBaseline: 0
            )
        case .dataMin(let minimumSpan, let paddingFraction):
            let domain = paddedDomain(
                for: points.map(\.value),
                minimumSpan: minimumSpan,
                paddingFraction: paddingFraction,
                includeZero: false
            )
            return ChartScale(
                xDomain: xDomain(for: points),
                yDomain: domain,
                areaBaseline: domain.lowerBound
            )
        }
    }

    static func colorScaleDomain(for points: [TimeSeriesChartPoint]) -> [String] {
        orderedSeriesValues(for: points, value: \.seriesKey)
    }

    static func colorScaleRange(for points: [TimeSeriesChartPoint]) -> [Color] {
        var colors: [Color] = []
        var seen = Set<String>()
        for point in points {
            if seen.insert(point.seriesKey).inserted {
                colors.append(point.color)
            }
        }
        return colors
    }

    private static func flatten<Input>(
        series: [Input],
        transform: (Input) -> [TimeSeriesChartPoint]
    ) -> [TimeSeriesChartPoint] {
        series
            .flatMap(transform)
            .sorted {
                if $0.timestamp == $1.timestamp {
                    return $0.seriesKey < $1.seriesKey
                }
                return $0.timestamp < $1.timestamp
            }
    }

    private static func orderedSeriesValues<Value: Hashable>(
        for points: [TimeSeriesChartPoint],
        value: KeyPath<TimeSeriesChartPoint, Value>
    ) -> [Value] {
        var output: [Value] = []
        var seen = Set<Value>()
        for point in points {
            let item = point[keyPath: value]
            if seen.insert(item).inserted {
                output.append(item)
            }
        }
        return output
    }

    private static func segmented<Sample>(
        _ values: [Sample],
        seriesKey: String,
        timestamp: KeyPath<Sample, Date>,
        map: (Sample, String) -> TimeSeriesChartPoint
    ) -> [TimeSeriesChartPoint] {
        guard !values.isEmpty else { return [] }
        let continuityKeys = continuityKeys(for: values, seriesKey: seriesKey, timestamp: timestamp)
        return zip(values, continuityKeys).map(map)
    }

    private static func paddedDomain(
        for values: [Double],
        minimumSpan: Double,
        paddingFraction: Double,
        includeZero: Bool
    ) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        let lowerBound: Double
        let upperBound: Double

        if minValue == maxValue {
            let delta = max(minimumSpan, abs(minValue * 0.1))
            lowerBound = minValue - delta
            upperBound = maxValue + delta
        } else {
            let padding = max(minimumSpan * 0.1, (maxValue - minValue) * paddingFraction)
            lowerBound = minValue - padding
            upperBound = maxValue + padding
        }

        if includeZero {
            return min(0, lowerBound)...max(upperBound, minimumSpan)
        }
        return lowerBound...upperBound
    }

    private static func xDomain(for points: [TimeSeriesChartPoint]) -> ClosedRange<Date>? {
        guard let minDate = points.map(\.timestamp).min(),
              let maxDate = points.map(\.timestamp).max() else {
            return nil
        }
        if minDate == maxDate {
            let expanded = minDate.addingTimeInterval(-30)...maxDate.addingTimeInterval(30)
            return expanded
        }
        return minDate...maxDate
    }

    private static func inferredCadence<Sample>(
        for values: [Sample],
        timestamp: KeyPath<Sample, Date>
    ) -> TimeInterval {
        let deltas = zip(values, values.dropFirst()).compactMap { previous, current -> TimeInterval? in
            let delta = current[keyPath: timestamp].timeIntervalSince(previous[keyPath: timestamp])
            return delta > 0 ? delta : nil
        }
        guard !deltas.isEmpty else { return 1 }
        let sorted = deltas.sorted()
        return sorted[sorted.count / 2]
    }
}

enum DashboardChartStyle {
    @AxisContentBuilder
    static func timeXAxis() -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 3)) { value in
            AxisGridLine()
                .foregroundStyle(DashboardPalette.chartGrid.opacity(0.42))
            AxisTick()
                .foregroundStyle(DashboardPalette.chartAxisText)
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(DashboardPalette.chartAxisText)
                }
            }
        }
    }

    @AxisContentBuilder
    static func leadingNumericAxis(
        values: [Double]? = nil,
        label: @escaping (Double) -> String
    ) -> some AxisContent {
        if let values {
            AxisMarks(preset: .aligned, position: .leading, values: values) { value in
                AxisGridLine()
                    .foregroundStyle(DashboardPalette.chartGrid)
                AxisTick()
                    .foregroundStyle(DashboardPalette.chartAxisText)
                AxisValueLabel {
                    if let numericValue = value.as(Double.self) {
                        Text(label(numericValue))
                            .foregroundStyle(DashboardPalette.chartAxisStrong)
                    }
                }
            }
        } else {
            AxisMarks(preset: .aligned, position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(DashboardPalette.chartGrid)
                AxisTick()
                    .foregroundStyle(DashboardPalette.chartAxisText)
                AxisValueLabel {
                    if let numericValue = value.as(Double.self) {
                        Text(label(numericValue))
                            .foregroundStyle(DashboardPalette.chartAxisStrong)
                    }
                }
            }
        }
    }

    static func valueLabel(
        for value: Double,
        unit: MetricUnit?,
        throughputUnit: ThroughputDisplayUnit
    ) -> String {
        guard let unit else {
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
            return String(format: "%.1f", value)
        }
    }
}

struct DetachedChartInteractionOverlay: View {
    enum ZoomMode {
        case horizontal
        case bothAxes
    }

    let proxy: ChartProxy
    let geometry: GeometryProxy
    var paneController: DetachedMetricsPaneController? = nil
    var zoomMode: ZoomMode = .horizontal
    @Binding var hoveredDate: Date?
    @Binding var viewport: ChartViewport
    @Binding var selectionRect: CGRect?

    @State private var interactionStarted = false

    var body: some View {
        let plotFrame = geometry[proxy.plotAreaFrame]

        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        beginInteractionIfNeeded()
                        let start = clamped(value.startLocation, to: plotFrame)
                        let current = clamped(value.location, to: plotFrame)
                        let horizontalDistance = abs(current.x - start.x)
                        let verticalDistance = abs(current.y - start.y)
                        guard horizontalDistance >= 3 || verticalDistance >= 3 else {
                            selectionRect = nil
                            hoveredDate = nil
                            return
                        }
                        selectionRect = Self.selectionRect(
                            for: start,
                            current: current,
                            plotFrame: plotFrame,
                            zoomMode: zoomMode
                        )
                        hoveredDate = nil
                    }
                    .onEnded { value in
                        defer {
                            selectionRect = nil
                            endInteractionIfNeeded()
                        }
                        let start = clamped(value.startLocation, to: plotFrame)
                        let end = clamped(value.location, to: plotFrame)
                        let horizontalDistance = abs(end.x - start.x)
                        let verticalDistance = abs(end.y - start.y)
                        let (shouldZoomX, shouldZoomY) = Self.zoomDecision(
                            horizontalDistance: horizontalDistance,
                            verticalDistance: verticalDistance,
                            zoomMode: zoomMode
                        )
                        guard shouldZoomX || shouldZoomY else { return }

                        let localStartX = start.x - plotFrame.minX
                        let localEndX = end.x - plotFrame.minX
                        let localStartY = start.y - plotFrame.minY
                        let localEndY = end.y - plotFrame.minY

                        let xDomain: ClosedRange<Date>?
                        if shouldZoomX,
                           let x1: Date = proxy.value(atX: localStartX, as: Date.self),
                           let x2: Date = proxy.value(atX: localEndX, as: Date.self) {
                            xDomain = min(x1, x2)...max(x1, x2)
                        } else {
                            xDomain = viewport.xDomain
                        }

                        let yDomain: ClosedRange<Double>?
                        if shouldZoomY,
                           let y1: Double = proxy.value(atY: localStartY, as: Double.self),
                           let y2: Double = proxy.value(atY: localEndY, as: Double.self) {
                            yDomain = min(y1, y2)...max(y1, y2)
                        } else {
                            yDomain = viewport.yDomain
                        }

                        viewport.apply(xDomain: xDomain, yDomain: yDomain)
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        beginInteractionIfNeeded()
                        viewport.reset()
                        selectionRect = nil
                        hoveredDate = nil
                        endInteractionIfNeeded()
                    }
            )
            .onContinuousHover { phase in
                guard selectionRect == nil else { return }
                switch phase {
                case .active(let location):
                    let xPosition = location.x - plotFrame.origin.x
                    guard xPosition >= 0,
                          xPosition <= proxy.plotAreaSize.width,
                          let date: Date = proxy.value(atX: xPosition, as: Date.self) else {
                        hoveredDate = nil
                        return
                    }
                    hoveredDate = date
                case .ended:
                    hoveredDate = nil
                }
            }
            .onDisappear {
                selectionRect = nil
                endInteractionIfNeeded()
            }
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    static func zoomDecision(
        horizontalDistance: CGFloat,
        verticalDistance: CGFloat,
        zoomMode: ZoomMode
    ) -> (shouldZoomX: Bool, shouldZoomY: Bool) {
        let shouldZoomX = horizontalDistance >= 12
        let shouldZoomY = zoomMode == .bothAxes && verticalDistance >= 12
        return (shouldZoomX, shouldZoomY)
    }

    static func selectionRect(
        for start: CGPoint,
        current: CGPoint,
        plotFrame: CGRect,
        zoomMode: ZoomMode
    ) -> CGRect {
        switch zoomMode {
        case .horizontal:
            return CGRect(
                x: min(start.x, current.x),
                y: plotFrame.minY,
                width: abs(current.x - start.x),
                height: plotFrame.height
            )
        case .bothAxes:
            return CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
        }
    }

    private func beginInteractionIfNeeded() {
        guard let paneController, !interactionStarted else { return }
        interactionStarted = true
        paneController.beginPaneInteraction()
    }

    private func endInteractionIfNeeded() {
        guard let paneController, interactionStarted else { return }
        interactionStarted = false
        paneController.endPaneInteraction()
    }
}

struct ChartZoomSelectionOverlay: View {
    let selectionRect: CGRect?

    var body: some View {
        GeometryReader { _ in
            if let selectionRect {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(
                        Rectangle()
                            .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(
                        x: selectionRect.midX,
                        y: selectionRect.midY
                    )
            }
        }
        .allowsHitTesting(false)
    }
}
