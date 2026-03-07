import SwiftUI

struct HistoryWindowSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    @ObservedObject var paneController: DetachedMetricsPaneController
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                HistoryWindowSegmentButton(
                    option: option,
                    selection: $selection,
                    paneController: paneController,
                    label: label
                )

                if option != options.last {
                    Divider()
                        .frame(height: 18)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct HistoryWindowSegmentButton<Option: Hashable>: View {
    let option: Option
    @Binding var selection: Option
    @ObservedObject var paneController: DetachedMetricsPaneController
    let label: (Option) -> String

    @State private var interactionStarted = false

    var body: some View {
        Button {
            selection = option
        } label: {
            Text(label(option))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .font(.headline)
        }
        .buttonStyle(.plain)
        .background(selection == option ? Color.accentColor : Color.clear)
        .foregroundStyle(selection == option ? Color.white : Color.primary)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !interactionStarted else { return }
                    interactionStarted = true
                    paneController.beginPaneInteraction()
                }
                .onEnded { _ in
                    guard interactionStarted else { return }
                    interactionStarted = false
                    paneController.endPaneInteraction()
                }
        )
        .onDisappear {
            guard interactionStarted else { return }
            interactionStarted = false
            paneController.endPaneInteraction()
        }
    }
}
