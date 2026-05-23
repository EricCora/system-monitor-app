import SwiftUI

/// Defers history reloads while a detached pane chart is hovered or zoom-selected.
struct DetachedPaneHistoryRefresh: ViewModifier {
    let contextRefreshID: String
    let refreshTriggerID: String
    let isInteractionActive: Bool
    let onContextChange: () -> Void
    let refresh: () async -> Void

    @State private var lastRefreshContextID = ""
    @State private var deferredRefreshTriggerID: String?

    func body(content: Content) -> some View {
        content
            .task(id: refreshTriggerID) {
                if lastRefreshContextID != contextRefreshID {
                    onContextChange()
                    lastRefreshContextID = contextRefreshID
                }
                if isInteractionActive {
                    deferredRefreshTriggerID = refreshTriggerID
                    return
                }
                await refresh()
            }
            .onChange(of: isInteractionActive) { isActive in
                guard !isActive, deferredRefreshTriggerID != nil else { return }
                deferredRefreshTriggerID = nil
                Task { await refresh() }
            }
    }
}

extension View {
    func detachedPaneHistoryRefresh(
        contextRefreshID: String,
        refreshTriggerID: String,
        isInteractionActive: Bool,
        onContextChange: @escaping () -> Void,
        refresh: @escaping () async -> Void
    ) -> some View {
        modifier(
            DetachedPaneHistoryRefresh(
                contextRefreshID: contextRefreshID,
                refreshTriggerID: refreshTriggerID,
                isInteractionActive: isInteractionActive,
                onContextChange: onContextChange,
                refresh: refresh
            )
        )
    }
}
