import AppKit
import PulseBarCore
import SwiftUI

private extension Color {
    static func pulseBarAdaptive(
        light: (Double, Double, Double, Double),
        dark: (Double, Double, Double, Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let source = isDark ? dark : light
            return NSColor(
                calibratedRed: CGFloat(source.0),
                green: CGFloat(source.1),
                blue: CGFloat(source.2),
                alpha: CGFloat(source.3)
            )
        })
    }
}

enum DashboardPalette {
    static var canvasTop: Color { .pulseBarAdaptive(light: (0.955, 0.965, 0.975, 1), dark: (0.075, 0.085, 0.10, 1)) }
    static var canvasBottom: Color { .pulseBarAdaptive(light: (0.905, 0.925, 0.955, 1), dark: (0.115, 0.13, 0.155, 1)) }
    static var cardTop: Color { .pulseBarAdaptive(light: (0.995, 0.997, 1, 1), dark: (0.165, 0.175, 0.20, 1)) }
    static var cardBottom: Color { .pulseBarAdaptive(light: (0.955, 0.965, 0.985, 1), dark: (0.115, 0.125, 0.15, 1)) }
    static var chromeFill: Color { .pulseBarAdaptive(light: (0.925, 0.945, 0.97, 1), dark: (0.19, 0.205, 0.235, 1)) }
    static var chromeBorder: Color { .pulseBarAdaptive(light: (0.75, 0.79, 0.85, 1), dark: (0.30, 0.33, 0.38, 1)) }
    static var divider: Color { .pulseBarAdaptive(light: (0.82, 0.86, 0.91, 1), dark: (0.25, 0.28, 0.33, 1)) }
    static var primaryText: Color { .pulseBarAdaptive(light: (0.11, 0.13, 0.17, 1), dark: (0.925, 0.94, 0.96, 1)) }
    static var secondaryText: Color { .pulseBarAdaptive(light: (0.36, 0.40, 0.46, 1), dark: (0.66, 0.70, 0.76, 1)) }
    static var tertiaryText: Color { .pulseBarAdaptive(light: (0.52, 0.56, 0.63, 1), dark: (0.49, 0.54, 0.61, 1)) }
    static var windowBackground: Color { .pulseBarAdaptive(light: (0.95, 0.96, 0.98, 1), dark: (0.105, 0.115, 0.135, 1)) }
    static var sectionFill: Color { .pulseBarAdaptive(light: (0.975, 0.982, 0.992, 1), dark: (0.135, 0.15, 0.18, 1)) }
    static var insetFill: Color { .pulseBarAdaptive(light: (0.92, 0.94, 0.965, 1), dark: (0.18, 0.195, 0.23, 1)) }
    static var hoverFill: Color { .pulseBarAdaptive(light: (0.90, 0.94, 0.98, 1), dark: (0.21, 0.24, 0.285, 1)) }
    static var selectionFill: Color { .pulseBarAdaptive(light: (0.86, 0.91, 0.98, 1), dark: (0.16, 0.22, 0.31, 1)) }
    static var chartGrid: Color { .pulseBarAdaptive(light: (0.67, 0.73, 0.81, 1), dark: (0.30, 0.35, 0.43, 1)) }
    static var chartRule: Color { .pulseBarAdaptive(light: (0.29, 0.35, 0.44, 1), dark: (0.58, 0.65, 0.74, 1)) }
    static var chartAxisText: Color { .pulseBarAdaptive(light: (0.35, 0.40, 0.48, 1), dark: (0.62, 0.67, 0.74, 1)) }
    static var chartAxisStrong: Color { .pulseBarAdaptive(light: (0.24, 0.29, 0.37, 1), dark: (0.76, 0.80, 0.86, 1)) }
    static var chartPlotTop: Color { .pulseBarAdaptive(light: (0.92, 0.945, 0.975, 1), dark: (0.16, 0.18, 0.22, 1)) }
    static var chartPlotBottom: Color { .pulseBarAdaptive(light: (0.87, 0.91, 0.955, 1), dark: (0.12, 0.14, 0.175, 1)) }
    static var chartPlotBorder: Color { .pulseBarAdaptive(light: (0.73, 0.79, 0.87, 1), dark: (0.28, 0.32, 0.39, 1)) }
    static var shellHighlight: Color { .pulseBarAdaptive(light: (1, 1, 1, 0.88), dark: (1, 1, 1, 0.10)) }
    static var shadow: Color { .pulseBarAdaptive(light: (0.11, 0.14, 0.20, 0.10), dark: (0, 0, 0, 0.28)) }
    static var shadowHeavy: Color { .pulseBarAdaptive(light: (0.11, 0.14, 0.20, 0.16), dark: (0, 0, 0, 0.38)) }
    static let success = Color(red: 0.20, green: 0.66, blue: 0.42)
    static let warning = Color(red: 0.90, green: 0.62, blue: 0.17)
    static let danger = Color(red: 0.82, green: 0.27, blue: 0.25)
    static let cpuAccent = Color(red: 0.11, green: 0.50, blue: 0.92)
    static let memoryAccent = Color(red: 0.84, green: 0.33, blue: 0.66)
    static let batteryAccent = Color(red: 0.18, green: 0.65, blue: 0.42)
    static let networkAccent = Color(red: 0.00, green: 0.62, blue: 0.78)
    static let diskAccent = Color(red: 0.95, green: 0.56, blue: 0.18)
    static let temperatureAccent = Color(red: 0.86, green: 0.30, blue: 0.26)
}

