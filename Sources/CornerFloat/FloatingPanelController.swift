import AppKit

extension Notification.Name {
    static let cornerFloatEdgeAutoHidePreferenceDidChange = Notification.Name(
        "CornerFloatEdgeAutoHidePreferenceDidChange"
    )
}

@MainActor
private final class EdgeHoverTrackingView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
    }
}

enum PanelSizePreset: CaseIterable {
    case compact
    case standard
    case spacious

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .spacious: return "Spacious"
        }
    }
}

@MainActor
class FloatingPanelController: NSObject, NSWindowDelegate {
    private static let edgeAutoHidePreferenceKey = "edgeAutoHideEnabled"
    static let edgeAutoHideRevealWidth: CGFloat = 10
    static let edgeAutoHideDockThreshold: CGFloat = 72

    let id = UUID()
    private(set) var displayName: String
    private(set) weak var owner: AppController?
    private(set) var panel: NSPanel?
    private var didTearDown = false
    private let defaultContentSize: CGSize
    private var lifecycleObserverTokens: [NSObjectProtocol] = []
    private var edgeTrackingView: EdgeHoverTrackingView?
    private var edgeCollapseWorkItem: DispatchWorkItem?
    private var edgeDockUpdateWorkItem: DispatchWorkItem?
    private var expandedEdgeFrame: CGRect?
    private var dockedEdge: HorizontalScreenEdge?
    private var isApplyingEdgeFrame = false
    private var isLiveResizing = false
    private(set) var isEdgeAutoHidden = false
    private(set) var isEdgeAutoHideEnabled: Bool

    static var edgeAutoHideDefaultEnabled: Bool {
        UserDefaults.standard.bool(forKey: edgeAutoHidePreferenceKey)
    }

    var isVisible: Bool {
        guard let panel else { return false }
        return panel.isVisible && !panel.isMiniaturized
    }

    var opacity: CGFloat = 1 {
        didSet {
            opacity = min(max(opacity, 0.2), 1)
            panel?.alphaValue = opacity
        }
    }

    var isClickThrough = false {
        didSet {
            panel?.ignoresMouseEvents = isClickThrough
            if isClickThrough {
                revealFromEdge(animated: false)
                cancelEdgeCollapse()
            } else if isEdgeAutoHideEnabled {
                scheduleEdgeCollapse()
            }
        }
    }

    init(owner: AppController, title: String, contentSize: CGSize) {
        self.owner = owner
        self.displayName = title
        self.defaultContentSize = contentSize
        self.isEdgeAutoHideEnabled = Self.edgeAutoHideDefaultEnabled
        super.init()
        createPanel(title: title, contentSize: contentSize)
        installLifecycleObservers()
    }

    func installContentView(_ contentView: NSView) {
        panel?.contentView = contentView
        installEdgeTrackingView(in: contentView)
    }

    func updateDisplayName(_ name: String) {
        displayName = name
        panel?.title = name
        owner?.requestMenuRefresh()
    }

