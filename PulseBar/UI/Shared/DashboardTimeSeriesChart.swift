import Charts
import PulseBarCore
import SwiftUI

struct DashboardTimeSeriesChart: View {
    let model: PreparedTimeSeriesChartModel
    var window: ChartWindow?
    var areaOpacity: Double = DashboardChartTheme.defaultAreaOpacity
    var plotCornerRadius: CGFloat = DashboardChartTheme.defaultPlotCornerRadius
    var height: CGFloat = 300
    var throughputUnit: ThroughputDisplayUnit = .bytesPerSecond
    var paneController: DetachedMetricsPaneController?
    var zoomMode: DetachedChartInteractionOverlay.ZoomMode = .bothAxes
    var hiddenLegendIDs: Set<String> = []
    var yAxisValues: [Double]?
    var yAxisLabel: ((Double) -> String)?
    @Binding var hoveredDate: Date?
    @Binding var viewport: ChartViewport
    @Binding var zoomSelectionRect: CGRect?

    @Environment(\.dashboardChartDisplayOptions) private var displayOptions

    private var resolvedAreaOpacity: Double {
        displayOptions.resolvedAreaOpacity
    }

    private func fillOpacity(for renderStyle: DashboardTimeSeriesRenderStyle) -> Double {
        DashboardChartTheme.resolvedAreaOpacity(for: renderStyle, baseOpacity: resolvedAreaOpacity)
    }

    private var resolvedPlotCornerRadius: CGFloat {
        displayOptions.plotCornerRadius ?? plotCornerRadius
    }

    private var showsMinorGrid: Bool {
        displayOptions.showsMinorGrid
    }