private struct DashboardSurfaceModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let resolvedRadius = DashboardTabMetrics.resolvedCornerRadius(cornerRadius)
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DashboardPalette.cardTop,
                                DashboardPalette.sectionFill
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                            .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                            .stroke(DashboardPalette.shellHighlight, lineWidth: 1)
                            .blur(radius: 0.5)
                            .mask(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            )
            .shadow(color: DashboardPalette.shadow, radius: 16, x: 0, y: 8)
    }
}

private struct DashboardInsetModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let resolvedRadius = DashboardTabMetrics.resolvedCornerRadius(cornerRadius)
        content
            .background(
                RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DashboardPalette.insetFill,
                                DashboardPalette.insetFill.opacity(0.84)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                            .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func dashboardSurface(padding: CGFloat = 10, cornerRadius: CGFloat = 8) -> some View {
        modifier(DashboardSurfaceModifier(padding: padding, cornerRadius: cornerRadius))
    }

    func dashboardInset(cornerRadius: CGFloat = 8) -> some View {
        modifier(DashboardInsetModifier(cornerRadius: cornerRadius))
    }

    func dashboardCanvasBackground() -> some View {
        background(
            ZStack {
                LinearGradient(
                    colors: [
                        DashboardPalette.canvasTop,
                        DashboardPalette.canvasBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        DashboardPalette.cpuAccent.opacity(0.11),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 420
                )
            }
        )
    }
}

extension DashboardPalette {
    static func chartPlotBackground(cornerRadius: CGFloat = DashboardChartTheme.defaultPlotCornerRadius, showsMinorGrid: Bool? = nil) -> some View {
        let resolvedRadius = cornerRadius
        return RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        chartPlotTop,
                        chartPlotBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if showsMinorGrid == true {
                    DashboardMinorGridOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                    .strokeBorder(chartPlotBorder.opacity(0.9), lineWidth: 1)
            )
    }
}

enum DashboardMinorGridGeometry {
    static let defaultSubdivisionCount = 4

    static func guideFractions(subdivisionCount: Int = defaultSubdivisionCount) -> [CGFloat] {
        guard subdivisionCount > 0 else { return [] }
        return (1...subdivisionCount).map { CGFloat($0) / CGFloat(subdivisionCount + 1) }
    }

    static func guidePositions(length: CGFloat, subdivisionCount: Int = defaultSubdivisionCount) -> [CGFloat] {
        guard length.isFinite, length > 0 else { return [] }
        return guideFractions(subdivisionCount: subdivisionCount).map { length * $0 }
    }
}

private struct DashboardMinorGridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                var path = Path()
                for x in DashboardMinorGridGeometry.guidePositions(length: size.width) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                for y in DashboardMinorGridGeometry.guidePositions(length: size.height) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }

                context.stroke(
                    path,
                    with: .color(DashboardPalette.chartGrid.opacity(0.64)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 4], dashPhase: 1)
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
    }
}

struct DashboardSectionLabel: View {
    let title: String
    var tint: Color = DashboardPalette.secondaryText

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(tint)
    }
}

struct ChartLegendItem: Identifiable {
    let id: String
    let label: String
    let color: Color
    let valueText: String?

    init(id: String, label: String, color: Color, valueText: String? = nil) {
        self.id = id
        self.label = label
        self.color = color
        self.valueText = valueText
    }
}

struct ChartLegendStrip: View {
    let items: [ChartLegendItem]
    var minimumItemWidth: CGFloat = 118
    var hiddenItemIDs: Set<String> = []
    var onToggle: ((ChartLegendItem) -> Void)?

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: minimumItemWidth),
                spacing: 10,
                alignment: .leading
            )
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(items) { item in
                Button {
                    onToggle?(item)
                } label: {
                    HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(hiddenItemIDs.contains(item.id) ? DashboardPalette.tertiaryText : item.color)
                        .frame(width: 9, height: 9)

                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                        .lineLimit(1)

                    if let valueText = item.valueText {
                        Text(valueText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DashboardPalette.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(hiddenItemIDs.contains(item.id) ? 0.45 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onToggle == nil)
            }
        }
    }
}

