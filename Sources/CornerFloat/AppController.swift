import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private static let openOnLaunchKey = "openChatGPTOnLaunch"
    private static let lastWebURLKey = "lastWebURL"
    private static let globalHotKeyPresetKey = "globalHotKeyPreset"
    private(set) var panels: [FloatingPanelController] = []
    private var statusBarController: StatusBarController?
    private var mainMenuController: MainMenuController?
    private var workspaceLibraryController: WorkspaceLibraryController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private let productPagesController = ProductPagesController()
    private let updateController = UpdateController()
    private let passkeyAuthorizationCoordinator = PasskeyAuthorizationCoordinator()
    private let launchAtLoginController = LaunchAtLoginController()
    private var globalHotKeyController: GlobalHotKeyController?
    private(set) var globalHotKeyError: String?
    private let workspaceLibrary = WorkspaceLibraryStore()
    private var webPanelURLs: [UUID: URL] = [:]
    private var lastObservedWebURL: String?

    var opensChatGPTOnLaunch: Bool {
        UserDefaults.standard.bool(forKey: Self.openOnLaunchKey)
    }

    var hasVisiblePanels: Bool {
        panels.contains { $0.isVisible }
    }

    var activePanel: FloatingPanelController? {
        panels.first { $0.panel?.isKeyWindow == true }
            ?? panels.reversed().first { $0.isVisible }
            ?? panels.last
    }

    var activeWebPanel: WebPanelController? {
        activePanel as? WebPanelController
    }

    var bookmarks: [BrowserBookmark] {
        workspaceLibrary.snapshot.bookmarks
    }

    var recentDestinations: [RecentDestination] {
        workspaceLibrary.snapshot.recents
    }

    var quickSites: [AddressShortcut] {
        workspaceLibrary.snapshot.shortcuts
    }

    var savedWorkspaces: [SavedWorkspace] {
        workspaceLibrary.snapshot.workspaces
    }

    var canBookmarkActivePage: Bool {
        currentURL(for: activeWebPanel) != nil
    }

    var globalShortcutDisplayName: String {
        globalHotKeyController?.shortcut.displayName ?? globalHotKeyPreset.shortcut.displayName
    }

    var globalHotKeyPreset: GlobalHotKeyPreset {
        guard let rawValue = UserDefaults.standard.string(forKey: Self.globalHotKeyPresetKey),
              let preset = GlobalHotKeyPreset(rawValue: rawValue) else {
            return .defaultPreset
        }
        return preset
    }

    var globalShortcutMenuModifiers: NSEvent.ModifierFlags {
        globalHotKeyPreset.menuModifiers
    }

    var isGlobalHotKeyRegistered: Bool {
        globalHotKeyController?.isRegistered == true
    }

    var isEdgeAutoHideEnabled: Bool {
        FloatingPanelController.edgeAutoHideDefaultEnabled
    }

    var launchAtLoginPresentation: LaunchAtLoginPresentation {
        launchAtLoginController.presentation
    }

    var canCheckForUpdates: Bool {
        updateController.canCheckForUpdates
    }

    var hasConfiguredUpdateChannel: Bool {
        updateController.isConfigured
    }

    var canManagePasskeyAccess: Bool {
        FileManager.default.fileExists(
            atPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/embedded.provisionprofile")
                .path
        )
    }

    var isLibraryManagerVisible: Bool {
        workspaceLibraryController?.isVisible == true
    }

    var isSettingsVisible: Bool {
        settingsWindowController?.isVisible == true
    }

    var isWelcomeVisible: Bool {
        onboardingController?.window?.isVisible == true
    }

    var settingsWindowIdentityForAcceptanceTesting: ObjectIdentifier? {
        settingsWindowController?.window.map(ObjectIdentifier.init)
    }

    var settingsPresentationStateForAcceptanceTesting: SettingsPresentationState? {
        settingsWindowController?.presentationState
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            Self.openOnLaunchKey: true,
            Self.globalHotKeyPresetKey: GlobalHotKeyPreset.defaultPreset.rawValue
        ])
        NSApp.setActivationPolicy(.accessory)
        mainMenuController = MainMenuController(owner: self)
        mainMenuController?.install()
        statusBarController = StatusBarController(owner: self)
        workspaceLibraryController = WorkspaceLibraryController(owner: self)
        installGlobalHotKey()
        lastObservedWebURL = sanitizedLastWebURLPreference()?.absoluteString
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        if let warning = workspaceLibrary.loadWarning {
            fputs("CornerFloat library warning: \(warning)\n", stderr)
            let isReadOnly = workspaceLibrary.isReadOnly
            DispatchQueue.main.async { [weak self] in
                self?.showError(
                    title: isReadOnly ? "Library Opened Read-Only" : "Library Recovered",
                    message: isReadOnly
                        ? warning
                        : "CornerFloat could not read the saved library and preserved the unreadable file before starting a clean library. \(warning)"
                )
            }
        }

        if CommandLine.arguments.contains("--google-login-acceptance") {
            if let url = URL(string: "https://chatgpt.com/auth/login") {
                addWebPanel(url: url)
            }
        } else if CommandLine.arguments.contains("--demo-panel")
            || CommandLine.arguments.contains("--ui-smoke-test") {
            openOfflineDemoPanel()
        } else if !UserDefaults.standard.bool(forKey: OnboardingWindowController.completionKey) {
            showWelcome(thenOpenDefaultPanel: true)
        } else if opensChatGPTOnLaunch {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.panels.isEmpty else { return }
                self.openChatGPTPanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKeyController?.invalidate()
        globalHotKeyController = nil
        NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object: nil)
        for panel in panels {
            panel.prepareForClose()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if let panel = activePanel {
            panel.show()
        } else {
            openChatGPTPanel()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let webURLs = urls.filter {
            guard let scheme = $0.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
        guard !webURLs.isEmpty else {
            showError(
                title: "Could Not Open Link",
                message: "CornerFloat can open HTTP and HTTPS web links."
            )
            return
        }
        if let target = activeWebPanel
            ?? panels.reversed().compactMap({ $0 as? WebPanelController }).first {
            for url in webURLs {
                target.openNewTab(url: url)
            }
            target.show()
            return
        }

        let target = addWebPanel(url: webURLs[0])
        for url in webURLs.dropFirst() {
            target.openNewTab(url: url)
        }
    }

    func openChatGPTPanel() {
        guard let url = URL(string: "https://chatgpt.com/") else { return }
        addWebPanel(url: url)
    }

    func promptForWebPage() {
        let previousApplication = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        let savedAddress = sanitizedLastWebURLPreference()?.absoluteString
        field.stringValue = savedAddress ?? "https://chatgpt.com/"
        field.placeholderString = "Website, address, or search"

        let alert = NSAlert()
        alert.messageText = "Open Floating Web Page"
        alert.informativeText = "Enter a URL, site name, or search. Plain text uses Google Search."
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        field.setAccessibilityLabel("Website address or search")
        alert.window.initialFirstResponder = field
        DispatchQueue.main.async {
            field.selectText(nil)
        }

        guard alert.runModal() == .alertFirstButtonReturn else {
            if previousApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApplication?.activate(options: [])
            }
            return
        }
        guard let url = resolveAddress(field.stringValue) else {
            showError(
                title: "Could Not Open Page",
                message: "Enter a website, address, or search. Web addresses must use HTTP or HTTPS."
            )
            return
        }
        addWebPanel(url: url)
    }

    func requestCloseAllPanels() {
        guard !panels.isEmpty,
              confirmDestructiveAction(.closeAllPanels(windowCount: panels.count)) else {
            return
        }
        closeAllPanels()
    }

    private func closeAllPanels() {
        let currentPanels = panels
        for panel in currentPanels {
            panel.close()
        }
    }

    func hideAllPanels() {
        for panel in panels {
            panel.hide()
        }
    }

    func showAllPanels() {
        for panel in panels {
            panel.show(activating: false)
        }
        activePanel?.show()
    }

    func toggleAllPanelsVisibility() {
        if hasVisiblePanels {
            hideAllPanels()
        } else if panels.isEmpty {
            openChatGPTPanel()
        } else {
            showAllPanels()
        }
    }

    func toggleEdgeAutoHide() {
        setEdgeAutoHideEnabled(!FloatingPanelController.edgeAutoHideDefaultEnabled)
    }

    func setEdgeAutoHideEnabled(_ enabled: Bool) {
        guard enabled != FloatingPanelController.edgeAutoHideDefaultEnabled else {
            settingsWindowController?.reload()
            return
        }
        FloatingPanelController.persistEdgeAutoHideDefault(enabled)
        for panel in panels {
            panel.setEdgeAutoHideEnabled(enabled, persistAsDefault: false)
        }
        requestMenuRefresh()
    }

    func toggleEdgeAutoHide(for panel: FloatingPanelController) {
        panel.toggleEdgeAutoHide()
        requestMenuRefresh()
    }

    func openNewTabInActivePanel() {
        if let activeWebPanel {
            activeWebPanel.openNewTab()
        } else {
            openChatGPTPanel()
        }
    }

    func closeCurrentTab() {
        activeWebPanel?.closeCurrentTab()
    }

    func toggleOpenChatGPTOnLaunch() {
        setOpenChatGPTOnLaunch(!opensChatGPTOnLaunch)
    }

    func setOpenChatGPTOnLaunch(_ enabled: Bool) {
        guard enabled != opensChatGPTOnLaunch else {
            settingsWindowController?.reload()
            return
        }
        UserDefaults.standard.set(enabled, forKey: Self.openOnLaunchKey)
        requestMenuRefresh()
    }

    @discardableResult
    func setGlobalHotKeyPreset(_ preset: GlobalHotKeyPreset) -> Bool {
        if preset == globalHotKeyPreset, globalHotKeyController?.isRegistered == true {
            globalHotKeyError = nil
            requestMenuRefresh()
            return true
        }

        do {
            if let globalHotKeyController, globalHotKeyController.isRegistered {
                try globalHotKeyController.updateShortcut(preset.shortcut)
            } else {
                globalHotKeyController?.invalidate()
                globalHotKeyController = try GlobalHotKeyController(
                    shortcut: preset.shortcut
                ) { [weak self] in
                    self?.toggleAllPanelsVisibility()
                }
            }
            UserDefaults.standard.set(preset.rawValue, forKey: Self.globalHotKeyPresetKey)
            globalHotKeyError = nil
            requestMenuRefresh()
            return true
        } catch {
            globalHotKeyError = error.localizedDescription
            requestMenuRefresh()
            showError(
                title: "Shortcut Unavailable",
                message: "\(error.localizedDescription) Your previous shortcut remains selected when it could be restored."
            )
            return false
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
        } catch {
            showError(title: "Could Not Change Login Item", message: error.localizedDescription)
        }
        requestMenuRefresh()
    }

    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    func exportLibrary() {
        let panel = NSSavePanel()
        panel.title = "Export CornerFloat Library"
        panel.nameFieldStringValue = "CornerFloat-Library.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try workspaceLibrary.exportData().write(to: destination, options: .atomic)
        } catch {
            showError(title: "Could Not Export Library", message: error.localizedDescription)
        }
    }

    func importLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Import CornerFloat Library"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let source = panel.url else { return }

        do {
            let data = try Data(contentsOf: source)
            let preview = try workspaceLibrary.previewImport(data)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Replace the Current Library?"
            alert.informativeText = "This file contains \(preview.summary). Importing replaces the current favorites, recents, Quick Sites, and saved workspaces. Open web panels and website data are not changed. Export first if you want a backup."
            alert.addButton(withTitle: "Cancel")
            let importButton = alert.addButton(withTitle: "Import & Replace")
            importButton.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }

            try workspaceLibrary.importDataReplacingLibrary(data)
            requestMenuRefresh()
            workspaceLibraryController?.show()
        } catch {
            showError(title: "Could Not Import Library", message: error.localizedDescription)
        }
    }

    func revealLibraryData() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: workspaceLibrary.fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([workspaceLibrary.fileURL])
        } else {
            let directory = workspaceLibrary.fileURL.deletingLastPathComponent()
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                NSWorkspace.shared.open(directory)
            } catch {
                showError(title: "Could Not Reveal Data", message: error.localizedDescription)
            }
        }
    }

    func hideActivePanel() {
        activePanel?.hide()
    }

    func closeActivePanel() {
        activePanel?.close()
    }

    func minimizeActivePanel() {
        activePanel?.minimize()
    }

    func moveActivePanelToBottomRight() {
        activePanel?.moveToBottomRight()
    }

    func shrinkActivePanel() {
        activePanel?.resizeWindow(by: 0.86)
    }

    func resetActivePanelSize() {
        activePanel?.resetWindowSize()
    }

    func expandActivePanel() {
        activePanel?.resizeWindow(by: 1.16)
    }

    func index(of panel: FloatingPanelController) -> Int {
        panels.firstIndex { $0 === panel } ?? 0
    }

    func panelDidClose(_ panel: FloatingPanelController) {
        panels.removeAll { $0 === panel }
        webPanelURLs.removeValue(forKey: panel.id)
        requestMenuRefresh()
    }

    func requestMenuRefresh() {
        statusBarController?.requestRefresh()
        mainMenuController?.refreshGlobalShortcut()
        workspaceLibraryController?.reload()
        settingsWindowController?.reload()
    }

    func showLibraryManager(section: CornerFloatManagerSection? = nil) {
        workspaceLibraryController?.show(section: section)
    }

    func showSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(owner: self)
        settingsWindowController = controller
        controller.show()
    }

    func resolveAddress(_ input: String) -> URL? {
        SmartAddressResolver.resolve(input, customShortcuts: quickSites)
    }

    func openQuickSite(id: UUID) {
        guard let shortcut = quickSites.first(where: { $0.id == id }),
              let url = SmartAddressResolver.resolve(shortcut.url),
              WorkspaceLibraryStore.isPersistableWebURL(url) else { return }
        addWebPanel(url: url)
    }

    func promptToAddQuickSite() {
        promptToSaveQuickSite(nil)
    }

    func promptToEditQuickSite(id: UUID) {
        guard let shortcut = workspaceLibrary.shortcut(id: id) else { return }
        promptToSaveQuickSite(shortcut)
    }

    func removeQuickSite(id: UUID) {
        do {
            try workspaceLibrary.removeShortcut(id: id)
            requestMenuRefresh()
        } catch {
            showLibraryError(error)
        }
    }

    func bookmarkActivePage() {
        guard let panel = activeWebPanel, let url = currentURL(for: panel) else {
            showError(
                title: CFL10n.text("没有可收藏的网页", "No Page to Favorite"),
                message: CFL10n.text("请先打开或选中一个网页面板。", "Open or select a web panel first.")
            )
            return
        }
        do {
            _ = try workspaceLibrary.addBookmark(title: destinationTitle(for: url), url: url)
            requestMenuRefresh()
        } catch {
            showLibraryError(error)
        }
    }

    func openBookmark(id: UUID) {
        guard let bookmark = bookmarks.first(where: { $0.id == id }),
              let url = URL(string: bookmark.url) else { return }
        addWebPanel(url: url)
        do {
            try workspaceLibrary.markBookmarkOpened(id: id)
        } catch {
            showLibraryError(error)
        }
        requestMenuRefresh()
    }

    func removeBookmark(id: UUID) {
        do {
            try workspaceLibrary.removeBookmark(id: id)
            requestMenuRefresh()
        } catch {
            showLibraryError(error)
        }
    }

    func openRecentDestination(id: UUID) {
        guard let recent = recentDestinations.first(where: { $0.id == id }),
              let url = URL(string: recent.url) else { return }
        addWebPanel(url: url)
    }

    func bookmarkRecentDestination(id: UUID) {
        guard let recent = recentDestinations.first(where: { $0.id == id }),
              let url = URL(string: recent.url) else { return }
        do {
            _ = try workspaceLibrary.addBookmark(title: recent.title, url: url)
            requestMenuRefresh()
        } catch {
            showLibraryError(error)
        }
    }

    func removeRecentDestination(id: UUID) {
        do {
            try workspaceLibrary.removeRecent(id: id)
            requestMenuRefresh()
        } catch {
            showLibraryError(error)
        }
    }

    func requestClearRecentDestinations() {
        let count = recentDestinations.count
        guard count > 0,
              confirmDestructiveAction(.clearRecents(count: count)) else {
            return
        }
        clearRecentDestinations()
    }

    private func clearRecentDestinations() {
        do {
            try workspaceLibrary.clearRecents()
            requestMenuRefresh()
        } catch {
            showLibraryError(error)
        }
    }

    func promptToSaveCurrentWorkspace() {
        let snapshots = currentWorkspacePanels()
        guard !snapshots.isEmpty else {
            showError(
                title: CFL10n.text("没有可保存的窗口", "No Windows to Save"),
                message: CFL10n.text("请先打开网页窗口。", "Open a web window first.")
            )
            return
        }

        let savedContents = workspaceContentsDescription(webCount: snapshots.count)

        NSApp.activate(ignoringOtherApps: true)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = CFL10n.text("例如：学习、邮件、每日工作", "For example: Study, Mail, Daily Work")
        field.stringValue = suggestedWorkspaceName()
        field.setAccessibilityLabel(CFL10n.text("工作区名称", "Workspace name"))

        let alert = NSAlert()
        alert.messageText = CFL10n.text("保存当前工作区", "Save Current Workspace")
        alert.informativeText = CFL10n.text(
            "保存 \(savedContents) 的位置、大小、标签页和显示设置。使用相同名称会更新已有工作区。",
            "Save the positions, sizes, tabs, and display settings for \(savedContents). Reusing a name updates that workspace."
        )
        alert.accessoryView = field
        alert.addButton(withTitle: CFL10n.text("保存", "Save"))
        alert.addButton(withTitle: CFL10n.text("取消", "Cancel"))
        alert.window.initialFirstResponder = field
        DispatchQueue.main.async { field.selectText(nil) }
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            _ = try workspaceLibrary.saveWorkspace(name: field.stringValue, panels: snapshots)
            requestMenuRefresh()
            workspaceLibraryController?.show(section: .workspaces)
        } catch {
            showLibraryError(error)
        }
    }

    func restoreWorkspace(id: UUID, replacingCurrentPanels: Bool) {
        guard let workspace = workspaceLibrary.workspace(id: id) else { return }
        if replacingCurrentPanels {
            closeAllPanels()
        }

        for snapshot in workspace.panels {
            guard let content = snapshot.restoreContent else { continue }
            switch content {
            case let .web(tabURLs, selectedIndex):
                guard let firstURL = tabURLs.first else { continue }
                let controller = addWebPanel(url: firstURL)
                controller.restoreWorkspaceTabs(tabURLs, selectedIndex: selectedIndex)
                applyWorkspacePresentation(snapshot, to: controller)
            }
        }
        requestMenuRefresh()
    }

    func removeWorkspace(id: UUID) {
        do {
            try workspaceLibrary.removeWorkspace(id: id)
            requestMenuRefresh()
        } catch {
            showLibraryError(error)
        }
    }

    private func promptToSaveQuickSite(_ existing: AddressShortcut?) {
        NSApp.activate(ignoringOtherApps: true)

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 158))
        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.frame = NSRect(x: 0, y: 134, width: 390, height: 18)
        let nameField = NSTextField(frame: NSRect(x: 0, y: 106, width: 390, height: 24))
        nameField.placeholderString = "University Mail"
        nameField.stringValue = existing?.name ?? ""
        nameField.setAccessibilityLabel("Quick site name")

        let aliasLabel = NSTextField(labelWithString: "Shortcut words · separate with commas")
        aliasLabel.frame = NSRect(x: 0, y: 80, width: 390, height: 18)
        let aliasField = NSTextField(frame: NSRect(x: 0, y: 52, width: 390, height: 24))
        aliasField.placeholderString = "unimail, campus mail"
        aliasField.stringValue = existing?.aliases.joined(separator: ", ") ?? ""
        aliasField.setAccessibilityLabel("Shortcut words")

        let urlLabel = NSTextField(labelWithString: "Destination · HTTP or HTTPS")
        urlLabel.frame = NSRect(x: 0, y: 26, width: 390, height: 18)
        let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 390, height: 24))
        urlField.placeholderString = "https://mail.google.com/"
        urlField.stringValue = existing?.url ?? "https://"
        urlField.setAccessibilityLabel("Quick site destination")

        for view in [nameLabel, nameField, aliasLabel, aliasField, urlLabel, urlField] {
            accessory.addSubview(view)
        }

        let alert = NSAlert()
        alert.messageText = existing == nil ? "Add Quick Site" : "Edit Quick Site"
        alert.informativeText = "Type any shortcut word in a CornerFloat address bar to open this destination directly. Custom aliases take precedence over built-in names and stay on this Mac."
        alert.accessoryView = accessory
        alert.addButton(withTitle: existing == nil ? "Add" : "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = nameField
        DispatchQueue.main.async { nameField.selectText(nil) }

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let aliases = aliasField.stringValue.components(
            separatedBy: CharacterSet(charactersIn: ",;\n")
        )
        do {
            _ = try workspaceLibrary.saveShortcut(
                id: existing?.id,
                name: nameField.stringValue,
                aliases: aliases,
                urlString: urlField.stringValue
            )
            requestMenuRefresh()
            workspaceLibraryController?.show(section: .shortcuts)
        } catch {
            showLibraryError(error)
        }
    }

    func showError(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "11"
        let buildKind = hasConfiguredUpdateChannel
            ? "Signed release build with a configured update channel."
            : "Open-source local build. No Apple developer account or signed update channel is required."
        let credits = NSAttributedString(
            string: "A private floating workspace for websites.\n\n\(buildKind)\n\nBuilt with AppKit, WebKit, and Sparkle. CornerFloat source code is licensed under MIT. Sparkle and bundled components retain their own license notices, included with the app.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "CornerFloat",
            .applicationVersion: "Version \(version) (\(build))",
            .credits: credits
        ])
    }

    func showPrivacyPolicy() {
        productPagesController.show(.privacy)
    }

    func showSupport() {
        productPagesController.show(.support)
    }

    func checkForUpdates() {
        updateController.checkForUpdates(nil)
    }

    /// Passkey permission is intentionally requested only after this explicit
    /// menu action. Merely launching CornerFloat never presents the system prompt.
    func enableOrReviewPasskeyAccess() {
        Task { @MainActor [weak self] in
            await self?.passkeyAuthorizationCoordinator.handleExplicitUserAction()
        }
    }

    func showWelcome(thenOpenDefaultPanel: Bool = false) {
        if let onboardingController {
            onboardingController.begin()
            return
        }
        let controller = OnboardingWindowController()
        onboardingController = controller
        controller.onFinish = { [weak self, weak controller] result in
            guard let self else { return }
            if self.onboardingController === controller {
                self.onboardingController = nil
            }
            if result == .completed, thenOpenDefaultPanel, self.panels.isEmpty {
                self.openChatGPTPanel()
            }
        }
        controller.begin()
    }

    func dismissWelcomeForAcceptanceTesting() {
        onboardingController?.window?.performClose(nil)
    }

    func completeWelcomeForAcceptanceTesting() {
        onboardingController?.completeForAcceptanceTesting()
    }

    func closeSettingsForAcceptanceTesting() {
        settingsWindowController?.close()
    }

    private func installGlobalHotKey() {
        do {
            globalHotKeyController = try GlobalHotKeyController(
                shortcut: globalHotKeyPreset.shortcut
            ) { [weak self] in
                self?.toggleAllPanelsVisibility()
            }
            globalHotKeyError = nil
        } catch {
            globalHotKeyController = nil
            globalHotKeyError = error.localizedDescription
            fputs("CornerFloat global shortcut unavailable: \(error.localizedDescription)\n", stderr)
        }
        requestMenuRefresh()
    }

    @discardableResult
    private func addWebPanel(url: URL) -> WebPanelController {
        let controller = WebPanelController(owner: self, url: url)
        panels.append(controller)
        webPanelURLs[controller.id] = url
        recordRecentDestination(url)
        controller.moveToBottomRight()
        controller.show()
        requestMenuRefresh()
        return controller
    }

    @objc private func userDefaultsDidChange(_ notification: Notification) {
        guard let url = sanitizedLastWebURLPreference() else { return }
        let string = url.absoluteString
        guard string != lastObservedWebURL else { return }
        lastObservedWebURL = string
        if let panel = activeWebPanel {
            webPanelURLs[panel.id] = url
        }
        recordRecentDestination(url)
        requestMenuRefresh()
    }

    private func currentURL(for panel: WebPanelController?) -> URL? {
        guard let panel else { return nil }
        if let url = panel.currentPageURL, WorkspaceLibraryStore.isPersistableWebURL(url) {
            return url
        }
        if let url = webPanelURLs[panel.id] { return url }
        guard panel === activeWebPanel,
              let url = sanitizedLastWebURLPreference() else { return nil }
        return url
    }

    private func recordRecentDestination(_ url: URL) {
        guard let persistedURL = URLPersistenceSanitizer.sanitizedURL(url) else { return }
        lastObservedWebURL = persistedURL.absoluteString
        do {
            try workspaceLibrary.recordRecent(
                title: destinationTitle(for: persistedURL),
                url: persistedURL
            )
        } catch {
            fputs("CornerFloat could not save recent destination: \(error.localizedDescription)\n", stderr)
        }
    }

    private func sanitizedLastWebURLPreference() -> URL? {
        let defaults = UserDefaults.standard
        guard let storedValue = defaults.string(forKey: Self.lastWebURLKey) else { return nil }
        guard let candidate = URL(string: storedValue),
              let sanitizedURL = URLPersistenceSanitizer.sanitizedURL(candidate) else {
            defaults.removeObject(forKey: Self.lastWebURLKey)
            return nil
        }
        if sanitizedURL.absoluteString != storedValue {
            defaults.set(sanitizedURL.absoluteString, forKey: Self.lastWebURLKey)
        }
        return sanitizedURL
    }

    private func destinationTitle(for url: URL) -> String {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        switch host.lowercased() {
        case "chatgpt.com": return "ChatGPT"
        case "google.com": return "Google"
        case "mail.google.com": return "Gmail"
        default: return host
        }
    }

    private func currentWorkspacePanels() -> [WorkspacePanelSnapshot] {
        panels.compactMap { panel in
            guard let frame = panel.panel?.frame else { return nil }
            guard let webPanel = panel as? WebPanelController,
                  let url = currentURL(for: webPanel) else { return nil }
            return WorkspacePanelSnapshot(
                url: url.absoluteString,
                tabURLs: webPanel.workspaceTabURLs.map(\.absoluteString),
                selectedTabIndex: webPanel.selectedWorkspaceTabIndex,
                frame: frame,
                isVisible: panel.isVisible,
                opacity: panel.opacity,
                isClickThrough: panel.isClickThrough,
                edgeAutoHideEnabled: panel.isEdgeAutoHideEnabled
            )
        }
    }

    private func applyWorkspacePresentation(
        _ snapshot: WorkspacePanelSnapshot,
        to controller: FloatingPanelController
    ) {
        if let panel = controller.panel {
            panel.setFrame(
                restoredFrame(
                    snapshot.frame,
                    minimumSize: CGSize(width: 340, height: 460)
                ),
                display: true
            )
            controller.normalizeRestoredPresentation()
        }
        controller.setOpacity(snapshot.opacity)
        if snapshot.isClickThrough != controller.isClickThrough {
            controller.toggleClickThrough()
        }
        controller.setEdgeAutoHideEnabled(
            snapshot.edgeAutoHideEnabled ?? false,
            persistAsDefault: false
        )
        if snapshot.isVisible {
            controller.show(activating: false)
        } else {
            controller.hide()
        }
    }

    private func restoredFrame(_ requested: CGRect, minimumSize: CGSize) -> CGRect {
        let screens = NSScreen.screens
        let visibleFrames = screens.map(\.visibleFrame)
        guard let visible = WindowGeometry.bestVisibleFrame(
            for: requested,
            candidates: visibleFrames,
            fallback: NSScreen.main?.visibleFrame ?? visibleFrames.first
        ) else { return requested }
        var frame = requested
        frame.size.width = min(max(frame.width, minimumSize.width), max(minimumSize.width, visible.width - 24))
        frame.size.height = min(max(frame.height, minimumSize.height), max(minimumSize.height, visible.height - 24))
        frame.origin.x = min(max(frame.origin.x, visible.minX + 12), visible.maxX - frame.width - 12)
        frame.origin.y = min(max(frame.origin.y, visible.minY + 12), visible.maxY - frame.height - 12)
        return frame
    }

    private func workspaceContentsDescription(webCount: Int) -> String {
        webCount == 1 ? "1 web window" : "\(webCount) web windows"
    }

    private func suggestedWorkspaceName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        return CFL10n.text("工作区 \(formatter.string(from: Date()))", "Workspace \(formatter.string(from: Date()))")
    }

    private func showLibraryError(_ error: Error) {
        showError(
            title: CFL10n.text("无法保存资料库", "Could Not Save Library"),
            message: error.localizedDescription
        )
    }

    private func openOfflineDemoPanel() {
        let html = """
        <html><head><meta name='viewport' content='width=device-width'>
        <style>
        body { font: 16px -apple-system; padding: 28px; background: #f4f6fa; color: #182033; }
        .card { background: white; padding: 24px; border-radius: 18px; box-shadow: 0 8px 32px #26324d22; }
        h1 { margin: 0 0 10px; font-size: 26px; }
        input, button, a { box-sizing: border-box; padding: 10px 12px; border-radius: 10px; border: 1px solid #ccd3df; font: inherit; }
        input { width: 100%; } button, a { display: block; width: 100%; margin-top: 10px; background: #fff; color: #182033; text-align: center; text-decoration: none; }
        </style></head><body><div class='card'><h1>CornerFloat</h1>
        <p>The floating web panel is ready.</p>
        <input placeholder='Type here to test interaction'>
        <button id='popup' onclick="const w=window.open('about:blank','cornerfloat-oauth-test'); w.document.write('<title>Popup Ready</title><h1>OAuth-style popup ready</h1>'); w.document.close();">Open OAuth-style popup</button>
        <button id='alert' onclick="alert('JavaScript dialog ready')">Show JavaScript dialog</button>
        <form id='post-form' method='post' action='https://cornerfloat-post-retry.invalid/submit'>
        <input type='hidden' name='test' value='do-not-replay'>
        <button id='post-failure' type='button' onclick="document.getElementById('post-form').submit()">Test failed form safety</button>
        </form>
        <input id='upload' type='file' aria-label='Choose upload test file'>
        <a id='download' download='cornerfloat-smoke.txt' href='data:text/plain,CornerFloat%20download%20test'>Start test download</a>
        </div></body></html>
        """
        guard let encoded = html.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "data:text/html;charset=utf-8,\(encoded)") else { return }
        addWebPanel(url: url)
    }

}
