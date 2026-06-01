import PulseBarCore
import SwiftUI

struct DashboardMiniChart: View {
    let model: PreparedTimeSeriesChartModel
    var areaOpacity: Double = DashboardChartTheme.defaultAreaOpacity
    var lineColor: Color?
    var fillColor: Color?
    var positiveColor: Color = DashboardPalette.networkChartAccent
    var negativeColor: Color = DashboardPalette.diskChartAccent
    var showsPlotBackground: Bool = true
    var plotCornerRadius: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            switch model.miniPresentation ?? .timeSeries {
            case .menuBarBars:
                menuBarBars(in: proxy.size)
            case .menuBarHistory:
                menuBarHistory(in: proxy.size)
            case .bidirectionalBars:
                bidirectionalBars(in: proxy.size)
            case .indexedSparkline:
                indexSparkline(in: proxy.size)
            case .timeSeries:
                timeSeriesCanvas(in: proxy.size)
            }
        }
    }

    @ViewBuilder
    private func indexSparkline(in size: CGSize) -> some View {
        let values = model.points.map(\.value)
        if values.count < 2 {
            placeholder(in: size)
        } else {
            let accent = lineColor ?? model.points.first?.color ?? DashboardPalette.cpuChartAccent
            let fill = fillColor ?? DashboardChartTheme.areaFillColor(accent, opacity: areaOpacity)

            ZStack {
                if showsPlotBackground {
                    DashboardChartTheme.miniPlotBackground(cornerRadius: plotCornerRadius)
                }

                Canvas(rendersAsynchronously: true) { context, canvasSize in
                    let points = ChartPlotGeometry.indexScaledPoints(values: values, size: canvasSize)
                    var area = Path()
                    guard let first = points.first, let last = points.last else { return }
                    area.move(to: CGPoint(x: first.x, y: canvasSize.height))
                    for point in points {
                        area.addLine(to: point)
                    }
                    area.addLine(to: CGPoint(x: last.x, y: canvasSize.height))
                    area.closeSubpath()
                    context.fill(area, with: .color(fill))

                    var line = Path()
                    line.move(to: first)
                    for point in points.dropFirst() {
                        line.addLine(to: point)
                    }
                    context.stroke(
                        line,
                        with: .color(accent),
                        style: DashboardChartTheme.seriesStroke(accent, lineWidth: 2.25)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func timeSeriesCanvas(in size: CGSize) -> some View {
        if model.points.count < 2 {
            placeholder(in: size)
        } else {
            let xDomain = model.scale.xDomain ?? model.fallbackXDomain
            let yDomain = model.fixedYDomain ?? model.scale.yDomain
            let segments = ChartRenderSemantics.continuitySegments(for: model.renderStyle, points: model.points)

            ZStack {
                if showsPlotBackground {
                    DashboardChartTheme.miniPlotBackground(cornerRadius: plotCornerRadius)
                }

                Canvas(rendersAsynchronously: true) { context, canvasSize in
                    ChartPlotGeometry.drawGapStrips(
                        timestamps: model.points.map(\.timestamp),
                        xDomain: xDomain,
                        in: &context,
                        size: canvasSize
                    )

                    switch model.renderStyle {
                    case .stackedArea:
                        drawStackedArea(segments: segments, xDomain: xDomain, yDomain: yDomain, context: &context, size: canvasSize)
                    case .baselineAreaLine:
                        drawBaselineSeries(segments: segments, xDomain: xDomain, yDomain: yDomain, context: &context, size: canvasSize)
                    case .lineOnly:
                        drawLineSeries(segments: segments, xDomain: xDomain, yDomain: yDomain, context: &context, size: canvasSize)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menuBarBars(in size: CGSize) -> some View {
        let values = barValues
        let tint = lineColor ?? model.points.first?.color ?? DashboardPalette.cpuChartAccent
        if values.count < 2 {
            Capsule()
                .fill(tint.opacity(0.2))
        } else {
            let maxValue = max(values.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(tint)
                        .frame(height: max(2, CGFloat(value / maxValue) * size.height))
                }
            }
        }
    }

    @ViewBuilder
    private func menuBarHistory(in size: CGSize) -> some View {
        let tint = lineColor ?? model.points.first?.color ?? DashboardPalette.cpuChartAccent
        if model.points.count < 2 {
            Capsule()
                .fill(tint.opacity(0.2))
        } else {
            let path = ChartPlotGeometry.linePath(for: model.points.map(\.value), size: size)
            path
                .stroke(tint, style: DashboardChartTheme.seriesStroke(tint, lineWidth: 1.6))
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
        }
    }

    @ViewBuilder
    private func bidirectionalBars(in size: CGSize) -> some View {
        let positive = model.positiveValues
        let negative = model.negativeValues
        let count = max(positive.count, negative.count)
        let maxValue = max((positive + negative).max() ?? 1, 1)

        ZStack(alignment: .center) {
            if showsPlotBackground {
                RoundedRectangle(cornerRadius: plotCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DashboardPalette.chromeFill, DashboardPalette.sectionFill],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Rectangle()
                .fill(DashboardPalette.chromeBorder)
                .frame(height: 1)

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    let upValue = index < positive.count ? positive[index] : 0
                    let downValue = index < negative.count ? negative[index] : 0

                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(positiveColor)
                            .frame(height: max(1, CGFloat(upValue / maxValue) * ((size.height / 2) - 6)))
                        Spacer().frame(height: 1)
                        Rectangle()
                            .fill(negativeColor)
                            .frame(height: max(1, CGFloat(downValue / maxValue) * ((size.height / 2) - 6)))
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func placeholder(in size: CGSize) -> some View {
        let accent = lineColor ?? model.points.first?.color ?? DashboardPalette.cpuChartAccent
        RoundedRectangle(cornerRadius: plotCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [DashboardPalette.chromeFill, DashboardPalette.sectionFill],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: plotCornerRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.2), lineWidth: 1)
            }
    }

    private var barValues: [Double] {
        model.points.map(\.value)
    }

    private var resolvedStackedAreaOpacity: Double {
        DashboardChartTheme.resolvedAreaOpacity(for: .stackedArea, baseOpacity: areaOpacity)
    }

    private func drawStackedArea(
        segments: [[TimeSeriesChartPoint]],
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let timelineSegments = segments
            .filter { $0.count >= 2 }
            .sorted { ($0.first?.timestamp ?? .distantPast) < ($1.first?.timestamp ?? .distantPast) }

        for segment in timelineSegments {
            let grouped = Dictionary(grouping: segment, by: \.seriesKey)
            let seriesKeys = grouped.keys.sorted {
                ChartRenderSemantics.layerRank(for: $0) < ChartRenderSemantics.layerRank(for: $1)
            }

            var cumulativeByTimestamp: [Date: Double] = [:]
            for seriesKey in seriesKeys {
                let seriesPoints = (grouped[seriesKey] ?? []).sorted { $0.timestamp < $1.timestamp }
                guard seriesPoints.count >= 2 else { continue }

                drawStackedLayer(
                    segment: seriesPoints,
                    topValue: { point in
                        (cumulativeByTimestamp[point.timestamp] ?? yDomain.lowerBound) + point.value
                    },
                    baselineValue: { point in
                        cumulativeByTimestamp[point.timestamp] ?? yDomain.lowerBound
                    },
                    xDomain: xDomain,
                    yDomain: yDomain,
                    context: &context,
                    size: size
                )

                for point in seriesPoints {
                    let baseline = cumulativeByTimestamp[point.timestamp] ?? yDomain.lowerBound
                    cumulativeByTimestamp[point.timestamp] = baseline + point.value
                }
            }
        }
    }

    private func drawStackedLayer(
        segment: [TimeSeriesChartPoint],
        topValue: (TimeSeriesChartPoint) -> Double,
        baselineValue: (TimeSeriesChartPoint) -> Double,
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let color = segment.first?.color ?? DashboardPalette.cpuChartAccent
        let area = stackedAreaPath(
            points: segment,
            topValue: topValue,
            baselineValue: baselineValue,
            xDomain: xDomain,
            yDomain: yDomain,
            size: size
        )
        context.fill(area, with: .color(DashboardChartTheme.areaFillStackedColor(color, opacity: resolvedStackedAreaOpacity)))
        context.stroke(
            stackedLinePath(
                points: segment,
                value: topValue,
                xDomain: xDomain,
                yDomain: yDomain,
                size: size
            ),
            with: .color(DashboardChartTheme.seriesLineColor(color)),
            lineWidth: DashboardChartTheme.compactLineWidth
        )
    }

    private func stackedAreaPath(
        points: [TimeSeriesChartPoint],
        topValue: (TimeSeriesChartPoint) -> Double,
        baselineValue: (TimeSeriesChartPoint) -> Double,
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>,
        size: CGSize
    ) -> Path {
        guard let first = points.first, let last = points.last else { return Path() }
        var path = Path()
        path.move(to: CGPoint(
            x: ChartPlotGeometry.xPosition(for: first.timestamp, domain: xDomain, width: size.width),
            y: ChartPlotGeometry.yPosition(for: topValue(first), domain: yDomain, height: size.height)
        ))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(
                x: ChartPlotGeometry.xPosition(for: point.timestamp, domain: xDomain, width: size.width),
                y: ChartPlotGeometry.yPosition(for: topValue(point), domain: yDomain, height: size.height)
            ))
        }
        path.addLine(to: CGPoint(
            x: ChartPlotGeometry.xPosition(for: last.timestamp, domain: xDomain, width: size.width),
            y: ChartPlotGeometry.yPosition(for: baselineValue(last), domain: yDomain, height: size.height)
        ))
        for point in points.dropLast().reversed() {
            path.addLine(to: CGPoint(
                x: ChartPlotGeometry.xPosition(for: point.timestamp, domain: xDomain, width: size.width),
                y: ChartPlotGeometry.yPosition(for: baselineValue(point), domain: yDomain, height: size.height)
            ))
        }
        path.closeSubpath()
        return path
    }

    private func stackedLinePath(
        points: [TimeSeriesChartPoint],
        value: (TimeSeriesChartPoint) -> Double,
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>,
        size: CGSize
    ) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(to: CGPoint(
            x: ChartPlotGeometry.xPosition(for: first.timestamp, domain: xDomain, width: size.width),
            y: ChartPlotGeometry.yPosition(for: value(first), domain: yDomain, height: size.height)
        ))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(
                x: ChartPlotGeometry.xPosition(for: point.timestamp, domain: xDomain, width: size.width),
                y: ChartPlotGeometry.yPosition(for: value(point), domain: yDomain, height: size.height)
            ))
        }
        return path
    }

    private func drawBaselineSeries(
        segments: [[TimeSeriesChartPoint]],
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let baseline = model.scale.areaBaseline
        let orderedSegments = segments
            .filter { $0.count >= 2 }
            .sorted(by: ChartRenderSemantics.compareSegmentsForDrawOrder)

        for segment in orderedSegments {
            let color = segment.first?.color ?? DashboardPalette.cpuChartAccent
            let area = ChartPlotGeometry.areaPath(
                points: segment,
                baseline: baseline,
                xDomain: xDomain,
                yDomain: yDomain,
                size: size
            )
            context.fill(area, with: .color((fillColor ?? DashboardChartTheme.areaFillColor(color, opacity: areaOpacity))))
            context.stroke(
                ChartPlotGeometry.linePath(for: segment, xDomain: xDomain, yDomain: yDomain, size: size),
                with: .color(lineColor ?? DashboardChartTheme.seriesLineColor(color)),
                lineWidth: DashboardChartTheme.compactLineWidth
            )
        }
    }

    private func drawLineSeries(
        segments: [[TimeSeriesChartPoint]],
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let orderedSegments = segments
            .filter { $0.count >= 2 }
            .sorted(by: ChartRenderSemantics.compareSegmentsForDrawOrder)

        for segment in orderedSegments {
            let color = segment.first?.color ?? DashboardPalette.cpuChartAccent
            context.stroke(
                ChartPlotGeometry.linePath(for: segment, xDomain: xDomain, yDomain: yDomain, size: size),
                with: .color(lineColor ?? DashboardChartTheme.seriesLineColor(color)),
                lineWidth: DashboardChartTheme.compactLineWidth
            )
        }
    }
}
