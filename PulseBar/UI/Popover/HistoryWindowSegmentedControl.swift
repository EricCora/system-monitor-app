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
                .padding(.vertical, style == .detached ? 7 : 6)
                .padding(.horizontal, style == .detached ? 12 : 10)
                .background(backgroundColor, in: Capsule())
                .foregroundStyle(selection == option ? Color.white : Color.primary)
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
            return .accentColor
        }
        return style == .detached ? Color.primary.opacity(0.08) : Color.primary.opacity(0.06)
    }

    private var borderColor: Color {
        style == .detached ? Color.primary.opacity(0.08) : Color.primary.opacity(0.12)
    }
}
