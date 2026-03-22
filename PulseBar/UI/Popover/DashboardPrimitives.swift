import SwiftUI

enum DashboardPalette {
    static let canvasTop = Color(red: 0.86, green: 0.90, blue: 0.96)
    static let canvasBottom = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let cardTop = Color(red: 0.99, green: 0.992, blue: 0.997)
    static let cardBottom = Color(red: 0.95, green: 0.965, blue: 0.985)
    static let chromeFill = Color(red: 0.91, green: 0.94, blue: 0.975)
    static let chromeBorder = Color(red: 0.74, green: 0.79, blue: 0.86)
    static let divider = Color(red: 0.83, green: 0.87, blue: 0.92)
    static let primaryText = Color(red: 0.12, green: 0.15, blue: 0.20)
    static let secondaryText = Color(red: 0.34, green: 0.39, blue: 0.46)
    static let tertiaryText = Color(red: 0.47, green: 0.52, blue: 0.60)
    static let windowBackground = Color(red: 0.94, green: 0.96, blue: 0.99)
    static let sectionFill = Color(red: 0.985, green: 0.989, blue: 0.996)
    static let insetFill = Color(red: 0.89, green: 0.92, blue: 0.96)
    static let hoverFill = Color(red: 0.87, green: 0.91, blue: 0.97)
    static let selectionFill = Color(red: 0.81, green: 0.88, blue: 0.98)
    static let chartGrid = Color(red: 0.79, green: 0.84, blue: 0.90)
    static let chartRule = Color(red: 0.42, green: 0.48, blue: 0.56)
    static let success = Color(red: 0.20, green: 0.61, blue: 0.36)
    static let warning = Color(red: 0.84, green: 0.58, blue: 0.12)
    static let danger = Color(red: 0.78, green: 0.24, blue: 0.22)
    static let cpuAccent = Color(red: 0.10, green: 0.52, blue: 0.95)
    static let memoryAccent = Color(red: 0.84, green: 0.33, blue: 0.66)
    static let batteryAccent = Color(red: 0.20, green: 0.66, blue: 0.43)
    static let networkAccent = Color(red: 0.00, green: 0.62, blue: 0.78)
    static let diskAccent = Color(red: 0.95, green: 0.54, blue: 0.17)
    static let temperatureAccent = Color(red: 0.86, green: 0.30, blue: 0.26)
}

private struct DashboardSurfaceModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DashboardPalette.sectionFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                    )
            )
    }
}

private struct DashboardInsetModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DashboardPalette.insetFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(DashboardPalette.divider, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func dashboardSurface(padding: CGFloat = 10, cornerRadius: CGFloat = 12) -> some View {
        modifier(DashboardSurfaceModifier(padding: padding, cornerRadius: cornerRadius))
    }

    func dashboardInset(cornerRadius: CGFloat = 12) -> some View {
        modifier(DashboardInsetModifier(cornerRadius: cornerRadius))
    }
}

struct DashboardSectionLabel: View {
    let title: String
    var tint: Color = DashboardPalette.secondaryText

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }
}

struct DashboardInfoBanner: View {
    let text: String
    var tint: Color = DashboardPalette.secondaryText
    var fill: Color = DashboardPalette.insetFill

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(DashboardPalette.chromeBorder, lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 22, x: 0, y: 12)
    }
}

struct DashboardSparklineView: View {
    let values: [Double]
    var lineColor: Color = .accentColor
    var fillColor: Color = .accentColor.opacity(0.18)

    var body: some View {
        GeometryReader { proxy in
            if plottedValues.count < 2 {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DashboardPalette.chromeFill)
            } else {
                let points = scaledPoints(in: proxy.size)

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DashboardPalette.chromeFill)

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                        for point in points {
                            path.addLine(to: point)
                        }
                        if let last = points.last {
                            path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                        }
                        path.closeSubpath()
                    }
                    .fill(fillColor)

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 80)
    }

    private var plottedValues: [Double] {
        let values = values.suffix(36)
        return values.isEmpty ? [0] : Array(values)
    }

    private func scaledPoints(in size: CGSize) -> [CGPoint] {
        let values = plottedValues
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
}

struct DashboardBidirectionalSparklineView: View {
    let positiveValues: [Double]
    let negativeValues: [Double]
    var positiveColor: Color = .pink
    var negativeColor: Color = .blue

    var body: some View {
        GeometryReader { proxy in
            let count = max(plottedPositive.count, plottedNegative.count)
            let maxValue = max((plottedPositive + plottedNegative).max() ?? 1, 1)

            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DashboardPalette.chromeFill)

                Rectangle()
                    .fill(DashboardPalette.chromeBorder)
                    .frame(height: 1)

                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<count, id: \.self) { index in
                        let upValue = index < plottedPositive.count ? plottedPositive[index] : 0
                        let downValue = index < plottedNegative.count ? plottedNegative[index] : 0

                        VStack(spacing: 0) {
                            Spacer()
                            Rectangle()
                                .fill(positiveColor)
                                .frame(height: max(1, CGFloat(upValue / maxValue) * ((proxy.size.height / 2) - 6)))
                            Spacer().frame(height: 1)
                            Rectangle()
                                .fill(negativeColor)
                                .frame(height: max(1, CGFloat(downValue / maxValue) * ((proxy.size.height / 2) - 6)))
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
        .frame(height: 82)
    }

    private var plottedPositive: [Double] {
        Array(positiveValues.suffix(36))
    }

    private var plottedNegative: [Double] {
        Array(negativeValues.suffix(36))
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
                .foregroundStyle(tint)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(DashboardPalette.primaryText)
        }
        .font(.subheadline)
    }
}

struct DashboardProcessListRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack {
            Text(name)
                .lineLimit(1)
                .foregroundStyle(DashboardPalette.primaryText)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(DashboardPalette.secondaryText)
        }
        .font(.subheadline)
    }
}