    func show(activating: Bool = true) {
        guard let panel else { return }
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        if activating, isEdgeAutoHidden {
            revealFromEdge(animated: true)
        }
        if activating {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        visibilityDidChange(isVisible: true)
        owner?.requestMenuRefresh()
        if isEdgeAutoHideEnabled, !isEdgeAutoHidden {
            scheduleEdgeCollapse(after: activating ? 1.6 : 1.0)
        }
    }

    func hide() {
        cancelEdgeCollapse()
        panel?.orderOut(nil)
        visibilityDidChange(isVisible: false)
        owner?.requestMenuRefresh()
    }

    func toggleVisibility() {
        isVisible ? hide() : show()
    }

    func minimize() {
        revealFromEdge(animated: false)
        cancelEdgeCollapse()
        panel?.miniaturize(nil)
        visibilityDidChange(isVisible: false)
        owner?.requestMenuRefresh()
    }

    func moveToBottomRight() {
        guard let panel else { return }
        revealFromEdge(animated: false)
        fitWindowInsideCurrentScreen()
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = WindowGeometry.bottomRightOrigin(
            windowSize: panel.frame.size,
            visibleFrame: visibleFrame,
            cascadeIndex: owner?.index(of: self) ?? 0
        )
        panel.setFrameOrigin(origin)
        if isEdgeAutoHideEnabled {
            dockedEdge = .right
            scheduleEdgeDockUpdate()
        }
    }

    func setEdgeAutoHideEnabled(
        _ enabled: Bool,
        persistAsDefault: Bool = false
    ) {
        guard isEdgeAutoHideEnabled != enabled else {
            if persistAsDefault {
                Self.persistEdgeAutoHideDefault(enabled)
            }
            return
        }

        isEdgeAutoHideEnabled = enabled
        if enabled {
            installEdgeTrackingViewIfNeeded()
            if let panel, let visibleFrame = visibleFrameForWindow(panel) {
                let edge = WindowGeometry.nearestHorizontalEdge(
                    to: panel.frame,
                    in: visibleFrame
                )
                dockedEdge = edge
                let dockedFrame = WindowGeometry.dockedFrame(
                    panel.frame,
                    to: edge,
                    in: visibleFrame
                )
                expandedEdgeFrame = dockedFrame
                applyEdgeFrame(dockedFrame, animated: panel.isVisible)
            }
            scheduleEdgeDockUpdate(after: 0)
        } else {
            cancelEdgeCollapse()
            edgeDockUpdateWorkItem?.cancel()
            edgeDockUpdateWorkItem = nil
            revealFromEdge(animated: true)
            expandedEdgeFrame = nil
            dockedEdge = nil
        }

        if persistAsDefault {
            Self.persistEdgeAutoHideDefault(enabled)
        }
        owner?.requestMenuRefresh()
    }

    func toggleEdgeAutoHide() {
        // A panel-level toggle is intentionally local. The app-level command
        // persists and broadcasts the shared default explicitly.
        setEdgeAutoHideEnabled(!isEdgeAutoHideEnabled, persistAsDefault: false)
    }

    func revealFromEdge(activating: Bool) {
        revealFromEdge(animated: true)
        if activating {
            show(activating: true)
        }
    }

    func collapseToEdge() {
        collapseToEdgeIfPossible(ignoringPointerLocation: true)
    }

    static func persistEdgeAutoHideDefault(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: edgeAutoHidePreferenceKey)
        NotificationCenter.default.post(
            name: .cornerFloatEdgeAutoHidePreferenceDidChange,
            object: nil,
            userInfo: ["enabled": enabled]
        )
    }

    func resizeWindow(by factor: CGFloat) {
        guard let panel, factor > 0 else { return }
        let currentSize = panel.contentView?.bounds.size ?? panel.frame.size
        setContentSize(
            CGSize(width: currentSize.width * factor, height: currentSize.height * factor)
        )
    }

    func resetWindowSize() {
        setContentSize(preferredContentSize(for: .standard))
    }

    func applySizePreset(_ preset: PanelSizePreset) {
        setContentSize(preferredContentSize(for: preset))
    }

    func preferredContentSize(for preset: PanelSizePreset) -> CGSize {
        let scale: CGFloat
        switch preset {
        case .compact: scale = 0.80
        case .standard: scale = 1
        case .spacious: scale = 1.30
        }
        return CGSize(
            width: defaultContentSize.width * scale,
            height: defaultContentSize.height * scale
        )
    }

    func setOpacity(_ value: CGFloat) {
        opacity = value
        owner?.requestMenuRefresh()
    }

    func toggleClickThrough() {
        isClickThrough.toggle()
        owner?.requestMenuRefresh()
    }

    func close() {
        guard let panel else {
            tearDownIfNeeded()
            return
        }
        panel.close()
    }

    func prepareForClose() {
        // Subclasses override when they own streams or observers.
    }

    func visibilityDidChange(isVisible: Bool) {
        // Subclasses can pause expensive work while hidden.
    }

    func edgeAutoHideDidChange(isCollapsed: Bool) {
        // Subclasses can pause expensive work while only the reveal strip is visible.
    }

    func systemWillSleep() {
        // Subclasses can suspend streams or network work before sleep.
    }

    func systemDidWake() {
        // Subclasses can safely resume work after wake.
    }

    func screenConfigurationDidChange() {
        // Subclasses can update display-dependent resources.
    }

    func activeSpaceDidChange() {
        // Subclasses can react to Space or full-screen transitions.
    }

    func windowWillClose(_ notification: Notification) {
        tearDownIfNeeded()
        panel = nil
    }

