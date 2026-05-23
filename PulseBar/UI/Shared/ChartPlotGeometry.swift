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
}
