import SwiftUI
import PulseBarCore

enum DashboardTabMetrics {
    static let sectionSpacing: CGFloat = 12
    static let surfaceCornerRadius: CGFloat = 8
    static let hoverSectionCornerRadius: CGFloat = 16
    static let insetCornerRadius: CGFloat = 16

    /// Pass-through for `dashboardSurface` / `dashboardInset`; radii are not clamped here.
    static func resolvedCornerRadius(_ requested: CGFloat) -> CGFloat {
        requested
    }
}

enum DashboardControlMetrics {
    static let chartWindowChipCompactWidth: CGFloat = 58
    static let chartWindowChipDetachedWidth: CGFloat = 74
    static let chartWindowChipCompactHeight: CGFloat = 34
    static let chartWindowChipDetachedHeight: CGFloat = 42

    static let chartToolsCompactSpacing: CGFloat = 10
    static let chartToolsDetachedSpacing: CGFloat = 12
    static let chartToolsCompactHorizontalPadding: CGFloat = 8
    static let chartToolsDetachedHorizontalPadding: CGFloat = 10
    static let chartToolsCompactVerticalPadding: CGFloat = 6
    static let chartToolsDetachedVerticalPadding: CGFloat = 8
    static let chartToolsDetachedSliderMinWidth: CGFloat = 220
    static let chartToolsCompactSliderMinWidth: CGFloat = 140

    static let chartToolsCompactCornerRadius: CGFloat = 10
    static let chartToolsDetachedCornerRadius: CGFloat = 12
    static let chartToolsCompactFillOpacity: CGFloat = 0.86
    static let chartToolsDetachedFillOpacity: CGFloat = 0.92

    static let chartWindowPickerDetachedPadding: CGFloat = 2
}

/// Fixed row heights that mirror `DetachedMetricsPaneShell` so AppKit panel sizing stays aligned.
enum DetachedPaneShellMetrics {
    static let chartWindowPickerBlockHeight: CGFloat = 40
    static let chartToolsStripBlockHeight: CGFloat = 46
    static let headerBlockHeight: CGFloat = 50
    static let paneToolbarBlockHeight: CGFloat = 32
    static let chartInsetTopPadding: CGFloat = 12
    static let chartInsetBottomPadding: CGFloat = 12
    static let legendFooterBlockHeight: CGFloat = 58

    /// Matches `DetachedMetricsPaneShell` rows above the chart plot (window picker through inset top padding).
    static var chromeAboveChart: CGFloat {
        DashboardTabMetrics.sectionSpacing * 4
            + chartWindowPickerBlockHeight
            + chartToolsStripBlockHeight
            + headerBlockHeight
            + paneToolbarBlockHeight
            + chartInsetTopPadding
    }
}

enum DetachedPaneLayout {
    struct PaneStyle: Equatable {
        let chartHeight: CGFloat
        let emptyChartMinHeight: CGFloat
        let extraToolbarRowHeight: CGFloat
    }

    static let standardPane = PaneStyle(
        chartHeight: 260,
        emptyChartMinHeight: 200,
        extraToolbarRowHeight: 0
    )
    static let comparePane = PaneStyle(
        chartHeight: 270,
        emptyChartMinHeight: 190,
        extraToolbarRowHeight: 0
    )
    static let temperaturePane = PaneStyle(
        chartHeight: 260,
        emptyChartMinHeight: 200,
        extraToolbarRowHeight: 34
    )

    static let preferredPanelWidth: CGFloat = 560
    static let minimumUsablePanelWidth: CGFloat = 420
    static let absoluteMinimumPanelWidth: CGFloat = 260
    static let panelGap: CGFloat = 4
    static let hostPadding: CGFloat = 8
    static let shellSurfacePadding: CGFloat = 14
    static let minimumPanelHeight: CGFloat = 340
    static let maximumPanelHeight: CGFloat = 680

    static func paneStyle(for target: DetachedMetricsPaneTarget?) -> PaneStyle {
        switch target {
        case .temperatureCompare:
            return comparePane
        case .temperature:
            return temperaturePane
        case .memory, .cpu, nil:
            return standardPane
        }
    }

    static func contentHeight(for target: DetachedMetricsPaneTarget?) -> CGFloat {
        let style = paneStyle(for: target)
        return DetachedPaneShellMetrics.chromeAboveChart
            + style.extraToolbarRowHeight
            + style.chartHeight
            + DetachedPaneShellMetrics.legendFooterBlockHeight
            + (hostPadding * 2)
            + (shellSurfacePadding * 2)
    }
}

struct DashboardTabSection<Content: View>: View {
    let title: String
    var tint: Color = DashboardPalette.secondaryText
  let content: Content

    init(_ title: String, tint: Color = DashboardPalette.secondaryText, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardSectionLabel(title: title, tint: tint)
            content
        }
    }
}

struct ChartTabToolbar: View {
    @ObservedObject var coordinator: AppCoordinator
    @Binding var historyWindow: ChartWindow

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTabMetrics.sectionSpacing) {
            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: $historyWindow
            )
            ChartToolsStrip(
                smoothingAlpha: $coordinator.chartSmoothingAlpha,
                showsMinorGrid: $coordinator.chartMinorGridEnabled
            )
        }
    }
}

struct HoverDetachSection<Content: View>: View {
    let isActive: Bool
    var accent: Color = DashboardPalette.cpuAccent
    let onPin: () -> Void
    let onPreview: (Bool) -> Void
    let content: Content

    init(
        isActive: Bool,
        accent: Color = DashboardPalette.cpuAccent,
        onPin: @escaping () -> Void,
        onPreview: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isActive = isActive
        self.accent = accent
        self.onPin = onPin
        self.onPreview = onPreview
        self.content = content()
    }

    var body: some View {
        Button(action: onPin) {
            content
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: DashboardTabMetrics.hoverSectionCornerRadius, style: .continuous)
                        .fill(isActive ? DashboardPalette.selectionFill : DashboardPalette.sectionFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: DashboardTabMetrics.hoverSectionCornerRadius, style: .continuous)
                                .strokeBorder(isActive ? accent.opacity(0.45) : DashboardPalette.chromeBorder, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onPreview(hovering)
        }
    }
}

struct ProcessListSection<Row: View>: View {
    let title: String
    var tint: Color = DashboardPalette.secondaryText
    let rows: Row

    init(_ title: String, tint: Color = DashboardPalette.secondaryText, @ViewBuilder rows: () -> Row) {
        self.title = title
        self.tint = tint
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DashboardSectionLabel(title: title, tint: tint)
            rows
        }
        .dashboardSurface(padding: 12, cornerRadius: DashboardTabMetrics.surfaceCornerRadius)
    }
}
