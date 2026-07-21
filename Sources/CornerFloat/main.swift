import AppKit
import Darwin

private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

if CommandLine.arguments.contains("--hotkey-self-test") {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        var invocationCount = 0
        var verifiedShortcuts: [String] = []
        do {
            for preset in GlobalHotKeyPreset.allCases {
                let expectedInvocationCount = invocationCount + 1
                let controller = try GlobalHotKeyController(shortcut: preset.shortcut) {
                    invocationCount += 1
                }
                guard controller.isRegistered else {
                    fputs("CornerFloat global-hotkey self-test failed: \(preset.shortcut.displayName) was not registered\n", stderr)
                    exit(1)
                }
                let eventStatus = controller.dispatchRegisteredEventForTesting()
                guard eventStatus == noErr else {
                    controller.invalidate()
                    fputs("CornerFloat global-hotkey self-test failed: \(preset.shortcut.displayName) Carbon event dispatch returned \(eventStatus)\n", stderr)
                    exit(1)
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                guard invocationCount == expectedInvocationCount else {
                    controller.invalidate()
                    fputs("CornerFloat global-hotkey self-test failed: \(preset.shortcut.displayName) handler was not delivered exactly once\n", stderr)
                    exit(1)
                }
                controller.invalidate()
                guard !controller.isRegistered else {
                    fputs("CornerFloat global-hotkey self-test failed: \(preset.shortcut.displayName) remained registered after invalidation\n", stderr)
                    exit(1)
                }
                verifiedShortcuts.append(preset.shortcut.displayName)
            }
            print("CornerFloat global-hotkey self-test OK: \(verifiedShortcuts.joined(separator: ", ")) registered, delivered through the Carbon event callback, and unregistered on the main actor without Accessibility permission")
        } catch {
            fputs("CornerFloat global-hotkey self-test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    exit(0)
}

if CommandLine.arguments.contains("--lifecycle-diagnostics") {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let runner = LifecycleDiagnosticsRunner(application: application)
        withExtendedLifetime(runner) {
            runner.start()
            application.run()
        }
    }
    exit(0)
}

if CommandLine.arguments.contains("--self-test") {
    func failSmartAddressTest(_ message: String) -> Never {
        fputs("CornerFloat smart-address self-test failed: \(message)\n", stderr)
        exit(1)
    }

    func expectAddress(_ input: String, _ expected: String?) {
        let actual = SmartAddressResolver.resolve(input)?.absoluteString
        guard actual == expected else {
            failSmartAddressTest("\(String(reflecting: input)) resolved to \(actual ?? "nil"), expected \(expected ?? "nil")")
        }
    }

    func expectSearch(_ input: String) {
        guard let url = SmartAddressResolver.resolve(input),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == "www.google.com",
              components.path == "/search",
              components.queryItems?.first(where: { $0.name == "q" })?.value == input else {
            failSmartAddressTest("\(String(reflecting: input)) did not preserve its Google search query")
        }
    }

    expectAddress(" Google ", "https://www.google.com/")
    expectAddress("google search", "https://www.google.com/")
    expectAddress("ChatGPT", "https://chatgpt.com/auth/login")
    expectAddress("chat gpt", "https://chatgpt.com/auth/login")
    expectAddress("Gmail", "https://mail.google.com/")
    expectAddress("https://example.com/a?x=1", "https://example.com/a?x=1")
    expectAddress("example.com/path", "https://example.com/path")
    expectAddress("localhost:3000", "http://localhost:3000")
    expectAddress("127.0.0.1:5173", "http://127.0.0.1:5173")
    expectAddress("", nil)
    expectAddress("   ", nil)
    expectAddress("https://", nil)
    expectAddress("javascript:alert(1)", nil)
    expectAddress("file:///tmp/private.txt", nil)
    expectSearch("UniMail")
    expectSearch("best cafes near me")
    expectSearch("墨尔本 明天天气")
    expectSearch("C++ URLSession?")
    expectSearch("student@example.com")
    expectSearch("foo/bar")
    expectSearch("site:openai.com ChatGPT")
    expectSearch("3.14")
    expectSearch("v1.20")
    expectSearch("2026.07")
    expectSearch("999.999.999.999")

    if let persistencePrivacyError = URLPersistenceSanitizerSelfTest.run() {
        fputs("CornerFloat URL persistence self-test failed: \(persistencePrivacyError)\n", stderr)
        exit(1)
    }

    let hotKeyPresets = GlobalHotKeyPreset.allCases
    guard hotKeyPresets.count == 4,
          Set(hotKeyPresets.map(\.rawValue)).count == hotKeyPresets.count,
          Set(hotKeyPresets.map { $0.shortcut.displayName }).count == hotKeyPresets.count,
          Set(hotKeyPresets.map { $0.shortcut.modifiers }).count == hotKeyPresets.count,
          Set(hotKeyPresets.map { $0.menuModifiers.rawValue }).count == hotKeyPresets.count,
          hotKeyPresets.allSatisfy({
              $0.shortcut.keyCode == GlobalHotKeyShortcut.togglePanels.keyCode
          }),
          GlobalHotKeyPreset.defaultPreset == .shiftCommandSpace else {
        fputs("CornerFloat global-hotkey preset self-test failed\n", stderr)
        exit(1)
    }

    let closeAllConfirmation = CornerFloatDestructiveAction
        .closeAllPanels(windowCount: 3)
        .confirmation
    let clearRecentsConfirmation = CornerFloatDestructiveAction
        .clearRecents(count: 4)
        .confirmation
    guard closeAllConfirmation.message.contains("3 windows"),
          closeAllConfirmation.destructiveButtonTitle == "Close All Windows",
          clearRecentsConfirmation.message.contains("4 entries"),
          clearRecentsConfirmation.destructiveButtonTitle == "Clear Recents" else {
        fputs("CornerFloat destructive-action policy self-test failed\n", stderr)
        exit(1)
    }

    if let launchAtLoginError = MainActor.assumeIsolated({ LaunchAtLoginSelfTest.run() }) {
        fputs("CornerFloat launch-at-login self-test failed: \(launchAtLoginError)\n", stderr)
        exit(1)
    }

    if let libraryError = WorkspaceLibrarySelfTest.run() {
        fputs("CornerFloat library self-test failed: \(libraryError)\n", stderr)
        exit(1)
    }

    let frame = CGRect(x: 0, y: 40, width: 1440, height: 820)
    let origin = WindowGeometry.bottomRightOrigin(
        windowSize: CGSize(width: 400, height: 500),
        visibleFrame: frame,
        margin: 20
    )
    guard origin == CGPoint(x: 1020, y: 60) else {
        fputs("CornerFloat self-test failed\n", stderr)
        exit(1)
    }

    let expandedEdgeFrame = WindowGeometry.dockedFrame(
        CGRect(x: 1000, y: 100, width: 400, height: 500),
        to: .right,
        in: frame
    )
    guard expandedEdgeFrame == CGRect(x: 1040, y: 100, width: 400, height: 500) else {
        fputs("CornerFloat edge docking self-test failed\n", stderr)
        exit(1)
    }

    let collapsedEdgeFrame = WindowGeometry.collapsedFrame(
        expandedFrame: expandedEdgeFrame,
        at: .right,
        in: frame,
        revealWidth: 10
    )
    guard collapsedEdgeFrame == CGRect(x: 1430, y: 100, width: 400, height: 500) else {
        fputs("CornerFloat edge collapse self-test failed\n", stderr)
        exit(1)
    }

    let secondDisplay = CGRect(x: 1440, y: 40, width: 1920, height: 1040)
    let selectedDisplay = WindowGeometry.bestVisibleFrame(
        for: CGRect(x: 1900, y: 100, width: 400, height: 500),
        candidates: [frame, secondDisplay]
    )
    guard selectedDisplay == secondDisplay else {
        fputs("CornerFloat multi-display selection self-test failed\n", stderr)
        exit(1)
    }

    let maximumIntersectionDisplay = WindowGeometry.bestVisibleFrame(
        for: CGRect(x: 1200, y: 100, width: 600, height: 500),
        candidates: [frame, secondDisplay]
    )
    guard maximumIntersectionDisplay == secondDisplay else {
        fputs("CornerFloat maximum-intersection display self-test failed\n", stderr)
        exit(1)
    }

    print("CornerFloat self-test OK: geometry, edge docking, smart addresses, URL privacy, shortcut presets, Launch at Login state, and portable local libraries")
    exit(0)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appController = AppController()
    application.delegate = appController
    if CommandLine.arguments.contains("--ui-smoke-test") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let applicationMenu = NSApp.mainMenu?.items.first?.submenu
            let applicationMenuTitles = Set(applicationMenu?.items.map(\.title) ?? [])
            func hasShortcut(
                _ title: String,
                key: String,
                modifiers: NSEvent.ModifierFlags
            ) -> Bool {
                guard let item = applicationMenu?.items.first(where: { $0.title == title }) else {
                    return false
                }
                let actualModifiers = item.keyEquivalentModifierMask.intersection(
                    .deviceIndependentFlagsMask
                )
                return item.keyEquivalent == key && actualModifiers == modifiers
            }
            guard hasShortcut("Settings…", key: ",", modifiers: [.command]),
                  hasShortcut("Hide CornerFloat", key: "h", modifiers: [.command]),
                  hasShortcut("Hide Others", key: "h", modifiers: [.command, .option]),
                  applicationMenuTitles.contains("Show All"),
                  !applicationMenuTitles.contains("Hide All Panels") else {
                fputs("CornerFloat UI smoke-test failed: application menu does not use standard Mac settings and hide commands\n", stderr)
                application.terminate(nil)
                return
            }
            let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu
            guard let visibilityItem = viewMenu?.items.first(where: {
                $0.title == "Show or Hide All Panels"
            }),
            visibilityItem.keyEquivalent == " ",
            visibilityItem.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
                == appController.globalShortcutMenuModifiers else {
                fputs("CornerFloat UI smoke-test failed: configurable shortcut is not reflected in the View menu\n", stderr)
                application.terminate(nil)
                return
            }
            guard appController.hasConfiguredUpdateChannel
                    || !applicationMenuTitles.contains("Check for Updates…") else {
                fputs("CornerFloat UI smoke-test failed: source build exposed update action\n", stderr)
                application.terminate(nil)
                return
            }
            guard appController.canManagePasskeyAccess
                    || !applicationMenuTitles.contains("Enable or Review Passkey Access…") else {
                fputs("CornerFloat UI smoke-test failed: source build exposed Passkey action\n", stderr)
                application.terminate(nil)
                return
            }

            guard let panel = appController.panels.first, panel.isVisible else {
                fputs("CornerFloat UI smoke-test failed: missing visible panel\n", stderr)
                application.terminate(nil)
                return
            }

            guard let lifecyclePanel = panel.panel,
                  lifecyclePanel.collectionBehavior.contains(.canJoinAllSpaces),
                  lifecyclePanel.collectionBehavior.contains(.fullScreenAuxiliary) else {
                fputs("CornerFloat UI smoke-test failed: panel is not configured for Spaces and full-screen apps\n", stderr)
                application.terminate(nil)
                return
            }

            let moreMenu = lifecyclePanel.toolbar?.items
                .compactMap { $0 as? NSMenuToolbarItem }
                .first(where: { $0.label == "More" })?
                .menu
            func moreMenuHasShortcut(
                _ title: String,
                key: String,
                modifiers: NSEvent.ModifierFlags
            ) -> Bool {
                guard let item = moreMenu?.items.first(where: { $0.title == title }) else {
                    return false
                }
                return item.keyEquivalent == key
                    && item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
                        == modifiers
            }
            guard moreMenuHasShortcut("Close Current Tab", key: "w", modifiers: [.command]),
                  moreMenuHasShortcut(
                    "Close & Remove This Panel",
                    key: "w",
                    modifiers: [.command, .shift]
                  ) else {
                fputs("CornerFloat UI smoke-test failed: browser More menu has inconsistent close shortcuts\n", stderr)
                application.terminate(nil)
                return
            }

            let requiredPanelStyle: NSWindow.StyleMask = [
                .titled, .closable, .miniaturizable, .resizable
            ]
            guard lifecyclePanel.styleMask.contains(requiredPanelStyle),
                  !lifecyclePanel.titlebarAppearsTransparent,
                  lifecyclePanel.toolbarStyle == .unifiedCompact,
                  lifecyclePanel.standardWindowButton(.closeButton) != nil,
                  lifecyclePanel.standardWindowButton(.miniaturizeButton) != nil,
                  lifecyclePanel.standardWindowButton(.zoomButton) != nil else {
                fputs("CornerFloat UI smoke-test failed: panel chrome is not using the unified native window style\n", stderr)
                application.terminate(nil)
                return
            }

            let initialPanelEdgeSetting = panel.isEdgeAutoHideEnabled
            let initialDefaultEdgeSetting = FloatingPanelController.edgeAutoHideDefaultEnabled
            let edgePreferenceNotifications = NotificationCounter()
            let edgePreferenceObserver = NotificationCenter.default.addObserver(
                forName: .cornerFloatEdgeAutoHidePreferenceDidChange,
                object: nil,
                queue: .main
            ) { _ in
                edgePreferenceNotifications.increment()
            }
            panel.toggleEdgeAutoHide()
            panel.toggleEdgeAutoHide()
            NotificationCenter.default.removeObserver(edgePreferenceObserver)
            guard panel.isEdgeAutoHideEnabled == initialPanelEdgeSetting,
                  FloatingPanelController.edgeAutoHideDefaultEnabled == initialDefaultEdgeSetting,
                  edgePreferenceNotifications.value == 0 else {
                fputs("CornerFloat UI smoke-test failed: panel edge toggle changed the global preference\n", stderr)
                application.terminate(nil)
                return
            }

            let workspaceNotifications = NSWorkspace.shared.notificationCenter
            workspaceNotifications.post(name: NSWorkspace.willSleepNotification, object: nil)
            workspaceNotifications.post(name: NSWorkspace.didWakeNotification, object: nil)
            workspaceNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            NotificationCenter.default.post(
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
            guard panel.isVisible,
                  let lifecycleScreenFrame = lifecyclePanel.screen?.visibleFrame,
                  lifecyclePanel.frame.intersects(lifecycleScreenFrame) else {
                fputs("CornerFloat UI smoke-test failed: panel did not recover after lifecycle notifications\n", stderr)
                application.terminate(nil)
                return
            }

            if let edgePanel = panel.panel, let visibleFrame = edgePanel.screen?.visibleFrame {
                let testEdge: HorizontalScreenEdge = NSEvent.mouseLocation.x > visibleFrame.midX
                    ? .left
                    : .right
                let frameAwayFromPointer = WindowGeometry.dockedFrame(
                    edgePanel.frame,
                    to: testEdge,
                    in: visibleFrame
                )
                edgePanel.setFrame(frameAwayFromPointer, display: true)
            }
            panel.setEdgeAutoHideEnabled(true, persistAsDefault: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                panel.collapseToEdge()
                guard panel.isEdgeAutoHidden,
                      let edgePanel = panel.panel,
                      let visibleFrame = edgePanel.screen?.visibleFrame else {
                    let frameDescription = panel.panel.map { String(describing: $0.frame) } ?? "nil"
                    fputs(
                        "CornerFloat UI smoke-test failed: panel did not collapse to an edge "
                            + "(enabled=\(panel.isEdgeAutoHideEnabled), collapsed=\(panel.isEdgeAutoHidden), "
                            + "visible=\(panel.isVisible), frame=\(frameDescription))\n",
                        stderr
                    )
                    application.terminate(nil)
                    return
                }
                let visibleStrip = edgePanel.frame.intersection(visibleFrame)
                guard abs(visibleStrip.width - FloatingPanelController.edgeAutoHideRevealWidth) < 1 else {
                    fputs("CornerFloat UI smoke-test failed: edge reveal strip has the wrong width\n", stderr)
                    application.terminate(nil)
                    return
                }

                panel.revealFromEdge(activating: false)
                guard !panel.isEdgeAutoHidden else {
                    fputs("CornerFloat UI smoke-test failed: edge panel did not reveal\n", stderr)
                    application.terminate(nil)
                    return
                }
                panel.setEdgeAutoHideEnabled(false, persistAsDefault: false)

                panel.hide()
                guard !panel.isVisible else {
                    fputs("CornerFloat UI smoke-test failed: panel did not hide\n", stderr)
                    application.terminate(nil)
                    return
                }

                panel.show(activating: false)
                panel.minimize()
                panel.show(activating: false)
                guard panel.isVisible, panel.panel?.isMiniaturized == false else {
                    fputs("CornerFloat UI smoke-test failed: minimized panel did not recover\n", stderr)
                    application.terminate(nil)
                    return
                }

                panel.panel?.performClose(nil)
                guard !panel.isVisible, !appController.panels.contains(where: { $0 === panel }) else {
                    fputs("CornerFloat UI smoke-test failed: red close did not remove the panel\n", stderr)
                    application.terminate(nil)
                    return
                }

                appController.showWelcome(thenOpenDefaultPanel: true)
                guard appController.isWelcomeVisible else {
                    fputs("CornerFloat UI smoke-test failed: welcome window did not open\n", stderr)
                    application.terminate(nil)
                    return
                }
                appController.dismissWelcomeForAcceptanceTesting()
                guard !appController.isWelcomeVisible, appController.panels.isEmpty else {
                    fputs("CornerFloat UI smoke-test failed: dismissing welcome unexpectedly opened a panel\n", stderr)
                    application.terminate(nil)
                    return
                }

                appController.showWelcome(thenOpenDefaultPanel: true)
                appController.completeWelcomeForAcceptanceTesting()
                guard !appController.isWelcomeVisible,
                      appController.panels.count == 1,
                      let onboardingPanel = appController.panels.first else {
                    fputs("CornerFloat UI smoke-test failed: onboarding CTA did not open the default panel\n", stderr)
                    application.terminate(nil)
                    return
                }
                onboardingPanel.close()
                guard appController.panels.isEmpty else {
                    fputs("CornerFloat UI smoke-test failed: onboarding panel did not close cleanly\n", stderr)
                    application.terminate(nil)
                    return
                }

                let originalOpenOnLaunch = appController.opensChatGPTOnLaunch
                let originalEdgeAutoHide = appController.isEdgeAutoHideEnabled
                appController.showSettings()
                let firstSettingsIdentity = appController.settingsWindowIdentityForAcceptanceTesting
                appController.showSettings()
                let secondSettingsIdentity = appController.settingsWindowIdentityForAcceptanceTesting
                let initialSettingsState = appController.settingsPresentationStateForAcceptanceTesting

                appController.setOpenChatGPTOnLaunch(!originalOpenOnLaunch)
                appController.setEdgeAutoHideEnabled(!originalEdgeAutoHide)
                let changedSettingsState = appController.settingsPresentationStateForAcceptanceTesting

                appController.setOpenChatGPTOnLaunch(originalOpenOnLaunch)
                appController.setEdgeAutoHideEnabled(originalEdgeAutoHide)
                let restoredSettingsState = appController.settingsPresentationStateForAcceptanceTesting
                appController.closeSettingsForAcceptanceTesting()

                guard firstSettingsIdentity != nil,
                      firstSettingsIdentity == secondSettingsIdentity,
                      initialSettingsState?.opensChatGPTOnLaunch == originalOpenOnLaunch,
                      initialSettingsState?.edgeAutoHideEnabled == originalEdgeAutoHide,
                      initialSettingsState?.shortcutRegistered == appController.isGlobalHotKeyRegistered,
                      initialSettingsState?.shortcutDisplayName.contains(
                        appController.globalShortcutDisplayName
                      ) == true,
                      initialSettingsState?.shortcutDetail.isEmpty == false,
                      initialSettingsState?.shortcutPresetRawValue
                        == appController.globalHotKeyPreset.rawValue,
                      initialSettingsState?.launchAtLoginState
                        == appController.launchAtLoginPresentation.state,
                      initialSettingsState?.launchAtLoginDetail.isEmpty == false,
                      changedSettingsState?.opensChatGPTOnLaunch == !originalOpenOnLaunch,
                      changedSettingsState?.edgeAutoHideEnabled == !originalEdgeAutoHide,
                      restoredSettingsState?.opensChatGPTOnLaunch == originalOpenOnLaunch,
                      restoredSettingsState?.edgeAutoHideEnabled == originalEdgeAutoHide,
                      !appController.isSettingsVisible else {
                    fputs("CornerFloat UI smoke-test failed: settings window reuse or state synchronization failed\n", stderr)
                    application.terminate(nil)
                    return
                }

                appController.showLibraryManager(section: .shortcuts)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard appController.isLibraryManagerVisible else {
                        fputs("CornerFloat UI smoke-test failed: library manager did not open\n", stderr)
                        application.terminate(nil)
                        return
                    }

                    print("CornerFloat UI smoke-test OK: standard Mac shortcuts, configurable global access, Login Item presentation, source-only release actions hidden, Spaces/full-screen flags, screen/sleep/wake recovery, edge collapse/reveal, hide, restore, minimize, onboarding result handling, reusable settings state, standard close and Quick Sites manager")
                    application.terminate(nil)
                }
            }
        }
    }
    application.run()
}
