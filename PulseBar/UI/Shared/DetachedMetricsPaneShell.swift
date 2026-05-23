import SwiftUI
import PulseBarCore

struct DetachedMetricsPaneShell<Header: View, AccessoryToolbar: View, Chart: View, Footer: View>: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    @Binding var historyWindow: ChartWindow
    @Binding var hoveredDate: Date?
    @Binding var viewport: ChartViewport
    @Binding var zoomSelectionRect: CGRect?

    let paneStyle: DetachedPaneLayout.PaneStyle
    let sectionAccent: Color
    let header: Header
    let accessoryToolbar: AccessoryToolbar
    let chart: Chart
    let footer: Footer

    init(
        coordinator: AppCoordinator,
        paneController: DetachedMetricsPaneController,
        historyWindow: Binding<ChartWindow>,
        hoveredDate: Binding<Date?>,
        viewport: Binding<ChartViewport>,
        zoomSelectionRect: Binding<CGRect?>,
        paneStyle: DetachedPaneLayout.PaneStyle = DetachedPaneLayout.standardPane,
        sectionAccent: Color,
        @ViewBuilder header: () -> Header,
        @ViewBuilder accessoryToolbar: () -> AccessoryToolbar = { EmptyView() },
        @ViewBuilder chart: () -> Chart,
        @ViewBuilder footer: () -> Footer
    ) {
        self.coordinator = coordinator
        self.paneController = paneController
        _historyWindow = historyWindow
        _hoveredDate = hoveredDate
        _viewport = viewport
        _zoomSelectionRect = zoomSelectionRect
        self.paneStyle = paneStyle
        self.sectionAccent = sectionAccent
        self.header = header()
        self.accessoryToolbar = accessoryToolbar()
        self.chart = chart()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTabMetrics.sectionSpacing) {
            ChartWindowPicker(
                options: coordinator.visibleChartWindows,
                selection: $historyWindow,
                paneController: paneController,
                style: .detached
            )
            ChartToolsStrip(
                smoothingAlpha: $coordinator.chartSmoothingAlpha,
                showsMinorGrid: $coordinator.chartMinorGridEnabled,
                style: .detached
            )

            header

            paneToolbar

            VStack(alignment: .leading, spacing: 10) {
                chart
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                footer
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
            .dashboardInset(cornerRadius: DashboardTabMetrics.insetCornerRadius)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(DashboardPalette.primaryText)
        .dashboardSurface(
            padding: DetachedPaneLayout.shellSurfacePadding,
            cornerRadius: DashboardTabMetrics.surfaceCornerRadius
        )
        .environment(
            \.dashboardChartDisplayOptions,
            ChartDisplayOptions(
                showsMinorGrid: coordinator.chartMinorGridEnabled,
                smoothingAlpha: coordinator.chartSmoothingAlpha,
                areaOpacity: coordinator.chartAreaOpacity,
                plotCornerRadius: DashboardChartTheme.detachedPlotCornerRadius
            )
        )
        .onExitCommand {
            paneController.dismissActivePreview()
        }
    }

    private var paneToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if viewport.isZoomed {
                    Button("Reset Zoom") {
                        viewport.reset()
                        zoomSelectionRect = nil
                        hoveredDate = nil
                    }
                    .buttonStyle(.bordered)
                }

                if paneController.pinnedTarget != nil {
                    Button("Unpin") {
                        paneController.unpin()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Close") {
                    paneController.closePanel(clearSelection: true)
                }
                .buttonStyle(.bordered)
            }

            accessoryToolbar
        }
        .padding(.bottom, 2)
    }
}

struct DetachedPaneEmptyChartState: View {
    let message: String
    var minHeight: CGFloat = DetachedPaneLayout.standardPane.emptyChartMinHeight

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(DashboardPalette.secondaryText)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DashboardPalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
    }
}
