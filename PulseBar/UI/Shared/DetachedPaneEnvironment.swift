import SwiftUI

private struct DetachedPaneStyleKey: EnvironmentKey {
    static let defaultValue = DetachedPaneLayout.standardPane
}

extension EnvironmentValues {
    var detachedPaneStyle: DetachedPaneLayout.PaneStyle {
        get { self[DetachedPaneStyleKey.self] }
        set { self[DetachedPaneStyleKey.self] = newValue }
    }
}
