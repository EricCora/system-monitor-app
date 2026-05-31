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
        "\(seriesKey)-\(continuityKey)-\(timestamp.timeIntervalSince1970)"
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

struct ChartDisplayOptions: Equatable {
    var showsMinorGrid: Bool = false
    var smoothingAlpha: Double = 1.0
    var areaOpacity: Double?
    var plotCornerRadius: CGFloat?

    var resolvedAreaOpacity: Double {
        areaOpacity ?? DashboardChartTheme.defaultAreaOpacity
    }

    var resolvedPlotCornerRadius: CGFloat {
        plotCornerRadius ?? DashboardChartTheme.defaultPlotCornerRadius
    }

    var normalizedSmoothingAlpha: Double {
        guard smoothingAlpha.isFinite else { return 1.0 }
        return min(max(smoothingAlpha, 0.05), 1.0)
    }
}

private struct DashboardChartDisplayOptionsKey: EnvironmentKey {
    static let defaultValue = ChartDisplayOptions()
}

extension EnvironmentValues {
    var dashboardChartDisplayOptions: ChartDisplayOptions {
        get { self[DashboardChartDisplayOptionsKey.self] }
        set { self[DashboardChartDisplayOptionsKey.self] = newValue }
    }
}

enum DashboardChartStyle {
    static let xAxisStartPadding: CGFloat = 34
    static let xAxisEndPadding: CGFloat = 48

    static func visibleXDomain(
        dataDomain: ClosedRange<Date>?,
        window: ChartWindow,
        now: Date = Date()
    ) -> ClosedRange<Date> {
        let endDate = max(dataDomain?.upperBound ?? now, now)
        return endDate.addingTimeInterval(-window.seconds)...endDate
    }

    @AxisContentBuilder
    static func timeXAxis(showsMinorGrid: Bool = false) -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 3)) { value in
            AxisGridLine()
                .foregroundStyle(DashboardPalette.chartGrid.opacity(DashboardChartTheme.gridOpacity))
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
        showsMinorGrid: Bool = false,
        label: @escaping (Double) -> String
    ) -> some AxisContent {
        if let values {
            AxisMarks(preset: .aligned, position: .leading, values: values) { value in
                AxisGridLine()
                    .foregroundStyle(DashboardPalette.chartGrid.opacity(DashboardChartTheme.gridOpacity))
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
                    .foregroundStyle(DashboardPalette.chartGrid.opacity(DashboardChartTheme.gridOpacity))
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

struct ChartHoverOverlay: View {
    let proxy: ChartProxy
    let geometry: GeometryProxy
    @Binding var hoveredDate: Date?

    var body: some View {
        let plotFrame = geometry[proxy.plotAreaFrame]

        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
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
        let minimumDistance: CGFloat = 12
        guard horizontalDistance >= minimumDistance || verticalDistance >= minimumDistance else {
            return (false, false)
        }

        guard zoomMode == .bothAxes else {
            return (horizontalDistance >= minimumDistance, false)
        }

        let directionalBias: CGFloat = 1.35

        if horizontalDistance >= minimumDistance && verticalDistance < minimumDistance {
            return (true, false)
        }

        if verticalDistance >= minimumDistance && horizontalDistance < minimumDistance {
            return (false, true)
        }

        if horizontalDistance > (verticalDistance * directionalBias) {
            return (true, false)
        }

        if verticalDistance > (horizontalDistance * directionalBias) {
            return (false, true)
        }

        return (true, true)
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
    var plotFrame: CGRect? = nil
    var cornerRadius: CGFloat = 14

    var body: some View {
        GeometryReader { _ in
            if let selectionRect,
               let plotFrame,
               let clippedRect = Self.clippedSelectionRect(selectionRect, to: plotFrame) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .frame(width: plotFrame.width, height: plotFrame.height)
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(
                                Rectangle()
                                    .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                            .frame(width: clippedRect.width, height: clippedRect.height)
                            .offset(
                                x: clippedRect.minX - plotFrame.minX,
                                y: clippedRect.minY - plotFrame.minY
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .position(
                        x: plotFrame.midX,
                        y: plotFrame.midY
                    )
            }
        }
        .allowsHitTesting(false)
    }

    static func clippedSelectionRect(_ selectionRect: CGRect, to plotFrame: CGRect) -> CGRect? {
        let clippedRect = selectionRect.intersection(plotFrame)
        guard !clippedRect.isNull,
              clippedRect.width > 0,
              clippedRect.height > 0 else {
            return nil
        }
        return clippedRect
    }
}
