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
            .padding(style == .detached ? 2 : 0)
        }
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
                    .font(style == .detached ? .headline : .subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.center)
                    .frame(
                        minWidth: style == .detached ? 62 : 52,
                        minHeight: style == .detached ? 42 : 34,
                        alignment: .center
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, style == .detached ? 8 : 6)
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
        return style == .detached ? DashboardPalette.sectionFill : Color.white.opacity(0.84)
    }

    private var borderColor: Color {
        style == .detached ? DashboardPalette.chromeBorder : DashboardPalette.chromeBorder
    }
}
