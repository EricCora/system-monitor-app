import SwiftUI
import PulseBarCore

struct ChartWindowPicker: View {
    enum Style {
        case compact
        case detached
    }

    let options: [ChartWindow]
    @Binding var selection: ChartWindow
    var paneController: DetachedMetricsPaneController? = nil
    var style: Style = .compact

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    ChartWindowChip(
                        option: option,
                        selection: $selection,
                        paneController: paneController,
                        style: style
                    )
                }
            }
            .padding(style == .detached ? DashboardControlMetrics.chartWindowPickerDetachedPadding : 0)
        }
    }
}

struct ChartToolsStrip: View {
    enum Style {
        case compact
        case detached
    }

    @Binding var smoothingAlpha: Double
    @Binding var showsMinorGrid: Bool
    var style: Style = .compact

    private var sliderBounds: ClosedRange<Double> {
        0.05...1.0
    }

    private var spacing: CGFloat {
        style == .detached
            ? DashboardControlMetrics.chartToolsDetachedSpacing
            : DashboardControlMetrics.chartToolsCompactSpacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            HStack(spacing: 6) {
                Text("LPF")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardPalette.secondaryText)
                Slider(value: $smoothingAlpha, in: sliderBounds, step: 0.05)
                    .frame(
                        minWidth: style == .detached
                            ? DashboardControlMetrics.chartToolsDetachedSliderMinWidth
                            : DashboardControlMetrics.chartToolsCompactSliderMinWidth
                    )
                Text(String(format: "%.2f", smoothingAlpha))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DashboardPalette.primaryText)
                    .frame(width: 36, alignment: .trailing)
            }

            Toggle("Minor Grid", isOn: $showsMinorGrid)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
                .foregroundStyle(DashboardPalette.secondaryText)
        }
        .padding(
            .horizontal,
            style == .detached
                ? DashboardControlMetrics.chartToolsDetachedHorizontalPadding
                : DashboardControlMetrics.chartToolsCompactHorizontalPadding
        )
        .padding(
            .vertical,
            style == .detached
                ? DashboardControlMetrics.chartToolsDetachedVerticalPadding
                : DashboardControlMetrics.chartToolsCompactVerticalPadding
        )
        .background(
            RoundedRectangle(
                cornerRadius: style == .detached
                    ? DashboardControlMetrics.chartToolsDetachedCornerRadius
                    : DashboardControlMetrics.chartToolsCompactCornerRadius,
                style: .continuous
            )
            .fill(
                DashboardPalette.insetFill.opacity(
                    style == .detached
                        ? DashboardControlMetrics.chartToolsDetachedFillOpacity
                        : DashboardControlMetrics.chartToolsCompactFillOpacity
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: style == .detached
                        ? DashboardControlMetrics.chartToolsDetachedCornerRadius
                        : DashboardControlMetrics.chartToolsCompactCornerRadius,
                    style: .continuous
                )
                .strokeBorder(DashboardPalette.divider, lineWidth: 1)
            )
        )
    }
}

private struct ChartWindowChip: View {

    let option: ChartWindow
    @Binding var selection: ChartWindow
    let paneController: DetachedMetricsPaneController?
    let style: ChartWindowPicker.Style

    @State private var interactionStarted = false

    var body: some View {
        Button {
            selection = option
        } label: {
            Text(option.label)
                .font(
                    .system(
                        size: style == .detached ? 15 : 13,
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .multilineTextAlignment(.center)
                .frame(
                    width: style == .detached
                        ? DashboardControlMetrics.chartWindowChipDetachedWidth
                        : DashboardControlMetrics.chartWindowChipCompactWidth,
                    height: style == .detached
                        ? DashboardControlMetrics.chartWindowChipDetachedHeight
                        : DashboardControlMetrics.chartWindowChipCompactHeight,
                    alignment: .center
                )
                .background(backgroundColor, in: Capsule())
                .foregroundStyle(selection == option ? Color.white : DashboardPalette.primaryText)
                .overlay(
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: selection == option ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard let paneController, !interactionStarted else { return }
                    interactionStarted = true
                    paneController.beginPaneInteraction()
                }
                .onEnded { _ in
                    guard let paneController, interactionStarted else { return }
                    interactionStarted = false
                    paneController.endPaneInteraction()
                }
        )
        .onDisappear {
            guard let paneController, interactionStarted else { return }
            interactionStarted = false
            paneController.endPaneInteraction()
        }
    }

    private var backgroundColor: Color {
        if selection == option {
            return DashboardPalette.cpuAccent
        }
        return style == .detached ? DashboardPalette.sectionFill : DashboardPalette.insetFill.opacity(0.84)
    }

    private var borderColor: Color {
        DashboardPalette.chromeBorder
    }
}