    func windowDidMiniaturize(_ notification: Notification) {
        cancelEdgeCollapse()
        visibilityDidChange(isVisible: false)
        owner?.requestMenuRefresh()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        visibilityDidChange(isVisible: true)
        if isEdgeAutoHideEnabled {
            scheduleEdgeCollapse()
        }
        owner?.requestMenuRefresh()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if isEdgeAutoHidden,
           let panel,
           panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) {
            revealFromEdge(animated: true)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if isEdgeAutoHideEnabled {
            scheduleEdgeCollapse(after: 0.8)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingEdgeFrame, isEdgeAutoHideEnabled, !isEdgeAutoHidden else { return }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            expandedEdgeFrame = nil
            dockedEdge = nil
        }
        scheduleEdgeDockUpdate()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard !isApplyingEdgeFrame, !isEdgeAutoHidden else { return }
        isLiveResizing = true
        cancelEdgeCollapse()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard isLiveResizing else { return }
        isLiveResizing = false
        guard let size = panel?.contentView?.bounds.size else { return }
        contentSizeDidChange(to: size)
        if isEdgeAutoHideEnabled {
            scheduleEdgeDockUpdate()
        }
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        let current = window.contentView?.bounds.size ?? window.frame.size
        let standard = preferredContentSize(for: .standard)
        let spacious = preferredContentSize(for: .spacious)
        let standardDistance = abs(current.width - standard.width) + abs(current.height - standard.height)
        let spaciousDistance = abs(current.width - spacious.width) + abs(current.height - spacious.height)
        setContentSize(spaciousDistance <= standardDistance ? standard : spacious)
        return false
    }

    func contentSizeDidChange(to size: CGSize) {
        // Subclasses can persist a preferred size.
    }

    func constrainedContentSize(
        _ requestedSize: CGSize,
        minimumSize: CGSize,
        maximumSize: CGSize
    ) -> CGSize {
        CGSize(
            width: min(max(requestedSize.width, minimumSize.width), maximumSize.width),
            height: min(max(requestedSize.height, minimumSize.height), maximumSize.height)
        )
    }

