import AppKit
import SwiftUI
import PulseBarCore

enum DetachedMetricsPaneFamily {
    case temperature
    case memory
    case cpu
}

enum DetachedMetricsPaneTarget: Hashable {
    case temperature(sensorID: String)
    case memory(chart: MemoryPaneChart)
    case cpu(chart: CPUPaneChart)

    var family: DetachedMetricsPaneFamily {
        switch self {
        case .temperature:
            return .temperature
        case .memory:
            return .memory
        case .cpu:
            return .cpu
        }
    }
}

@MainActor
final class DetachedMetricsPaneController: ObservableObject {
    private enum Layout {
        static let preferredPanelWidth: CGFloat = 560
        static let minimumUsablePanelWidth: CGFloat = 420
        static let absoluteMinimumPanelWidth: CGFloat = 260
        static let panelGap: CGFloat = 4
        static let minPanelHeight: CGFloat = 460
        static let minimumPanelHeight: CGFloat = 340
        static let hideDelay: TimeInterval = 0.18
    }

    @Published private(set) var pinnedTarget: DetachedMetricsPaneTarget?
    @Published private(set) var hoveredTarget: DetachedMetricsPaneTarget?
    @Published private(set) var mainListHovering = false
    @Published private(set) var panelHovering = false

    var activeTarget: DetachedMetricsPaneTarget? {
        pinnedTarget ?? hoveredTarget
    }

    private weak var coordinator: AppCoordinator?
    private weak var parentWindow: NSWindow?
    private var panel: DetachedMetricsPanel?
    private var hostingView: NSHostingView<DetachedMetricsPaneHostView>?
    private var hideWorkItem: DispatchWorkItem?
    private var paneInteractionCount = 0

    private var parentMoveObserver: NSObjectProtocol?
    private var parentResizeObserver: NSObjectProtocol?
    private var parentCloseObserver: NSObjectProtocol?
    private var appDeactivateObserver: NSObjectProtocol?

    func preview(
        _ target: DetachedMetricsPaneTarget,
        coordinator: AppCoordinator,
        parentWindow: NSWindow
    ) {
        guard pinnedTarget == nil else { return }
        hoveredTarget = target
        presentPanel(coordinator: coordinator, parentWindow: parentWindow)
    }

    func clearPreview(_ target: DetachedMetricsPaneTarget) {
        guard hoveredTarget == target else { return }
        scheduleHideIfNeeded()
    }

    func pin(
        _ target: DetachedMetricsPaneTarget,
        coordinator: AppCoordinator,
        parentWindow: NSWindow
    ) {
        pinnedTarget = target
        hoveredTarget = nil
        presentPanel(coordinator: coordinator, parentWindow: parentWindow)
    }

    func unpin() {
        pinnedTarget = nil
        if hoveredTarget == nil {
            scheduleHideIfNeeded()
        }
    }

    func setMainListHovering(_ hovering: Bool) {
        mainListHovering = hovering
        if hovering {
            cancelScheduledHide()
        } else {
            scheduleHideIfNeeded()
        }
    }

    func setPanelHovering(_ hovering: Bool) {
        panelHovering = hovering
        if hovering {
            cancelScheduledHide()
        } else {
            scheduleHideIfNeeded()
        }
    }

    func isActive(_ target: DetachedMetricsPaneTarget) -> Bool {
        activeTarget == target
    }

    func beginPaneInteraction() {
        paneInteractionCount += 1
        cancelScheduledHide()
    }

    func endPaneInteraction() {
        paneInteractionCount = max(0, paneInteractionCount - 1)
        scheduleHideIfNeeded()
    }

    func closeIfActive(family: DetachedMetricsPaneFamily, clearSelection: Bool = true) {
        guard activeTarget?.family == family || pinnedTarget?.family == family || hoveredTarget?.family == family else {
            return
        }
        closePanel(clearSelection: clearSelection)
    }

    func reconcileTemperatureSensors(_ visibleSensorIDs: Set<String>) {
        if case .temperature(let sensorID) = pinnedTarget, !visibleSensorIDs.contains(sensorID) {
            pinnedTarget = nil
        }
        if case .temperature(let sensorID) = hoveredTarget, !visibleSensorIDs.contains(sensorID) {
            hoveredTarget = nil
        }
        if activeTarget == nil {
            scheduleHideIfNeeded()
        }
    }

    func closePanel(clearSelection: Bool) {
        cancelScheduledHide()

        if clearSelection {
            pinnedTarget = nil
            hoveredTarget = nil
        } else if pinnedTarget == nil {
            hoveredTarget = nil
        }

        panelHovering = false
        mainListHovering = false
        paneInteractionCount = 0
        panel?.orderOut(nil)
    }

    func shutdown() {
        closePanel(clearSelection: true)
        removeObservers()
    }

    #if DEBUG
    func setPreviewTargetForTesting(_ target: DetachedMetricsPaneTarget?) {
        hoveredTarget = target
    }
    #endif

    private func presentPanel(coordinator: AppCoordinator, parentWindow: NSWindow) {
        self.coordinator = coordinator
        attachObservers(parentWindow: parentWindow)
        ensurePanel(coordinator: coordinator)
        positionPanel(relativeTo: parentWindow)
        cancelScheduledHide()
        panel?.orderFront(nil)
    }