    var body: some View {
        Chart {
            ForEach(renderGroups) { group in
                ForEach(Array(group.segments.enumerated()), id: \.offset) { _, segment in
                    ForEach(segment) { point in
                        chartMarks(for: point)
                    }
                }
            }

            if let hoveredDate {
                RuleMark(x: .value("Hover", hoveredDate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(DashboardPalette.chartRule)
            }
        }
        .chartXScale(domain: resolvedXDomain)
        .chartYScale(domain: resolvedYDomain)
        .chartYAxis {
            if let yAxisValues, let yAxisLabel {
                DashboardChartStyle.leadingNumericAxis(
                    values: yAxisValues,
                    showsMinorGrid: false
                ) { value in
                    yAxisLabel(value)
                }
            } else if model.primaryUnit == .percent, model.fixedYDomain == (0 ... 100) {
                DashboardChartStyle.leadingNumericAxis(
                    values: [0, 25, 50, 75, 100],
                    showsMinorGrid: false
                ) { value in
                    String(format: "%.0f%%", value)
                }
            } else {
                DashboardChartStyle.leadingNumericAxis(showsMinorGrid: false) { value in
                    defaultYAxisLabel(value)
                }
            }
        }
        .chartXAxis {
            DashboardChartStyle.timeXAxis(showsMinorGrid: false)
        }
        .chartXScale(range: .plotDimension(startPadding: DashboardChartStyle.xAxisStartPadding, endPadding: DashboardChartStyle.xAxisEndPadding))
        .chartPlotStyle { plot in
            plot
                .background(
                    DashboardPalette.chartPlotBackground(
                        cornerRadius: resolvedPlotCornerRadius,
                        showsMinorGrid: showsMinorGrid
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: resolvedPlotCornerRadius, style: .continuous))
        }
        .id("minor-grid-\(showsMinorGrid)")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plotFrame = geometry[proxy.plotAreaFrame]

                ZStack(alignment: .topLeading) {
                    if let paneController {
                        DetachedChartInteractionOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            paneController: paneController,
                            zoomMode: zoomMode,
                            hoveredDate: $hoveredDate,
                            viewport: $viewport,
                            selectionRect: $zoomSelectionRect
                        )
                    } else {
                        ChartHoverOverlay(
                            proxy: proxy,
                            geometry: geometry,
                            hoveredDate: $hoveredDate
                        )
                    }

                    ChartZoomSelectionOverlay(
                        selectionRect: zoomSelectionRect,
                        plotFrame: plotFrame,
                        cornerRadius: resolvedPlotCornerRadius
                    )

                    ChartGapStripOverlay(
                        timestamps: visiblePoints.map(\.timestamp),
                        xDomain: resolvedXDomain,
                        plotFrame: plotFrame
                    )
                }
            }
        }
        .frame(height: height)
    }

    @ChartContentBuilder
    private func chartMarks(for point: TimeSeriesChartPoint) -> some ChartContent {
        let seriesIdentity = ChartRenderSemantics.chartSeriesIdentity(for: point)
        switch model.renderStyle {
        case .stackedArea:
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value),
                series: .value("Series", seriesIdentity),
                stacking: .standard
            )
            .foregroundStyle(DashboardChartTheme.areaFillStacked(point.color, opacity: fillOpacity(for: .stackedArea)))
            .interpolationMethod(.linear)

        case .baselineAreaLine:
            AreaMark(
                x: .value("Time", point.timestamp),
                yStart: .value("Baseline", model.scale.renderedAreaBaseline(viewport: viewport)),
                yEnd: .value("Value", point.value),
                series: .value("Series", seriesIdentity)
            )
            .foregroundStyle(DashboardChartTheme.areaFill(point.color, opacity: fillOpacity(for: .baselineAreaLine)))
            .interpolationMethod(.linear)

            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value),
                series: .value("Series", seriesIdentity)
            )
            .foregroundStyle(DashboardChartTheme.seriesLineColor(point.color))
            .lineStyle(DashboardChartTheme.seriesStroke(point.color))
            .interpolationMethod(.linear)

        case .lineOnly:
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Value", point.value),
                series: .value("Series", seriesIdentity)
            )
            .foregroundStyle(DashboardChartTheme.seriesLineColor(point.color))
            .lineStyle(DashboardChartTheme.seriesStroke(point.color))
            .interpolationMethod(.linear)
        }
    }

    private var visiblePoints: [TimeSeriesChartPoint] {
        model.points.filter { !hiddenLegendIDs.contains($0.seriesKey) }
    }

    private var renderGroups: [ChartRenderSemantics.RenderGroup] {
        ChartRenderSemantics.renderGroups(for: model.renderStyle, points: visiblePoints)
    }

    private var resolvedXDomain: ClosedRange<Date> {
        if let xDomain = viewport.xDomain {
            return xDomain
        }
        if let window {
            return DashboardChartStyle.visibleXDomain(
                dataDomain: model.scale.xDomain ?? model.fallbackXDomain,
                window: window
            )
        }
        return model.scale.xDomain ?? model.fallbackXDomain
    }

    private var resolvedYDomain: ClosedRange<Double> {
        if let yDomain = viewport.yDomain {
            return yDomain
        }
        if let fixedYDomain = model.fixedYDomain {
            return fixedYDomain
        }
        return model.scale.yDomain
    }

    private func defaultYAxisLabel(_ value: Double) -> String {
        DashboardChartStyle.valueLabel(
            for: value,
            unit: model.primaryUnit,
            throughputUnit: throughputUnit
        )
    }
}

private struct ChartGapStripOverlay: View {
    let timestamps: [Date]
    let xDomain: ClosedRange<Date>
    let plotFrame: CGRect

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            for gapRange in ChartPlotGeometry.timelineGapRanges(for: timestamps) {
                let startX = ChartPlotGeometry.xPosition(for: gapRange.lowerBound, domain: xDomain, width: size.width)
                let endX = ChartPlotGeometry.xPosition(for: gapRange.upperBound, domain: xDomain, width: size.width)
                let rect = CGRect(
                    x: min(startX, endX),
                    y: 0,
                    width: max(abs(endX - startX), 1),
                    height: size.height
                )
                context.fill(Path(rect), with: .color(DashboardChartTheme.gapStripColor()))
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: rect.maxX, y: 0))
                        path.addLine(to: CGPoint(x: rect.maxX, y: size.height))
                    },
                    with: .color(DashboardChartTheme.gapDividerColor()),
                    lineWidth: 0.75
                )
            }
        }
        .frame(width: plotFrame.width, height: plotFrame.height)
        .position(x: plotFrame.midX, y: plotFrame.midY)
        .allowsHitTesting(false)
    }
}
