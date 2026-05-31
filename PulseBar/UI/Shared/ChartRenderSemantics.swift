import Foundation

/// Shared rules for how prepared chart points are grouped before rendering.
enum ChartRenderSemantics {
    struct RenderGroup: Identifiable {
        let id: String
        let segments: [[TimeSeriesChartPoint]]
    }

    static func continuitySegments(
        for style: DashboardTimeSeriesRenderStyle,
        points: [TimeSeriesChartPoint]
    ) -> [[TimeSeriesChartPoint]] {
        renderGroups(for: style, points: points).flatMap(\.segments)
    }

    /// Groups chart marks for rendering with stable z-order (back series first) and gap breaks preserved.
    static func renderGroups(
        for style: DashboardTimeSeriesRenderStyle,
        points: [TimeSeriesChartPoint]
    ) -> [RenderGroup] {
        switch style {
        case .stackedArea:
            return stackedContinuitySegments(from: points).enumerated().map { index, segment in
                RenderGroup(
                    id: "timeline-\(index)",
                    segments: [
                        segment.sorted {
                            if layerRank(for: $0.seriesKey) == layerRank(for: $1.seriesKey) {
                                return $0.timestamp < $1.timestamp
                            }
                            return layerRank(for: $0.seriesKey) < layerRank(for: $1.seriesKey)
                        }
                    ]
                )
            }

        case .baselineAreaLine, .lineOnly:
            let segments = ChartPlotGeometry.groupedSegments(from: points)
            var segmentsBySeries: [String: [[TimeSeriesChartPoint]]] = [:]
            for segment in segments {
                guard let seriesKey = segment.first?.seriesKey else { continue }
                segmentsBySeries[seriesKey, default: []].append(segment)
            }

            for seriesKey in segmentsBySeries.keys {
                segmentsBySeries[seriesKey]?.sort {
                    segmentIndex(from: $0.first?.continuityKey ?? "") < segmentIndex(from: $1.first?.continuityKey ?? "")
                }
            }

            return segmentsBySeries.keys
                .sorted { layerRank(for: $0) < layerRank(for: $1) }
                .map { seriesKey in
                    RenderGroup(
                        id: seriesKey,
                        segments: segmentsBySeries[seriesKey] ?? []
                    )
                }
        }
    }

    /// Swift Charts `series` identity. Uses `continuityKey` so gaps do not interpolate across missing data.
    static func chartSeriesIdentity(for point: TimeSeriesChartPoint) -> String {
        point.continuityKey
    }

    /// Lower rank is drawn first (bottom layer) for overlapping non-stacked series.
    static func layerRank(for seriesKey: String) -> Int {
        switch seriesKey {
        case "load.15":
            return 10
        case "load.5":
            return 20
        case "load.1":
            return 30
        case "cpu.system":
            return 10
        case "cpu.user":
            return 20
        case "memory.pressure", "memory.swap":
            return 10
        case "memory.pageIns":
            return 20
        case "memory.pageOuts":
            return 30
        case "gpu.processor":
            return 10
        case "gpu.memory":
            return 20
        default:
            if seriesKey.hasPrefix("temperature.") {
                return 40
            }
            return 100
        }
    }

    static func segmentIndex(from continuityKey: String) -> Int {
        guard let suffix = continuityKey.split(separator: "#").last else { return 0 }
        return Int(suffix) ?? 0
    }

    static func compareSegmentsForDrawOrder(
        _ lhs: [TimeSeriesChartPoint],
        _ rhs: [TimeSeriesChartPoint]
    ) -> Bool {
        let lhsKey = lhs.first?.seriesKey ?? ""
        let rhsKey = rhs.first?.seriesKey ?? ""
        if layerRank(for: lhsKey) != layerRank(for: rhsKey) {
            return layerRank(for: lhsKey) < layerRank(for: rhsKey)
        }
        return segmentIndex(from: lhs.first?.continuityKey ?? "")
            < segmentIndex(from: rhs.first?.continuityKey ?? "")
    }

    private static func stackedContinuitySegments(from points: [TimeSeriesChartPoint]) -> [[TimeSeriesChartPoint]] {
        guard !points.isEmpty else { return [] }

        let segmentIndices = ChartSeriesPipeline.timelineSegmentIndices(for: points.map(\.timestamp))
        var buckets: [Int: [TimeSeriesChartPoint]] = [:]
        for (point, segmentIndex) in zip(points, segmentIndices) {
            buckets[segmentIndex, default: []].append(point)
        }

        return buckets.keys.sorted().map { index in
            buckets[index]!.sorted {
                if $0.timestamp == $1.timestamp {
                    return layerRank(for: $0.seriesKey) < layerRank(for: $1.seriesKey)
                }
                return $0.timestamp < $1.timestamp
            }
        }
    }
}
