import AppKit
import SwiftUI

enum DashboardChartTheme {
    static let defaultAreaOpacity: Double = 0.72
    static let stackedAreaOpacity: Double = 0.88
    static let defaultLineOpacity: Double = 1.0
    static let defaultLineWidth: CGFloat = 2
    static let compactLineWidth: CGFloat = 1.75
    static let defaultPlotCornerRadius: CGFloat = 8
    static let detachedPlotCornerRadius: CGFloat = 14
    static let tabPlotCornerRadius: CGFloat = 12
    static let gridOpacity: Double = 0.10
    static let plotBorderOpacity: Double = 0.9
    static let hiddenLegendOpacity: Double = 0.48

    static var plotWellTop: Color { DashboardPalette.chartPlotTop }
    static var plotWellBottom: Color { DashboardPalette.chartPlotBottom }

    static let comparePalette: [Color] = [
        DashboardPalette.temperatureChartAccent,
        DashboardPalette.cpuChartAccent,
        DashboardPalette.memoryChartAccent,
        DashboardPalette.diskChartAccent,
        DashboardPalette.networkChartAccent,
        DashboardPalette.batteryChartAccent
    ]

    static func compareColor(for index: Int) -> Color {
        comparePalette[index % comparePalette.count]
    }

    /// Depth gradient: stays saturated from top to bottom (not fade-to-transparent).
    static func areaFill(_ color: Color, opacity: Double = defaultAreaOpacity) -> LinearGradient {
        LinearGradient(
            colors: [
                color.opacity(opacity * 0.92),
                color.opacity(opacity)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func areaFillStacked(_ color: Color, opacity: Double = stackedAreaOpacity) -> LinearGradient {
        areaFill(color, opacity: opacity)
    }

    /// Flat fill for Canvas mini charts (matches Swift Charts area midpoint).
    static func areaFillColor(_ color: Color, opacity: Double = defaultAreaOpacity) -> Color {
        color.opacity(opacity * 0.96)
    }

    static func areaFillStackedColor(_ color: Color, opacity: Double = stackedAreaOpacity) -> Color {
        color.opacity(opacity)
    }

    static func seriesStroke(_ color: Color, lineWidth: CGFloat = defaultLineWidth) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    static func seriesLineColor(_ color: Color, opacity: Double = defaultLineOpacity) -> Color {
        color.opacity(opacity)
    }

    static func sparklineFill(_ color: Color, opacity: Double = defaultAreaOpacity) -> Color {
        areaFillColor(color, opacity: opacity)
    }

    static func resolvedAreaOpacity(for renderStyle: DashboardTimeSeriesRenderStyle, baseOpacity: Double) -> Double {
        switch renderStyle {
        case .stackedArea:
            return stackedAreaOpacity
        case .baselineAreaLine, .lineOnly:
            return baseOpacity
        }
    }

    static func gapStripColor(opacity: Double = 0.22) -> Color {
        plotWellBottom.opacity(opacity)
    }

    static func gapDividerColor(opacity: Double = 0.35) -> Color {
        DashboardPalette.chartGrid.opacity(gridOpacity * opacity)
    }

    static func miniPlotBackground(cornerRadius: CGFloat = 8) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [plotWellTop, plotWellBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DashboardPalette.chartPlotBorder.opacity(plotBorderOpacity), lineWidth: 1)
            )
    }
}

extension DashboardPalette {
    static let cpuUserAccent = Color(red: 0.00, green: 0.68, blue: 0.94)
    static let cpuSystemAccent = Color(red: 1.00, green: 0.23, blue: 0.19)

    static var memoryChartAccent: Color { memoryAccent.opacity(0.92).saturated(by: 1.08) }
    static var networkChartAccent: Color { networkAccent.saturated(by: 1.10) }
    static var diskChartAccent: Color { diskAccent.saturated(by: 1.08) }
    static var temperatureChartAccent: Color { temperatureAccent.saturated(by: 1.10) }
    static var batteryChartAccent: Color { batteryAccent.saturated(by: 1.06) }
    static var cpuChartAccent: Color { cpuAccent.saturated(by: 1.06) }

    static func seriesColor(forSeriesKey key: String, fallback: Color = cpuChartAccent) -> Color {
        if key.hasPrefix("cpu.user") { return cpuUserAccent }
        if key.hasPrefix("cpu.system") { return cpuSystemAccent }
        if key.hasPrefix("memory.") { return memoryChartAccent }
        if key.hasPrefix("load.") {
            switch key {
            case "load.1": return cpuUserAccent
            case "load.5": return cpuSystemAccent
            default: return tertiaryText
            }
        }
        if key.hasPrefix("gpu.") {
            return key.contains("memory") ? networkChartAccent : cpuUserAccent
        }
        if key == "fps" { return networkChartAccent }
        return fallback
    }
}

private extension Color {
    func saturated(by factor: Double) -> Color {
        #if canImport(AppKit)
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else { return self }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(
            hue: Double(hue),
            saturation: Double(min(1, saturation * CGFloat(factor))),
            brightness: Double(brightness),
            opacity: Double(alpha)
        )
        #else
        return self
        #endif
    }
}
