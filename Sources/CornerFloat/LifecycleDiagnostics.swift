import AppKit
import Darwin

private struct LifecycleDiagnosticReport: Codable {
    let screenCount: Int
    let panelCollectionBehavior: [String]
    let rehomedOffscreenPanel: Bool
    let sleepNotifications: Int
    let wakeNotifications: Int
    let spaceNotifications: Int
    let screenConfigurationCallbacks: Int
    let visibilityCallbacks: Int
    let edgeCollapseCallbacks: Int
    let finalEdgeAutoHidden: Bool
    let idleSeconds: TimeInterval
}

@MainActor
private final class LifecycleProbePanelController: FloatingPanelController {
    private(set) var sleepNotifications = 0
    private(set) var wakeNotifications = 0
    private(set) var spaceNotifications = 0
    private(set) var screenConfigurationCallbacks = 0
    private(set) var visibilityCallbacks = 0
    private(set) var edgeCollapseCallbacks = 0

    init(owner: AppController) {
        super.init(
            owner: owner,
            title: "CornerFloat Lifecycle Diagnostic",
            contentSize: CGSize(width: 340, height: 240)
        )
        let label = NSTextField(
            wrappingLabelWithString: "Running local window lifecycle diagnostics.\nNo special macOS privacy permission is used."
        )
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        installContentView(view)
        setEdgeAutoHideEnabled(false, persistAsDefault: false)
    }

    override func visibilityDidChange(isVisible: Bool) {
        visibilityCallbacks += 1
    }

    override func edgeAutoHideDidChange(isCollapsed: Bool) {
        edgeCollapseCallbacks += 1
    }

    override func systemWillSleep() {
        sleepNotifications += 1
    }

    override func systemDidWake() {
        wakeNotifications += 1
    }

    override func screenConfigurationDidChange() {
        screenConfigurationCallbacks += 1
    }

    override func activeSpaceDidChange() {
        spaceNotifications += 1
    }
}

@MainActor
final class LifecycleDiagnosticsRunner {
    private let application: NSApplication
    private let owner = AppController()
    private var probe: LifecycleProbePanelController?
    private let idleSeconds: TimeInterval

    init(application: NSApplication, arguments: [String] = CommandLine.arguments) {
        self.application = application
        self.idleSeconds = Self.idleDuration(from: arguments)
    }

    func start() {
        guard !NSScreen.screens.isEmpty else {
            fail("macOS reported no screens")
            return
        }

        let probe = LifecycleProbePanelController(owner: owner)
        self.probe = probe
        probe.show(activating: false)

        guard let window = probe.panel,
              window.collectionBehavior.contains(.canJoinAllSpaces),
              window.collectionBehavior.contains(.fullScreenAuxiliary) else {
            fail("panel lacks canJoinAllSpaces or fullScreenAuxiliary")
            return
        }

        // Model a display that has just been unplugged by moving the real
        // NSPanel outside every current display and delivering the production
        // AppKit topology-change notification.
        let screenFrames = NSScreen.screens.map(\.visibleFrame)
        let farX = (screenFrames.map(\.maxX).max() ?? 0) + 4_000
        let farY = (screenFrames.map(\.maxY).max() ?? 0) + 4_000
        window.setFrameOrigin(CGPoint(x: farX, y: farY))
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        let wasRehomed = NSScreen.screens.contains {
            window.frame.intersection($0.visibleFrame).width > 0
                && window.frame.intersection($0.visibleFrame).height > 0
        }
        guard wasRehomed else {
            fail("an offscreen panel was not rehomed after screen configuration change")
            return
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        probe.hide()
        probe.show(activating: false)
        probe.minimize()
        probe.show(activating: false)

        if let visibleFrame = window.screen?.visibleFrame {
            let edge: HorizontalScreenEdge = NSEvent.mouseLocation.x > visibleFrame.midX
                ? .left
                : .right
            window.setFrame(
                WindowGeometry.dockedFrame(window.frame, to: edge, in: visibleFrame),
                display: true
            )
        }
        probe.setEdgeAutoHideEnabled(true, persistAsDefault: false)
        probe.collapseToEdge()
        guard probe.isEdgeAutoHidden else {
            fail("edge collapse did not enter the collapsed state")
            return
        }
        probe.revealFromEdge(activating: false)
        guard !probe.isEdgeAutoHidden else {
            fail("edge reveal did not restore the panel")
            return
        }
        probe.setEdgeAutoHideEnabled(false, persistAsDefault: false)

        guard probe.sleepNotifications >= 1,
              probe.wakeNotifications >= 1,
              probe.spaceNotifications >= 1,
              probe.screenConfigurationCallbacks >= 1,
              probe.visibilityCallbacks >= 5,
              probe.edgeCollapseCallbacks >= 2 else {
            fail("one or more window lifecycle callbacks were not delivered")
            return
        }

        // Keep a hidden AppKit process alive so the companion shell diagnostic
        // can sample real idle CPU and memory usage.
        probe.hide()
        print("CornerFloat lifecycle diagnostic idle-begin")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + idleSeconds) { [weak self] in
            self?.finish(rehomed: wasRehomed)
        }
    }

    private func finish(rehomed: Bool) {
        guard let probe else {
            fail("diagnostic probe was released early")
            return
        }
        let window = probe.panel
        let behavior: [String] = [
            window?.collectionBehavior.contains(.canJoinAllSpaces) == true
                ? "canJoinAllSpaces" : "missing-canJoinAllSpaces",
            window?.collectionBehavior.contains(.fullScreenAuxiliary) == true
                ? "fullScreenAuxiliary" : "missing-fullScreenAuxiliary"
        ]
        let report = LifecycleDiagnosticReport(
            screenCount: NSScreen.screens.count,
            panelCollectionBehavior: behavior,
            rehomedOffscreenPanel: rehomed,
            sleepNotifications: probe.sleepNotifications,
            wakeNotifications: probe.wakeNotifications,
            spaceNotifications: probe.spaceNotifications,
            screenConfigurationCallbacks: probe.screenConfigurationCallbacks,
            visibilityCallbacks: probe.visibilityCallbacks,
            edgeCollapseCallbacks: probe.edgeCollapseCallbacks,
            finalEdgeAutoHidden: probe.isEdgeAutoHidden,
            idleSeconds: idleSeconds
        )
        do {
            let data = try JSONEncoder().encode(report)
            print("CornerFloat lifecycle diagnostic OK: \(String(decoding: data, as: UTF8.self))")
            fflush(stdout)
            probe.close()
            application.terminate(nil)
        } catch {
            fail("could not encode diagnostic report: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        fputs("CornerFloat lifecycle diagnostic failed: \(message)\n", stderr)
        fflush(stderr)
        probe?.close()
        exit(1)
    }

    private static func idleDuration(from arguments: [String]) -> TimeInterval {
        guard let argument = arguments.first(where: { $0.hasPrefix("--idle-seconds=") }),
              let value = TimeInterval(argument.dropFirst("--idle-seconds=".count)) else {
            return 3
        }
        return min(max(value, 0.5), 30)
    }
}
