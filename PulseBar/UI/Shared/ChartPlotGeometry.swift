import Foundation
import SwiftUI

enum ChartPlotGeometry {
    static func groupedSegments(from points: [TimeSeriesChartPoint]) -> [[TimeSeriesChartPoint]] {
        Dictionary(grouping: points, by: \.continuityKey)
            .values
            .map { $0.sorted { $0.timestamp < $1.timestamp } }
            .sorted {
                guard let lhs = $0.first?.timestamp, let rhs = $1.first?.timestamp else { return false }
                return lhs < rhs
            }
    }

    static func xPosition(for timestamp: Date, domain: ClosedRange<Date>, width: CGFloat) -> CGFloat {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return width / 2 }
        let offset = timestamp.timeIntervalSince(domain.lowerBound)
        return CGFloat(min(max(offset / span, 0), 1)) * width
    }

    static func yPosition(for value: Double, domain: ClosedRange<Double>, height: CGFloat) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return height / 2 }
        let normalized = (value - domain.lowerBound) / span
        return height - (CGFloat(min(max(normalized, 0), 1)) * height)
    }

    static func indexScaledPoints(values: [Double], size: CGSize) -> [CGPoint] {
        let maxValue = values.max() ?? 0
        let minValue = values.min() ?? 0
        let span = max(maxValue - minValue, 0.001)

        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
            let normalized = (value - minValue) / span
            let y = size.height - (CGFloat(normalized) * (size.height - 8)) - 4
            return CGPoint(x: x, y: y)
        }
    }

    static func areaPath(
        points: [TimeSeriesChartPoint],
        baseline: Double,
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>,
        size: CGSize
    ) -> Path {
        guard let first = points.first, let last = points.last else { return Path() }
        var path = Path()
        let baselineY = yPosition(for: baseline, domain: yDomain, height: size.height)
        path.move(to: CGPoint(x: xPosition(for: first.timestamp, domain: xDomain, width: size.width), y: baselineY))
        for point in points {
            path.addLine(to: CGPoint(
                x: xPosition(for: point.timestamp, domain: xDomain, width: size.width),
                y: yPosition(for: point.value, domain: yDomain, height: size.height)
            ))
        }
        path.addLine(to: CGPoint(x: xPosition(for: last.timestamp, domain: xDomain, width: size.width), y: baselineY))
        path.closeSubpath()
        return path
    }

    static func linePath(
        for points: [TimeSeriesChartPoint],
        xDomain: ClosedRange<Date>,
        yDomain: ClosedRange<Double>,
        size: CGSize
    ) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(to: CGPoint(
            x: xPosition(for: first.timestamp, domain: xDomain, width: size.width),
            y: yPosition(for: first.value, domain: yDomain, height: size.height)
        ))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(
                x: xPosition(for: point.timestamp, domain: xDomain, width: size.width),
                y: yPosition(for: point.value, domain: yDomain, height: size.height)
            ))
        }
        return path
    }

    static func linePath(for values: [Double], size: CGSize) -> Path {
        let points = indexScaledPoints(values: values, size: size)
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    /// Returns x-ranges between contiguous timeline segments (missing-data gaps).
    static func timelineGapRanges(
        for timestamps: [Date],
        paddingFraction: Double = 0.015
    ) -> [ClosedRange<Date>] {
        guard timestamps.count >= 2 else { return [] }

        let sortedUnique = Array(Set(timestamps)).sorted()
        let segmentIndices = ChartSeriesPipeline.timelineSegmentIndices(for: timestamps)
        var segmentByTimestamp: [Date: Int] = [:]
        for (timestamp, segmentIndex) in zip(timestamps, segmentIndices) {
            segmentByTimestamp[timestamp] = segmentIndex
        }

        var boundaryTimestamps: [Date] = []
        for index in sortedUnique.indices.dropFirst() {
            let previous = sortedUnique[index - 1]
            let current = sortedUnique[index]
            guard segmentByTimestamp[previous] != segmentByTimestamp[current] else { continue }
            boundaryTimestamps.append(previous)
        }

        guard !boundaryTimestamps.isEmpty else { return [] }

        let span = sortedUnique.last!.timeIntervalSince(sortedUnique.first!)
        let padding = max(span * paddingFraction, 0.5)

        return boundaryTimestamps.map { boundary in
            let start = boundary.addingTimeInterval(padding * 0.35)
            let end = start.addingTimeInterval(padding)
            return start ... end
        }
    }

    static func drawGapStrips(
        timestamps: [Date],
        xDomain: ClosedRange<Date>,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        for gapRange in timelineGapRanges(for: timestamps) {
            let startX = xPosition(for: gapRange.lowerBound, domain: xDomain, width: size.width)
            let endX = xPosition(for: gapRange.upperBound, domain: xDomain, width: size.width)
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
}