    private func ensurePanel(coordinator: AppCoordinator) {
        if let hostingView {
            hostingView.rootView = DetachedMetricsPaneHostView(coordinator: coordinator, paneController: self)
            return
        }

        let panel = DetachedMetricsPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.preferredPanelWidth, height: Layout.minPanelHeight),
            styleMask: [.utilityWindow, .nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let rootView = DetachedMetricsPaneHostView(coordinator: coordinator, paneController: self)
        let hostingView = NSHostingView(rootView: rootView)
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
    }

    private func positionPanel(relativeTo parentWindow: NSWindow) {
        guard let panel else { return }
        self.parentWindow = parentWindow

        let parentFrame = parentWindow.frame
        let visibleFrame = parentWindow.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)

        panel.setFrame(
            Self.computePanelFrame(parentFrame: parentFrame, visibleFrame: visibleFrame),
            display: true
        )
    }

    private func scheduleHideIfNeeded() {
        guard pinnedTarget == nil else { return }
        guard !mainListHovering else { return }
        guard !panelHovering else { return }
        guard paneInteractionCount == 0 else { return }

        cancelScheduledHide()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pinnedTarget == nil else { return }
            guard !self.mainListHovering else { return }
            guard !self.panelHovering else { return }
            guard self.paneInteractionCount == 0 else { return }
            self.hoveredTarget = nil
            self.panel?.orderOut(nil)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.hideDelay, execute: workItem)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func attachObservers(parentWindow: NSWindow) {
        if self.parentWindow !== parentWindow {
            removeParentObservers()
            self.parentWindow = parentWindow

            parentMoveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self, weak parentWindow] _ in
                Task { @MainActor [weak self, weak parentWindow] in
                    guard let self, let parentWindow else { return }
                    self.positionPanel(relativeTo: parentWindow)
                }
            }
            parentResizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self, weak parentWindow] _ in
                Task { @MainActor [weak self, weak parentWindow] in
                    guard let self, let parentWindow else { return }
                    self.positionPanel(relativeTo: parentWindow)
                }
            }
            parentCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.closePanel(clearSelection: true)
                }
            }
        }

        if appDeactivateObserver == nil {
            appDeactivateObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.closePanel(clearSelection: true)
                }
            }
        }
    }

    static func computePanelFrame(parentFrame: NSRect, visibleFrame: NSRect) -> NSRect {
        let desiredHeight = max(Layout.minPanelHeight, parentFrame.height - 8)
        let maxVisibleHeight = max(Layout.minimumPanelHeight, visibleFrame.height - 8)
        let panelHeight = min(desiredHeight, maxVisibleHeight)

        let availableLeft = max(0, parentFrame.minX - visibleFrame.minX - Layout.panelGap)
        let availableRight = max(0, visibleFrame.maxX - parentFrame.maxX - Layout.panelGap)

        let placeOnLeft: Bool
        if availableLeft >= Layout.minimumUsablePanelWidth {
            placeOnLeft = true
        } else if availableRight >= Layout.minimumUsablePanelWidth {
            placeOnLeft = false
        } else {
            placeOnLeft = availableLeft >= availableRight
        }

        let availableOnChosenSide = placeOnLeft ? availableLeft : availableRight
        let maxVisibleWidth = max(Layout.absoluteMinimumPanelWidth, visibleFrame.width - 8)
        let unclampedWidth = max(Layout.absoluteMinimumPanelWidth, availableOnChosenSide)
        let panelWidth = min(Layout.preferredPanelWidth, min(unclampedWidth, maxVisibleWidth))

        var originX: CGFloat
        if placeOnLeft {
            originX = parentFrame.minX - Layout.panelGap - panelWidth
            originX = max(originX, visibleFrame.minX)
        } else {
            originX = parentFrame.maxX + Layout.panelGap
            originX = min(originX, visibleFrame.maxX - panelWidth)
        }

        var originY = parentFrame.maxY - panelHeight
        originY = min(originY, visibleFrame.maxY - panelHeight)
        originY = max(originY, visibleFrame.minY)

        return NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight)
    }

    private func removeParentObservers() {
        if let parentMoveObserver {
            NotificationCenter.default.removeObserver(parentMoveObserver)
            self.parentMoveObserver = nil
        }
        if let parentResizeObserver {
            NotificationCenter.default.removeObserver(parentResizeObserver)
            self.parentResizeObserver = nil
        }
        if let parentCloseObserver {
            NotificationCenter.default.removeObserver(parentCloseObserver)
            self.parentCloseObserver = nil
        }
    }

    private func removeObservers() {
        removeParentObservers()
        if let appDeactivateObserver {
            NotificationCenter.default.removeObserver(appDeactivateObserver)
            self.appDeactivateObserver = nil
        }
    }
}

final class DetachedMetricsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct DetachedMetricsPaneHostView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var paneController: DetachedMetricsPaneController

    var body: some View {
        content
        .onHover { hovering in
            paneController.setPanelHovering(hovering)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch paneController.activeTarget {
        case .temperature:
            TemperaturePaneContentView(coordinator: coordinator, paneController: paneController)
        case .memory:
            MemoryPaneContentView(coordinator: coordinator, paneController: paneController)
        case .cpu:
            CPUPaneContentView(coordinator: coordinator, paneController: paneController)
        case nil:
            Color.clear
        }
    }
}
