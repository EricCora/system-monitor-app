import SwiftUI

struct CompactChartSection<RefreshID: Hashable>: View {
    let refreshID: RefreshID
    var height: CGFloat = 92
    let modelProvider: () async -> PreparedTimeSeriesChartModel

    @State private var model = PreparedTimeSeriesChartModel.empty

    var body: some View {
        DashboardMiniChart(model: model, showsPlotBackground: true)
            .frame(height: height)
            .task(id: refreshID) {
                model = await modelProvider()
            }
    }
}