struct DetachedPaneHeaderCard: View {
    let sectionTitle: String
    let title: String
    let subtitle: String?
    let valueText: String
    let badgeText: String
    var accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                DashboardSectionLabel(title: sectionTitle, tint: accent)
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(valueText)
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)

                Text(badgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DashboardPalette.insetFill)
                    )
            }
        }
        .padding(12)
        .dashboardInset(cornerRadius: 16)
    }
}

struct DashboardInfoBanner: View {
    let text: String
    var tint: Color = DashboardPalette.secondaryText
    var fill: Color = DashboardPalette.insetFill

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.85))
                .frame(width: 4)

            Text(text)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                )
        )
    }
}

struct DashboardCard<Content: View>: View {
    let title: String
    var accent: Color = .accentColor
    var actionTitle: String?
    var action: (() -> Void)?
    let content: Content

    init(
        _ title: String,
        accent: Color = .accentColor,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accent = accent
        self.actionTitle = actionTitle
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.95),
                            accent.opacity(0.45)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 52, height: 5)

            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(accent)
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardPalette.secondaryText)
                }
            }

            content
        }
        .foregroundStyle(DashboardPalette.primaryText)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DashboardPalette.cardTop,
                            DashboardPalette.cardBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                )
        )
        .shadow(color: DashboardPalette.shadowHeavy, radius: 18, x: 0, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            action?()
        }
    }
}

struct DashboardSparklineView: View {
    let values: [Double]
    var lineColor: Color = DashboardPalette.cpuChartAccent
    var fillColor: Color = DashboardChartTheme.sparklineFill(DashboardPalette.cpuChartAccent)

    var body: some View {
        DashboardMiniChart(
            model: PreparedTimeSeriesChartModel.fromSparklineValues(values, color: lineColor),
            areaOpacity: DashboardChartTheme.defaultAreaOpacity,
            lineColor: lineColor,
            fillColor: fillColor,
            showsPlotBackground: true
        )
        .frame(height: 80)
    }
}

struct DashboardBidirectionalSparklineView: View {
    let positiveValues: [Double]
    let negativeValues: [Double]
    var positiveColor: Color = DashboardPalette.networkChartAccent
    var negativeColor: Color = DashboardPalette.diskChartAccent

    var body: some View {
        DashboardMiniChart(
            model: PreparedTimeSeriesChartModel.fromBidirectionalSparkline(
                positiveValues: positiveValues,
                negativeValues: negativeValues,
                positiveColor: positiveColor,
                negativeColor: negativeColor
            ),
            positiveColor: positiveColor,
            negativeColor: negativeColor,
            showsPlotBackground: true
        )
        .frame(height: 82)
    }
}

struct DashboardRingGauge: View {
    let value: Double
    let total: Double
    let title: String
    let valueText: String
    var tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(DashboardPalette.divider, lineWidth: 10)
                .overlay {
                    Circle()
                        .stroke(DashboardPalette.shellHighlight, lineWidth: 1)
                        .padding(5)
                }

            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(valueText)
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(DashboardPalette.secondaryText)
            }
        }
        .frame(width: 118, height: 118)
    }

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(max(value / total, 0), 1))
    }
}

struct DashboardMetricRow: View {
    let title: String
    let value: String
    var tint: Color = .secondary

    var body: some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
                .foregroundStyle(tint)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(DashboardPalette.primaryText)
        }
        .font(.subheadline)
    }
}

struct ProcessListRow: View {
    let displayName: String
    let value: String
    let executablePath: String
    let fallbackName: String

    init(entry: CPUProcessEntry) {
        displayName = entry.displayName
        value = UnitsFormatter.format(entry.cpuPercent, unit: .percent)
        executablePath = entry.executablePath
        fallbackName = entry.name
    }

    init(entry: MemoryProcessEntry) {
        displayName = entry.displayName
        value = UnitsFormatter.format(entry.residentBytes, unit: .bytes)
        executablePath = entry.executablePath
        fallbackName = entry.name
    }

    var body: some View {
        HStack(spacing: 8) {
            ProcessAppearanceResolver.iconView(forExecutablePath: executablePath)
            Text(displayName)
                .lineLimit(1)
                .foregroundStyle(DashboardPalette.primaryText)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(DashboardPalette.secondaryText)
        }
        .font(.subheadline)
        .help(ProcessAppearanceResolver.helpText(executablePath: executablePath, fallbackName: fallbackName))
    }
}

struct DashboardReadoutCell: View {
    let title: String
    let value: String
    var tint: Color = DashboardPalette.secondaryText
    var valueColor: Color = DashboardPalette.primaryText

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DashboardSectionLabel(title: title, tint: tint)

            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardPalette.insetFill.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                )
        )
    }
}