    func normalizeRestoredPresentation() {
        // Subclasses can repair source-specific layout after a raw workspace
        // frame has been restored.
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let screen = sender.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return frameSize }
        let maximumFrameSize = CGSize(
            width: max(1, visibleFrame.width - 24),
            height: max(1, visibleFrame.height - 24)
        )
        return CGSize(
            width: min(frameSize.width, maximumFrameSize.width),
            height: min(frameSize.height, maximumFrameSize.height)
        )
    }

    func windowDidChangeScreen(_ notification: Notification) {
        // This delegate callback also fires during a normal cross-display drag.
        // Rehoming here fights the user's pointer and can snap the panel back.
        // Actual display topology changes are handled by
        // didChangeScreenParametersNotification below.
        screenConfigurationDidChange()
    }

    private func createPanel(title: String, contentSize: CGSize) {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.toolbarStyle = .unifiedCompact
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.titlebarSeparatorStyle = .line
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.contentMinSize = NSSize(width: 260, height: 180)
        panel.standardWindowButton(.zoomButton)?.toolTip = "Switch between standard and spacious sizes"
        panel.delegate = self
        panel.alphaValue = opacity
        panel.ignoresMouseEvents = isClickThrough
        self.panel = panel
        moveToBottomRight()
    }

    func setContentSize(_ requestedSize: CGSize) {
        guard let panel else { return }
        revealFromEdge(animated: false)
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let currentContentSize = panel.contentView?.bounds.size ?? requestedSize
        let chromeWidth = max(panel.frame.width - currentContentSize.width, 0)
        let chromeHeight = max(panel.frame.height - currentContentSize.height, 0)
        let maximumSize = CGSize(
            width: max(260, visibleFrame.width - 24 - chromeWidth),
            height: max(180, visibleFrame.height - 24 - chromeHeight)
        )
        let minimumSize = panel.contentMinSize

        let size = constrainedContentSize(
            requestedSize,
            minimumSize: minimumSize,
            maximumSize: maximumSize
        )

        let oldFrame = panel.frame
        var targetFrame = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: size)
        )
        targetFrame.origin = CGPoint(
            x: oldFrame.maxX - targetFrame.width,
            y: oldFrame.minY
        )

        targetFrame.origin.x = min(
            max(targetFrame.origin.x, visibleFrame.minX + 12),
            visibleFrame.maxX - targetFrame.width - 12
        )
        targetFrame.origin.y = min(
            max(targetFrame.origin.y, visibleFrame.minY + 12),
            visibleFrame.maxY - targetFrame.height - 12
        )

        let shouldAnimate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(targetFrame, display: true, animate: shouldAnimate)
        contentSizeDidChange(to: size)
        if isEdgeAutoHideEnabled {
            scheduleEdgeDockUpdate()
        }
        owner?.requestMenuRefresh()
    }

    private func fitWindowInsideCurrentScreen() {
        guard let panel else { return }
        let visibleFrame = visibleFrameForWindow(panel) ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return }
        let frame = WindowGeometry.clampedFrame(panel.frame, inside: visibleFrame)
        applyEdgeFrame(frame, animated: false)
    }

    private func installEdgeTrackingView(in contentView: NSView) {
        edgeTrackingView?.removeFromSuperview()

        let trackingView = EdgeHoverTrackingView(frame: contentView.bounds)
        trackingView.translatesAutoresizingMaskIntoConstraints = false
        trackingView.onPointerEntered = { [weak self] in
            guard let self, self.isEdgeAutoHideEnabled, !self.isClickThrough else { return }
            self.cancelEdgeCollapse()
            self.revealFromEdge(animated: true)
        }
        trackingView.onPointerExited = { [weak self] in
            guard let self, self.isEdgeAutoHideEnabled, !self.isClickThrough else { return }
            self.scheduleEdgeCollapse()
        }
        contentView.addSubview(trackingView)
        NSLayoutConstraint.activate([
            trackingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            trackingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            trackingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            trackingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        edgeTrackingView = trackingView
    }

    private func installEdgeTrackingViewIfNeeded() {
        guard edgeTrackingView == nil, let contentView = panel?.contentView else { return }
        installEdgeTrackingView(in: contentView)
    }

    private func scheduleEdgeDockUpdate(after delay: TimeInterval = 0.35) {
        edgeDockUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateEdgeDockAndScheduleCollapse()
        }
        edgeDockUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func updateEdgeDockAndScheduleCollapse() {
        edgeDockUpdateWorkItem = nil
        guard isEdgeAutoHideEnabled,
              !isEdgeAutoHidden,
              !isLiveResizing,
              !isClickThrough,
              let panel,
              panel.isVisible,
              !panel.isMiniaturized,
              let visibleFrame = visibleFrameForWindow(panel) else { return }

        let nearestEdge = WindowGeometry.nearestHorizontalEdge(
            to: panel.frame,
            in: visibleFrame
        )
        let alreadyDocked = dockedEdge != nil
        guard alreadyDocked || WindowGeometry.isNearHorizontalEdge(
            nearestEdge,
            windowFrame: panel.frame,
            visibleFrame: visibleFrame,
            threshold: Self.edgeAutoHideDockThreshold
        ) else {
            expandedEdgeFrame = nil
            dockedEdge = nil
            return
        }

        dockedEdge = nearestEdge
        expandedEdgeFrame = WindowGeometry.dockedFrame(
            panel.frame,
            to: nearestEdge,
            in: visibleFrame
        )
        scheduleEdgeCollapse()
    }

    private func scheduleEdgeCollapse(after delay: TimeInterval = 0.7) {
        cancelEdgeCollapse()
        guard isEdgeAutoHideEnabled, !isEdgeAutoHidden, !isClickThrough else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.collapseToEdgeIfPossible()
        }
        edgeCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelEdgeCollapse() {
        edgeCollapseWorkItem?.cancel()
        edgeCollapseWorkItem = nil
    }

    private func collapseToEdgeIfPossible(ignoringPointerLocation: Bool = false) {
        edgeCollapseWorkItem = nil
        guard isEdgeAutoHideEnabled,
              !isEdgeAutoHidden,
              !isLiveResizing,
              !isClickThrough,
              let panel,
              panel.isVisible,
              !panel.isMiniaturized,
              let visibleFrame = visibleFrameForWindow(panel) else { return }

        if !ignoringPointerLocation,
           panel.frame.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) {
            scheduleEdgeCollapse(after: 0.35)
            return
        }

        let edge = dockedEdge ?? WindowGeometry.nearestHorizontalEdge(
            to: panel.frame,
            in: visibleFrame
        )
        let alreadyDocked = dockedEdge != nil
        guard alreadyDocked || WindowGeometry.isNearHorizontalEdge(
            edge,
            windowFrame: panel.frame,
            visibleFrame: visibleFrame,
            threshold: Self.edgeAutoHideDockThreshold
        ) else {
            expandedEdgeFrame = nil
            dockedEdge = nil
            return
        }

        let expandedFrame = WindowGeometry.dockedFrame(
            panel.frame,
            to: edge,
            in: visibleFrame
        )
        if panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            panel.resignKey()
        }
        self.expandedEdgeFrame = expandedFrame
        dockedEdge = edge
        isEdgeAutoHidden = true
        edgeAutoHideDidChange(isCollapsed: true)
        let collapsedFrame = WindowGeometry.collapsedFrame(
            expandedFrame: expandedFrame,
            at: edge,
            in: visibleFrame,
            revealWidth: Self.edgeAutoHideRevealWidth
        )
        applyEdgeFrame(collapsedFrame, animated: true)
        owner?.requestMenuRefresh()
    }

    private func revealFromEdge(animated: Bool) {
        cancelEdgeCollapse()
        guard isEdgeAutoHidden, let panel else { return }
        let visibleFrame = visibleFrameForWindow(panel) ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else { return }

        let edge = dockedEdge ?? WindowGeometry.nearestHorizontalEdge(
            to: panel.frame,
            in: visibleFrame
        )
        let candidate = expandedEdgeFrame ?? panel.frame
        let expandedFrame = WindowGeometry.dockedFrame(
            candidate,
            to: edge,
            in: visibleFrame
        )
        isEdgeAutoHidden = false
        self.expandedEdgeFrame = expandedFrame
        dockedEdge = edge
        edgeAutoHideDidChange(isCollapsed: false)
        applyEdgeFrame(expandedFrame, animated: animated)
        owner?.requestMenuRefresh()
    }

    private func applyEdgeFrame(_ frame: CGRect, animated: Bool) {
        guard let panel, frame != panel.frame else { return }
        isApplyingEdgeFrame = true
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(frame, display: true, animate: shouldAnimate)
        isApplyingEdgeFrame = false
    }

    private func visibleFrameForWindow(_ window: NSWindow) -> CGRect? {
        if let screen = window.screen {
            return screen.visibleFrame
        }
        let candidates = NSScreen.screens.map(\.visibleFrame)
        return WindowGeometry.bestVisibleFrame(
            for: expandedEdgeFrame ?? window.frame,
            candidates: candidates,
            fallback: NSScreen.main?.visibleFrame
        )
    }

    private func rehomeAfterScreenConfigurationChange() {
        guard let panel else { return }
        let wasCollapsed = isEdgeAutoHidden
        if wasCollapsed {
            isEdgeAutoHidden = false
        }

        let referenceFrame = expandedEdgeFrame ?? panel.frame
        let candidates = NSScreen.screens.map(\.visibleFrame)
        guard let visibleFrame = WindowGeometry.bestVisibleFrame(
            for: referenceFrame,
            candidates: candidates,
            fallback: NSScreen.main?.visibleFrame
        ) else { return }

        var targetFrame = WindowGeometry.clampedFrame(referenceFrame, inside: visibleFrame)
        if isEdgeAutoHideEnabled, let edge = dockedEdge {
            targetFrame = WindowGeometry.dockedFrame(targetFrame, to: edge, in: visibleFrame)
            expandedEdgeFrame = targetFrame
        }

        if wasCollapsed, isEdgeAutoHideEnabled, let edge = dockedEdge {
            isEdgeAutoHidden = true
            targetFrame = WindowGeometry.collapsedFrame(
                expandedFrame: targetFrame,
                at: edge,
                in: visibleFrame,
                revealWidth: Self.edgeAutoHideRevealWidth
            )
        }
        applyEdgeFrame(targetFrame, animated: false)
        screenConfigurationDidChange()
    }

    private func installLifecycleObservers() {
        let notificationCenter = NotificationCenter.default
        lifecycleObserverTokens.append(notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rehomeAfterScreenConfigurationChange()
            }
        })
        lifecycleObserverTokens.append(notificationCenter.addObserver(
            forName: .cornerFloatEdgeAutoHidePreferenceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let enabled = notification.userInfo?["enabled"] as? Bool else { return }
            MainActor.assumeIsolated {
                self?.setEdgeAutoHideEnabled(enabled, persistAsDefault: false)
            }
        })

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        lifecycleObserverTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelEdgeCollapse()
                self?.systemWillSleep()
            }
        })
        lifecycleObserverTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rehomeAfterScreenConfigurationChange()
                self.systemDidWake()
                if self.isVisible, !self.isEdgeAutoHidden {
                    self.panel?.orderFrontRegardless()
                }
            }
        })
        lifecycleObserverTokens.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.activeSpaceDidChange()
                if self.isVisible {
                    self.panel?.orderFrontRegardless()
                }
            }
        })
    }

    private func removeLifecycleObservers() {
        let defaultCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for token in lifecycleObserverTokens {
            defaultCenter.removeObserver(token)
            workspaceCenter.removeObserver(token)
        }
        lifecycleObserverTokens.removeAll()
    }

    private func tearDownIfNeeded() {
        guard !didTearDown else { return }
        didTearDown = true
        cancelEdgeCollapse()
        edgeDockUpdateWorkItem?.cancel()
        edgeDockUpdateWorkItem = nil
        edgeTrackingView?.onPointerEntered = nil
        edgeTrackingView?.onPointerExited = nil
        edgeTrackingView = nil
        removeLifecycleObservers()
        prepareForClose()
        owner?.panelDidClose(self)
    }
}
