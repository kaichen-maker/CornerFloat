import AppKit
import WebKit

// WebKit's delegate callback annotations changed across the Xcode versions
// that can build CornerFloat. Swift 5.10 imports plain closures; Swift 6 makes
// them Sendable, while the SDK bundled with Xcode 16.4 leaves the no-argument
// JavaScript alert callback nonisolated. Keep the witness signatures exact so
// downloads, dialogs, authentication, and navigation remain callable on 14+.
#if compiler(>=6.2)
typealias WebKitCallback0 = @MainActor @Sendable () -> Void
#elseif compiler(>=6.0)
typealias WebKitCallback0 = @Sendable () -> Void
#else
typealias WebKitCallback0 = () -> Void
#endif

#if compiler(>=6.0)
typealias WebKitCallback1<Value> = @MainActor @Sendable (Value) -> Void
typealias WebKitCallback2<First, Second> = @MainActor @Sendable (First, Second) -> Void
#else
typealias WebKitCallback1<Value> = (Value) -> Void
typealias WebKitCallback2<First, Second> = (First, Second) -> Void
#endif

@MainActor
final class WebPanelController: FloatingPanelController, WKNavigationDelegate, WKUIDelegate,
    WKDownloadDelegate, NSTextFieldDelegate, NSToolbarDelegate {
    #if CORNERFLOAT_WEBKIT_INTEGRATION_TESTS
    /// Read-only state used by the offline WebKit integration suite. Keeping
    /// this at the controller boundary lets the tests exercise the production
    /// delegates without making BrowserTab or any mutation API public.
    struct IntegrationTabState {
        let webView: WKWebView
        let pendingMainFrameRequest: URLRequest?
        let lastCommittedURL: URL?
        let failedRequest: URLRequest?
        let failedURL: URL?
        let isShowingError: Bool
        let isSelected: Bool
    }
    #endif

    private struct WorkspaceTabSnapshot {
        let urls: [URL]
        let selectedIndex: Int
    }

    private enum TabCreationSource {
        case initial
        case user
        case workspaceRestore
        case websitePopup
    }

    private struct PendingDownloadDestination {
        let downloadID: ObjectIdentifier
        let suggestedFilename: String
        let completion: WebKitCallback1<URL?>
    }

    private struct PendingVoiceRouteRequest {
        var machine: VoiceRoutePreflightMachine
        let webView: WKWebView
        let decisionHandler: WebKitCallback1<WKPermissionDecision>
        let hasBuiltInAlternative: Bool
    }

    private static let savedWidthKey = "preferredWebPanelWidth"
    private static let savedHeightKey = "preferredWebPanelHeight"
    private static let backItemIdentifier = NSToolbarItem.Identifier("CornerFloat.Back")
    private static let forwardItemIdentifier = NSToolbarItem.Identifier("CornerFloat.Forward")
    private static let reloadItemIdentifier = NSToolbarItem.Identifier("CornerFloat.Reload")
    private static let securityItemIdentifier = NSToolbarItem.Identifier("CornerFloat.Security")
    private static let addressItemIdentifier = NSToolbarItem.Identifier("CornerFloat.Address")
    private static let applicationMenuItemIdentifier = NSToolbarItem.Identifier("CornerFloat.ApplicationMenu")
    private static let compactToolbarWidth: CGFloat = 520
    static let maximumLiveTabs = 24
    /// Normal tabs share the same persistent store instance so a just-written
    /// session cookie can become visible to separately created tabs.
    /// Popups still use WebKit's supplied configuration in addTab(configuration:)
    /// so their opener relationship and browsing context remain intact.
    private static let sharedWebsiteDataStore = WKWebsiteDataStore.default()
    private static let sharedVoiceAudioRouteCoordinator = VoiceAudioRouteCoordinator()

    private let persistsPreferredSize: Bool
    private let addressField = NSTextField()
    private let rootView = NSView()
    private let tabBar = NSView()
    private let tabScrollView = NSScrollView()
    private let tabBarDocumentView = NSView()
    private let tabStack = NSStackView()
    private let contentContainer = NSView()
    private var tabBarHeightConstraint: NSLayoutConstraint?
    private var tabs: [BrowserTab] = []
    private var tabItemViews: [UUID: BrowserTabItemView] = [:]
    private weak var selectedTab: BrowserTab?
    private var browserToolbar: NSToolbar?
    private var isUsingCompactToolbar: Bool?
    private weak var backToolbarItem: NSToolbarItem?
    private weak var forwardToolbarItem: NSToolbarItem?
    private weak var securityToolbarItem: NSToolbarItem?
    private var activeDownloads: [ObjectIdentifier: WKDownload] = [:]
    private var downloadTransactions: [ObjectIdentifier: DownloadDestinationTransaction] = [:]
    private var destinationQueue: [PendingDownloadDestination] = []
    private var isPresentingDestinationPicker = false
    private weak var activeSavePanel: NSSavePanel?
    private var tabCyclingMonitor: Any?
    private var pendingTabLimitMessage: String?
    private var isPresentingTabLimitNotice = false
    private var activeTabLimitAlert: NSAlert?
    private var pendingVoiceRouteRequest: PendingVoiceRouteRequest?
    private var activeVoiceRouteAlert: NSAlert?
    #if CORNERFLOAT_WEBKIT_INTEGRATION_TESTS
    private(set) var integrationTabLimitNoticeCount = 0
    #endif

    init(owner: AppController, url: URL) {
        self.persistsPreferredSize = url.scheme != "data"

        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "Web Page"
        let initialSize = url.scheme == "data"
            ? CGSize(width: 420, height: 640)
            : Self.restoredContentSize()
        super.init(
            owner: owner,
            title: "Web · \(host)",
            contentSize: initialSize
        )

        panel?.contentMinSize = CGSize(width: 340, height: 460)
        buildInterface()
        installTabCyclingMonitor()
        _ = addTab(url: url, select: true, source: .initial)
    }

    var currentPageURL: URL? {
        guard let tab = selectedTab else { return nil }
        return tab.webView.url ?? tab.lastCommittedURL ?? tab.pendingMainFrameRequest?.url
    }

    var workspaceTabURLs: [URL] {
        workspaceTabSnapshot().urls
    }

    var selectedWorkspaceTabIndex: Int {
        workspaceTabSnapshot().selectedIndex
    }

    #if CORNERFLOAT_WEBKIT_INTEGRATION_TESTS
    var integrationTabStates: [IntegrationTabState] {
        tabs.map { tab in
            IntegrationTabState(
                webView: tab.webView,
                pendingMainFrameRequest: tab.pendingMainFrameRequest,
                lastCommittedURL: tab.lastCommittedURL,
                failedRequest: tab.failedRequest,
                failedURL: tab.failedURL,
                isShowingError: !tab.errorView.isHidden,
                isSelected: tab === selectedTab
            )
        }
    }

    var selectedIntegrationWebView: WKWebView? {
        selectedTab?.webView
    }

    var integrationTabAccessibilityStates: [BrowserTabItemView.IntegrationAccessibilityState] {
        tabs.compactMap { tabItemViews[$0.id]?.integrationAccessibilityState }
    }

    func selectIntegrationTab(webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }
        selectTab(id: tab.id)
    }

    func cycleIntegrationTab(backward: Bool) {
        _ = selectAdjacentTab(direction: backward ? -1 : 1)
    }
    #endif

    /// Projects the live tab array onto the subset that can safely cross the
    /// workspace persistence boundary. Keeping each retained tab's original
    /// identity prevents an earlier about:/data: popup from shifting the saved
    /// selected index to a different website.
    private func workspaceTabSnapshot() -> WorkspaceTabSnapshot {
        let retained = tabs.enumerated().compactMap { rawIndex, tab
            -> (rawIndex: Int, tab: BrowserTab, url: URL)? in
            guard let candidate = currentURL(for: tab),
                  let sanitizedURL = URLPersistenceSanitizer.sanitizedURL(candidate) else {
                return nil
            }
            return (rawIndex, tab, sanitizedURL)
        }
        guard !retained.isEmpty else {
            return WorkspaceTabSnapshot(urls: [], selectedIndex: 0)
        }

        let selectedIndex: Int
        if let selectedTab,
           let exactIndex = retained.firstIndex(where: { $0.tab === selectedTab }) {
            selectedIndex = exactIndex
        } else if let selectedTab,
                  let rawSelectedIndex = tabs.firstIndex(where: { $0 === selectedTab }),
                  let nearest = retained.enumerated().min(by: { lhs, rhs in
                      let leftDistance = abs(lhs.element.rawIndex - rawSelectedIndex)
                      let rightDistance = abs(rhs.element.rawIndex - rawSelectedIndex)
                      if leftDistance == rightDistance {
                          return lhs.element.rawIndex < rhs.element.rawIndex
                      }
                      return leftDistance < rightDistance
                  }) {
            // If the selected popup itself cannot be restored, choose its
            // nearest restorable neighbor instead of an unrelated raw index.
            selectedIndex = nearest.offset
        } else {
            selectedIndex = 0
        }
        return WorkspaceTabSnapshot(
            urls: retained.map { $0.url },
            selectedIndex: selectedIndex
        )
    }

    private func currentURL(for tab: BrowserTab) -> URL? {
        tab.webView.url ?? tab.lastCommittedURL ?? tab.pendingMainFrameRequest?.url
    }

    /// Restores a saved tab group after the panel has been created with its
    /// first URL. This keeps every tab in the same persistent WebKit data store
    /// so OAuth and passkey sessions remain consistent across the group.
    func restoreWorkspaceTabs(_ urls: [URL], selectedIndex: Int) {
        let validURLs = Array(
            urls.lazy.filter { BrowserSupport.isWebURL($0) }.prefix(Self.maximumLiveTabs)
        )
        guard let firstURL = validURLs.first, let firstTab = tabs.first else { return }

        let existingFirstURL = firstTab.webView.url
            ?? firstTab.lastCommittedURL
            ?? firstTab.pendingMainFrameRequest?.url
        if existingFirstURL?.absoluteString != firstURL.absoluteString {
            load(firstURL, in: firstTab)
        }
        for url in validURLs.dropFirst() {
            _ = addTab(url: url, select: false, source: .workspaceRestore)
        }
        let safeIndex = min(max(selectedIndex, 0), max(tabs.count - 1, 0))
        selectTab(id: tabs[safeIndex].id)
    }

    func openNewTab() {
        _ = addTab(
            url: URL(string: "https://www.google.com/"),
            select: true,
            source: .user
        )
    }

    func openNewTab(url: URL) {
        guard BrowserSupport.isWebURL(url) else { return }
        _ = addTab(url: url, select: true, source: .user)
    }

    func closeCurrentTab() {
        guard let id = selectedTab?.id else { return }
        closeTab(id: id)
    }

    override func preferredContentSize(for preset: PanelSizePreset) -> CGSize {
        switch preset {
        case .compact: return CGSize(width: 340, height: 500)
        case .standard: return CGSize(width: 420, height: 640)
        case .spacious: return CGSize(width: 560, height: 780)
        }
    }

    override func contentSizeDidChange(to size: CGSize) {
        updateResponsiveToolbar(for: size.width)
        guard persistsPreferredSize, size.width.isFinite, size.height.isFinite else { return }
        UserDefaults.standard.set(size.width, forKey: Self.savedWidthKey)
        UserDefaults.standard.set(size.height, forKey: Self.savedHeightKey)
    }

    override func normalizeRestoredPresentation() {
        guard let width = panel?.contentView?.bounds.width else { return }
        updateResponsiveToolbar(for: width, force: true)
    }

    private func buildInterface() {
        configureAddressField()

        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.wantsLayer = true
        tabBar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        configureTabBar()
        rootView.addSubview(tabBar)
        rootView.addSubview(contentContainer)
        let tabBarHeightConstraint = tabBar.heightAnchor.constraint(equalToConstant: 36)
        self.tabBarHeightConstraint = tabBarHeightConstraint
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: rootView.topAnchor),
            tabBarHeightConstraint,
            contentContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        installContentView(rootView)
        installBrowserToolbar()
    }

    private func configureAddressField() {
        addressField.placeholderString = "Enter a URL or search"
        addressField.font = .systemFont(ofSize: 13)
        addressField.isBezeled = false
        addressField.drawsBackground = true
        addressField.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.58)
        addressField.wantsLayer = true
        addressField.layer?.cornerRadius = 8
        addressField.focusRingType = .exterior
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.target = self
        addressField.action = #selector(loadAddress)
        addressField.delegate = self
        addressField.setAccessibilityLabel("URL or search")
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addressField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            addressField.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func configureTabBar() {
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.drawsBackground = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.autohidesScrollers = true
        tabScrollView.borderType = .noBorder

        tabBarDocumentView.translatesAutoresizingMaskIntoConstraints = false
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 4
        tabBarDocumentView.addSubview(tabStack)
        tabScrollView.documentView = tabBarDocumentView

        let newTabButton = NSButton()
        newTabButton.title = ""
        newTabButton.isBordered = false
        newTabButton.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "New tab"
        )
        newTabButton.toolTip = "New tab"
        newTabButton.target = self
        newTabButton.action = #selector(createNewTab)
        newTabButton.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        tabBar.addSubview(tabScrollView)
        tabBar.addSubview(newTabButton)
        tabBar.addSubview(separator)
        NSLayoutConstraint.activate([
            tabScrollView.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 6),
            tabScrollView.topAnchor.constraint(equalTo: tabBar.topAnchor, constant: 4),
            tabScrollView.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: -4),
            tabScrollView.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: -3),
            newTabButton.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -6),
            newTabButton.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 26),
            newTabButton.heightAnchor.constraint(equalToConstant: 26),
            separator.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),

            tabBarDocumentView.leadingAnchor.constraint(equalTo: tabScrollView.contentView.leadingAnchor),
            tabBarDocumentView.topAnchor.constraint(equalTo: tabScrollView.contentView.topAnchor),
            tabBarDocumentView.bottomAnchor.constraint(equalTo: tabScrollView.contentView.bottomAnchor),
            tabBarDocumentView.heightAnchor.constraint(equalTo: tabScrollView.contentView.heightAnchor),
            tabBarDocumentView.widthAnchor.constraint(greaterThanOrEqualTo: tabScrollView.contentView.widthAnchor),
            tabStack.leadingAnchor.constraint(equalTo: tabBarDocumentView.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: tabBarDocumentView.trailingAnchor),
            tabStack.centerYAnchor.constraint(equalTo: tabBarDocumentView.centerYAnchor)
        ])
    }

    private func installBrowserToolbar() {
        guard let panel else { return }

        panel.toolbarStyle = .unifiedCompact
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = false
        panel.titlebarSeparatorStyle = .line
        panel.backgroundColor = .windowBackgroundColor
        panel.isMovableByWindowBackground = false
        let width = panel.contentView?.bounds.width ?? panel.contentLayoutRect.width
        updateResponsiveToolbar(for: width, force: true)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarItemIdentifiers(compact: isUsingCompactToolbar ?? true)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.toolbarItemIdentifiers(compact: isUsingCompactToolbar ?? true)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.backItemIdentifier:
            let item = makeToolbarButton(
                identifier: itemIdentifier,
                symbol: "chevron.left",
                label: "Back",
                action: #selector(goBack),
                visibilityPriority: .low
            )
            backToolbarItem = item
            return item
        case Self.forwardItemIdentifier:
            let item = makeToolbarButton(
                identifier: itemIdentifier,
                symbol: "chevron.right",
                label: "Forward",
                action: #selector(goForward),
                visibilityPriority: .low
            )
            forwardToolbarItem = item
            return item
        case Self.reloadItemIdentifier:
            return makeToolbarButton(
                identifier: itemIdentifier,
                symbol: "arrow.clockwise",
                label: "Reload",
                action: #selector(reloadPage),
                visibilityPriority: .standard
            )
        case Self.securityItemIdentifier:
            let item = makeToolbarButton(
                identifier: itemIdentifier,
                symbol: "network",
                label: "Connection Information",
                action: #selector(showConnectionInformation),
                visibilityPriority: .high
            )
            securityToolbarItem = item
            return item
        case Self.addressItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "URL or Search"
            item.paletteLabel = "URL or Search"
            item.toolTip = "Enter a URL, website name, or search query"
            item.view = addressField
            item.visibilityPriority = .high
            return item
        case Self.applicationMenuItemIdentifier:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "More"
            item.paletteLabel = "More"
            item.toolTip = "More options"
            item.image = NSImage(
                systemSymbolName: "ellipsis.circle",
                accessibilityDescription: "More options"
            )?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            )
            item.showsIndicator = false
            item.menu = makeApplicationMenu()
            item.visibilityPriority = .user
            return item
        default:
            return nil
        }
    }

    private func makeToolbarButton(
        identifier: NSToolbarItem.Identifier,
        symbol: String,
        label: String,
        action: Selector,
        visibilityPriority: NSToolbarItem.VisibilityPriority
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        item.target = self
        item.action = action
        item.visibilityPriority = visibilityPriority
        return item
    }

    private static func toolbarItemIdentifiers(compact: Bool) -> [NSToolbarItem.Identifier] {
        if compact {
            return [
                securityItemIdentifier,
                addressItemIdentifier,
                applicationMenuItemIdentifier
            ]
        }
        return [
            backItemIdentifier,
            forwardItemIdentifier,
            reloadItemIdentifier,
            securityItemIdentifier,
            addressItemIdentifier,
            applicationMenuItemIdentifier
        ]
    }

    private func updateResponsiveToolbar(for width: CGFloat, force: Bool = false) {
        guard width.isFinite, width > 0, let panel else { return }
        let shouldUseCompactToolbar = width < Self.compactToolbarWidth
        guard force || isUsingCompactToolbar != shouldUseCompactToolbar else { return }
        isUsingCompactToolbar = shouldUseCompactToolbar

        backToolbarItem = nil
        forwardToolbarItem = nil
        securityToolbarItem = nil
        let mode = shouldUseCompactToolbar ? "Compact" : "Regular"
        let toolbar = NSToolbar(
            identifier: NSToolbar.Identifier("CornerFloat.Browser.\(mode).\(id.uuidString)")
        )
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        if #unavailable(macOS 15.0) {
            toolbar.showsBaselineSeparator = true
        }
        browserToolbar = toolbar
        panel.toolbar = toolbar
        updateNavigationButtons()
    }

    private func makeApplicationMenu() -> NSMenu {
        let menu = NSMenu(title: "CornerFloat")
        menu.addItem(makeApplicationMenuItem(
            title: "Back",
            symbol: "chevron.left",
            action: #selector(goBack),
            keyEquivalent: "["
        ))
        menu.addItem(makeApplicationMenuItem(
            title: "Forward",
            symbol: "chevron.right",
            action: #selector(goForward),
            keyEquivalent: "]"
        ))
        menu.addItem(makeApplicationMenuItem(
            title: "Reload",
            symbol: "arrow.clockwise",
            action: #selector(reloadPage),
            keyEquivalent: "r"
        ))
        menu.addItem(.separator())
        menu.addItem(makeApplicationMenuItem(
            title: "New Tab",
            symbol: "plus.square.on.square",
            action: #selector(createNewTab),
            keyEquivalent: "t"
        ))
        menu.addItem(makeApplicationMenuItem(
            title: "Next Tab",
            symbol: "arrow.right.square",
            action: #selector(selectNextTab),
            keyEquivalent: "\t",
            modifiers: [.control]
        ))
        menu.addItem(makeApplicationMenuItem(
            title: "Previous Tab",
            symbol: "arrow.left.square",
            action: #selector(selectPreviousTab),
            keyEquivalent: "\t",
            modifiers: [.control, .shift]
        ))
        menu.addItem(makeApplicationMenuItem(
            title: "Close Current Tab",
            symbol: "xmark.square",
            action: #selector(closeSelectedTab),
            keyEquivalent: "w"
        ))
        menu.addItem(makeApplicationMenuItem(
            title: "Open in Default Browser",
            symbol: "safari",
            action: #selector(openCurrentPageExternally)
        ))
        menu.addItem(.separator())
        menu.addItem(makeApplicationMenuItem(
            title: "Temporarily Hide This Panel",
            symbol: "eye.slash",
            action: #selector(hideThisPanel)
        ))
        menu.addItem(makeApplicationMenuItem(
            title: "Close & Remove This Panel",
            symbol: "xmark.circle",
            action: #selector(closeAndRemoveThisPanel),
            keyEquivalent: "w",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(makeApplicationMenuItem(
            title: "Quit CornerFloat",
            symbol: "power",
            action: #selector(quitCornerFloat),
            keyEquivalent: "q"
        ))
        return menu
    }

    private func makeApplicationMenuItem(
        title: String,
        symbol: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers ?? (keyEquivalent.isEmpty ? [] : [.command])
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private func installTabCyclingMonitor() {
        guard tabCyclingMonitor == nil else { return }
        tabCyclingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            let wasHandled = MainActor.assumeIsolated {
                self?.handleTabCyclingEvent(event) ?? false
            }
            return wasHandled ? nil : event
        }
    }

    private func handleTabCyclingEvent(_ event: NSEvent) -> Bool {
        // Hardware key code 48 is Tab on every supported Mac keyboard layout.
        // Checking the key code keeps Control-Shift-Tab reliable when its
        // charactersIgnoringModifiers value varies by input source.
        guard event.window === panel, event.keyCode == 48, tabs.count > 1 else {
            return false
        }
        let relevantModifiers = event.modifierFlags.intersection([
            .command, .option, .control, .shift
        ])
        let direction: Int
        switch relevantModifiers {
        case [.control]:
            direction = 1
        case [.control, .shift]:
            direction = -1
        default:
            return false
        }
        return selectAdjacentTab(direction: direction)
    }

    @discardableResult
    private func addTab(
        configuration: WKWebViewConfiguration? = nil,
        url: URL? = nil,
        select: Bool,
        source: TabCreationSource
    ) -> BrowserTab? {
        guard tabs.count < Self.maximumLiveTabs else {
            handleTabLimitReached(source: source)
            return nil
        }
        let configuration = configuration ?? Self.makeWebConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        Self.sharedVoiceAudioRouteCoordinator.register(webView)

        let tab = BrowserTab(webView: webView)
        tab.errorView.onRetry = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.retry(tab)
        }
        tab.errorView.onOpenExternally = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.openExternally(tab)
        }
        tab.errorView.onDismiss = { [weak tab] in
            tab?.errorView.hide()
        }

        tabs.append(tab)
        contentContainer.addSubview(tab.containerView)
        NSLayoutConstraint.activate([
            tab.containerView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            tab.containerView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            tab.containerView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            tab.containerView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        let tabItem = BrowserTabItemView(tabID: tab.id, title: tab.displayTitle)
        tabItem.onSelect = { [weak self] id in self?.selectTab(id: id) }
        tabItem.onClose = { [weak self] id in self?.closeTab(id: id) }
        tabItemViews[tab.id] = tabItem
        tabStack.addArrangedSubview(tabItem)
        updateTabBarVisibility()

        if select || selectedTab == nil {
            selectTab(id: tab.id)
        } else {
            tab.containerView.isHidden = true
        }

        if let url {
            load(url, in: tab)
        }
        return tab
    }

    private static func makeWebConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = sharedWebsiteDataStore
        configuration.applicationNameForUserAgent = BrowserSupport.browserApplicationName(
            version: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        )
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .recommended
        return configuration
    }

    private func selectTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectedTab = tab
        for candidate in tabs {
            let selected = candidate === tab
            candidate.containerView.isHidden = !selected
            tabItemViews[candidate.id]?.setSelected(selected)
        }
        addressField.stringValue = tab.webView.url?.absoluteString
            ?? tab.failedURL?.absoluteString
            ?? tab.lastCommittedURL?.absoluteString
            ?? tab.pendingMainFrameRequest?.url?.absoluteString
            ?? ""
        updateNavigationButtons()
        updateWindowTitle(using: tab)
        if let tabItem = tabItemViews[id] {
            tabScrollView.contentView.scrollToVisible(tabItem.frame)
        }
    }

    @discardableResult
    private func selectAdjacentTab(direction: Int) -> Bool {
        guard tabs.count > 1,
              let selectedTab,
              let currentIndex = tabs.firstIndex(where: { $0 === selectedTab }) else {
            return false
        }
        let offset = direction >= 0 ? 1 : tabs.count - 1
        let targetIndex = (currentIndex + offset) % tabs.count
        selectTab(id: tabs[targetIndex].id)
        return true
    }

    private func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        let wasSelected = selectedTab === tab
        cancelPendingVoiceRouteRequest(for: tab.webView)
        Self.sharedVoiceAudioRouteCoordinator.unregister(tab.webView)
        tab.webView.stopLoading()
        tab.webView.navigationDelegate = nil
        tab.webView.uiDelegate = nil
        tab.containerView.removeFromSuperview()
        if let tabItem = tabItemViews.removeValue(forKey: id) {
            tabStack.removeArrangedSubview(tabItem)
            tabItem.removeFromSuperview()
        }
        tabs.remove(at: index)
        updateTabBarVisibility()

        guard !tabs.isEmpty else {
            close()
            return
        }
        if wasSelected {
            selectTab(id: tabs[min(index, tabs.count - 1)].id)
        }
    }

    private func handleTabLimitReached(source: TabCreationSource) {
        let message: String
        switch source {
        case .user:
            message = "This panel already contains \(Self.maximumLiveTabs) tabs. Close a tab before opening another."
        case .websitePopup:
            message = "This website tried to open another tab, but this panel already contains \(Self.maximumLiveTabs) tabs. Close a tab, then try the action again."
        case .initial, .workspaceRestore:
            return
        }

        // Coalesce popup bursts into one notice. A hidden panel records the
        // warning and shows it the next time the user reveals that panel rather
        // than stealing focus from another app.
        guard pendingTabLimitMessage == nil, !isPresentingTabLimitNotice else { return }
        pendingTabLimitMessage = message
        #if CORNERFLOAT_WEBKIT_INTEGRATION_TESTS
        integrationTabLimitNoticeCount += 1
        #endif
        presentPendingTabLimitNoticeIfPossible()
    }

    private func presentPendingTabLimitNoticeIfPossible() {
        guard isVisible,
              !isPresentingTabLimitNotice,
              let message = pendingTabLimitMessage else { return }
        pendingTabLimitMessage = nil
        isPresentingTabLimitNotice = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Tab Limit Reached"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        activeTabLimitAlert = alert
        present(alert) { [weak self] _ in
            self?.activeTabLimitAlert = nil
            self?.isPresentingTabLimitNotice = false
        }
    }

    private func updateTabBarVisibility() {
        let shouldShow = tabs.count > 1
        tabBar.isHidden = !shouldShow
        tabBarHeightConstraint?.constant = shouldShow ? 36 : 0
    }

    private func load(_ url: URL, in tab: BrowserTab) {
        tab.errorView.hide()
        let request = URLRequest(url: url)
        tab.pendingMainFrameRequest = request
        tab.failedRequest = nil
        tab.failedURL = nil
        if tab === selectedTab {
            addressField.stringValue = url.absoluteString
        }
        remember(url)
        tab.webView.load(request)
    }

    private func remember(_ url: URL) {
        guard let persistedURL = URLPersistenceSanitizer.sanitizedURL(url) else { return }
        UserDefaults.standard.set(persistedURL.absoluteString, forKey: "lastWebURL")
    }

    func focusAddressField() {
        show()
        panel?.makeFirstResponder(addressField)
        addressField.selectText(nil)
    }

    func navigateBack() {
        if selectedTab?.webView.canGoBack == true { selectedTab?.webView.goBack() }
    }

    func navigateForward() {
        if selectedTab?.webView.canGoForward == true { selectedTab?.webView.goForward() }
    }

    func reloadCurrentPage() {
        guard let tab = selectedTab else { return }
        if tab.failedRequest != nil || tab.failedURL != nil {
            guard BrowserSupport.isSafeToRetry(tab.failedRequest) else {
                NSSound.beep()
                return
            }
            retry(tab)
            return
        }
        tab.errorView.hide()
        tab.webView.reload()
    }

    @objc private func goBack() { navigateBack() }
    @objc private func goForward() { navigateForward() }
    @objc private func reloadPage() { reloadCurrentPage() }
    @objc private func showConnectionInformation() {
        guard let webView = selectedTab?.webView,
              let url = webView.url else {
            NSSound.beep()
            return
        }
        let state = BrowserSupport.connectionSecurityState(
            for: url,
            hasOnlySecureContent: webView.hasOnlySecureContent,
            hasServerTrust: webView.serverTrust != nil
        )
        let alert = NSAlert()
        switch state {
        case .secure:
            alert.alertStyle = .informational
            alert.messageText = "Secure Connection"
            alert.informativeText = "WebKit verified an encrypted HTTPS connection to \(url.host ?? "this website") and reports that the page contains only secure content.\n\n\(url.absoluteString)"
        case .insecure:
            alert.alertStyle = .warning
            alert.messageText = "Connection Is Not Fully Secure"
            alert.informativeText = "Do not enter passwords or sensitive information unless you expected this connection.\n\n\(url.absoluteString)"
        case .localContent:
            alert.alertStyle = .informational
            alert.messageText = "Local or Internal Content"
            alert.informativeText = "This page is not using a normal HTTP or HTTPS website connection.\n\n\(url.absoluteString)"
        }
        alert.addButton(withTitle: "OK")
        present(alert, completion: { _ in })
    }
    @objc private func hideThisPanel() { hide() }
    @objc private func closeAndRemoveThisPanel() { close() }
    @objc private func quitCornerFloat() { NSApp.terminate(nil) }

    @objc private func createNewTab() {
        let url = URL(string: "https://www.google.com/")
        if addTab(url: url, select: true, source: .user) != nil {
            focusAddressField()
        }
    }

    @objc private func selectNextTab() {
        _ = selectAdjacentTab(direction: 1)
    }

    @objc private func selectPreviousTab() {
        _ = selectAdjacentTab(direction: -1)
    }

    @objc private func closeSelectedTab() {
        guard let id = selectedTab?.id else { return }
        closeTab(id: id)
    }

    @objc private func openCurrentPageExternally() {
        guard let tab = selectedTab else { return }
        openVisiblePageExternally(tab)
    }

    @objc private func loadAddress() {
        guard let tab = selectedTab,
              let url = owner?.resolveAddress(addressField.stringValue)
                ?? SmartAddressResolver.resolve(addressField.stringValue) else {
            NSSound.beep()
            return
        }
        load(url, in: tab)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }
        tab.errorView.hide()
        if tab === selectedTab, let url = webView.url {
            addressField.stringValue = url.absoluteString
        }
        updateNavigationButtons()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = tab(for: webView), let url = webView.url else { return }
        tab.lastCommittedURL = url
        remember(url)
        if tab === selectedTab {
            addressField.stringValue = url.absoluteString
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab = tab(for: webView) else { return }
        if let url = webView.url {
            tab.lastCommittedURL = url
            remember(url)
            if tab === selectedTab {
                addressField.stringValue = url.absoluteString
            }
        }
        updateTabTitle(tab)
        updateNavigationButtons()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping WebKitCallback2<WKNavigationActionPolicy, WKWebpagePreferences>
    ) {
        preferences.allowsContentJavaScript = true
        preferences.preferredContentMode = .recommended

        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow, preferences)
            return
        }

        let isUnsafeReplay: Bool
        switch navigationAction.navigationType {
        case .formResubmitted:
            isUnsafeReplay = true
        case .reload, .backForward:
            isUnsafeReplay = !BrowserSupport.isSafeToRetry(navigationAction.request)
        default:
            isUnsafeReplay = false
        }
        if isUnsafeReplay {
            decisionHandler(.cancel, preferences)
            presentUnsafeFormReplayNotice(url: url)
            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }

        if ["http", "https", "about", "blob", "data"].contains(scheme) {
            if navigationAction.targetFrame?.isMainFrame == true,
               let tab = tab(for: webView) {
                tab.pendingMainFrameRequest = navigationAction.request
                tab.failedRequest = nil
                tab.failedURL = nil
            }
            decisionHandler(.allow, preferences)
            return
        }

        let userInitiated = navigationAction.navigationType == .linkActivated
            || navigationAction.navigationType == .formSubmitted
        decisionHandler(.cancel, preferences)
        switch BrowserSupport.externalNavigationDisposition(
            for: url,
            isUserInitiated: userInitiated,
            isMainFrame: navigationAction.sourceFrame.isMainFrame
        ) {
        case .block:
            return
        case .confirmBeforeOpening:
            openExternalApplicationURL(url, requiresConfirmation: true)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping WebKitCallback1<WKNavigationResponsePolicy>
    ) {
        let response = navigationResponse.response
        let disposition = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || disposition.contains("attachment") {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
        guard navigationResponse.isForMainFrame,
              let tab = tab(for: webView),
              let httpResponse = response as? HTTPURLResponse else { return }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403
            || (500 ... 599).contains(httpResponse.statusCode) {
            tab.failedURL = response.url
            tab.failedRequest = tab.pendingMainFrameRequest
        }
        let canRetry = BrowserSupport.isSafeToRetry(tab.failedRequest)
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            tab.errorView.show(
                title: "Sign-In or Access Was Not Completed",
                message: retryAwareMessage(
                    "The website returned HTTP \(httpResponse.statusCode). Check your account access. If the site does not allow embedded sign-in, continue in your default browser.",
                    canRetry: canRetry
                ),
                symbol: "person.crop.circle.badge.exclamationmark",
                canRetry: canRetry,
                canOpenExternally: BrowserSupport.isWebURL(response.url ?? webView.url),
                canDismiss: true
            )
        } else if (500 ... 599).contains(httpResponse.statusCode) {
            tab.errorView.show(
                title: "Website Server Temporarily Unavailable",
                message: retryAwareMessage(
                    "The server returned HTTP \(httpResponse.statusCode). This is usually not a local CornerFloat problem.",
                    canRetry: canRetry
                ),
                symbol: "server.rack",
                canRetry: canRetry,
                canOpenExternally: BrowserSupport.isWebURL(response.url ?? webView.url),
                canDismiss: true
            )
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        guard let tab = addTab(
            configuration: configuration,
            select: true,
            source: .websitePopup
        ) else { return nil }
        tab.pendingMainFrameRequest = navigationAction.request
        return tab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }
        closeTab(id: tab.id)
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping WebKitCallback1<[URL]?>
    ) {
        guard let panel else {
            completionHandler(nil)
            return
        }
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canCreateDirectories = false
        openPanel.resolvesAliases = true
        openPanel.message = "Select only files you want to upload to this website"
        openPanel.prompt = "Select & Upload"
        openPanel.beginSheetModal(for: panel) { response in
            completionHandler(response == .OK ? openPanel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping WebKitCallback1<WKPermissionDecision>
    ) {
        let capture: BrowserSupport.MediaCaptureKind
        switch type {
        case .microphone:
            capture = .microphone
        case .camera:
            capture = .camera
        case .cameraAndMicrophone:
            capture = .cameraAndMicrophone
        @unknown default:
            capture = .unknown
        }
        let decision = BrowserSupport.mediaCaptureDecision(
            scheme: origin.protocol,
            capture: capture
        )
        guard decision == .prompt else {
            decisionHandler(.deny)
            return
        }

        beginMicrophoneRoutePreflight(
            for: webView,
            decisionHandler: decisionHandler
        )
    }

    private func beginMicrophoneRoutePreflight(
        for webView: WKWebView,
        decisionHandler: @escaping WebKitCallback1<WKPermissionDecision>
    ) {
        // A website should not be able to stack route sheets or strand an
        // earlier WebKit completion handler.
        guard pendingVoiceRouteRequest == nil else {
            decisionHandler(.deny)
            return
        }

        let assessment: VoiceRouteAssessment
        do {
            assessment = try Self.sharedVoiceAudioRouteCoordinator.assessment()
        } catch {
            // Failure to inspect optional audio metadata must never break an
            // otherwise valid HTTPS microphone request.
            fputs("CornerFloat could not inspect the current audio route: \(error)\n", stderr)
            decisionHandler(.prompt)
            return
        }

        var machine = VoiceRoutePreflightMachine()
        let initialEffects = machine.begin(with: assessment)
        if !initialEffects.isEmpty {
            applyVoiceRouteEffects(
                initialEffects,
                machine: &machine,
                webView: webView,
                decisionHandler: decisionHandler
            )
            return
        }

        let hasBuiltInAlternative = assessment.recommendedBuiltInInput != nil
        pendingVoiceRouteRequest = PendingVoiceRouteRequest(
            machine: machine,
            webView: webView,
            decisionHandler: decisionHandler,
            hasBuiltInAlternative: hasBuiltInAlternative
        )

        let alert = makeBluetoothVoiceRouteAlert(assessment: assessment)
        activeVoiceRouteAlert = alert
        present(alert) { [weak self] response in
            self?.completeVoiceRoutePreflight(response: response)
        }
    }

    private func makeBluetoothVoiceRouteAlert(
        assessment: VoiceRouteAssessment
    ) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Improve Bluetooth Voice Audio?"

        let inputName = assessment.snapshot.defaultInput?.name ?? "Bluetooth microphone"
        let outputName = assessment.snapshot.defaultOutput?.name ?? "Bluetooth headphones"
        let rateText: String
        if let rate = assessment.snapshot.defaultInput?.nominalSampleRate {
            rateText = " (\(Int(rate / 1_000)) kHz)"
        } else {
            rateText = ""
        }
        let alternativeText: String
        if let alternative = assessment.recommendedBuiltInInput {
            alternativeText = "Use Mac Microphone temporarily changes only the system input to \(alternative.name), while \(outputName) remains available for listening. CornerFloat restores the previous input after voice capture ends unless you change it yourself."
            alert.addButton(withTitle: "Use Mac Microphone")
            alert.addButton(withTitle: "Continue with Bluetooth")
            alert.addButton(withTitle: "Cancel")
        } else {
            alternativeText = "No built-in microphone is currently available. You can continue with Bluetooth or cancel and choose another input in System Settings."
            alert.addButton(withTitle: "Continue with Bluetooth")
            alert.addButton(withTitle: "Cancel")
        }

        alert.informativeText = "\(inputName) is the current input\(rateText) while \(outputName) is the current output. macOS can switch Bluetooth headphones to a lower-bandwidth two-way call mode, making live AI speech sound deep, slow, or delayed.\n\n\(alternativeText)"
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert
    }

    private func completeVoiceRoutePreflight(
        response: NSApplication.ModalResponse
    ) {
        guard var request = pendingVoiceRouteRequest else { return }
        pendingVoiceRouteRequest = nil
        activeVoiceRouteAlert = nil

        let decision: VoiceRouteDecision
        if request.hasBuiltInAlternative {
            switch response {
            case .alertFirstButtonReturn:
                decision = .useBuiltInInput
            case .alertSecondButtonReturn:
                decision = .continueCurrentRoute
            default:
                decision = .cancel
            }
        } else {
            decision = response == .alertFirstButtonReturn
                ? .continueCurrentRoute
                : .cancel
        }

        let effects = request.machine.handle(decision)
        applyVoiceRouteEffects(
            effects,
            machine: &request.machine,
            webView: request.webView,
            decisionHandler: request.decisionHandler
        )
    }

    private func applyVoiceRouteEffects(
        _ effects: [VoiceRoutePreflightEffect],
        machine: inout VoiceRoutePreflightMachine,
        webView: WKWebView,
        decisionHandler: WebKitCallback1<WKPermissionDecision>
    ) {
        guard let effect = effects.first else { return }
        switch effect {
        case .setDefaultInput(let deviceID):
            do {
                let previousID = try Self.sharedVoiceAudioRouteCoordinator
                    .useBuiltInInput(deviceID)
                let next = machine.completeSwitch(
                    succeeded: true,
                    previousID: previousID
                )
                applyVoiceRouteEffects(
                    next,
                    machine: &machine,
                    webView: webView,
                    decisionHandler: decisionHandler
                )
            } catch {
                let next = machine.completeSwitch(succeeded: false)
                applyVoiceRouteEffects(
                    next,
                    machine: &machine,
                    webView: webView,
                    decisionHandler: decisionHandler
                )
                DispatchQueue.main.async { [weak self] in
                    self?.presentVoiceRouteFailure()
                }
            }

        case .allowCapture:
            Self.sharedVoiceAudioRouteCoordinator.prepareForCapture(in: webView)
            decisionHandler(.prompt)

        case .denyCapture:
            decisionHandler(.deny)

        case .restoreDefaultInput:
            // Restoration belongs to the shared coordinator because another
            // panel may still be capturing when this request completes.
            break
        }
    }

    private func presentVoiceRouteFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Change Microphone"
        alert.informativeText = "CornerFloat could not complete the temporary microphone change. Review the current input in System Settings → Sound → Input, then try voice mode again."
        alert.addButton(withTitle: "OK")
        present(alert) { _ in }
    }

    private func cancelPendingVoiceRouteRequest(for webView: WKWebView) {
        guard let request = pendingVoiceRouteRequest,
              request.webView === webView else { return }
        pendingVoiceRouteRequest = nil
        request.decisionHandler(.deny)

        if let alertWindow = activeVoiceRouteAlert?.window,
           let sheetParent = alertWindow.sheetParent {
            sheetParent.endSheet(alertWindow, returnCode: .cancel)
        }
        activeVoiceRouteAlert = nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping WebKitCallback0
    ) {
        presentJavaScriptAlert(message: message, buttons: ["OK"], webView: webView) {
            _ in completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping WebKitCallback1<Bool>
    ) {
        presentJavaScriptAlert(
            message: message,
            buttons: ["Allow", "Cancel"],
            webView: webView
        ) {
            completionHandler($0 == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping WebKitCallback1<String?>
    ) {
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        let alert = makeWebsiteAlert(
            message: prompt,
            buttons: ["OK", "Cancel"],
            webView: webView
        )
        alert.accessoryView = input
        present(alert) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        show(error: error, in: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        show(error: error, in: webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }
        let failureURL = webView.url
            ?? tab.lastCommittedURL
            ?? tab.pendingMainFrameRequest?.url
        tab.failedURL = failureURL
        tab.failedRequest = tab.pendingMainFrameRequest
        let canRetry = BrowserSupport.isSafeToRetry(tab.failedRequest)
        tab.errorView.show(
            title: "Web Process Stopped",
            message: retryAwareMessage(
                "The page may have used too many resources or quit unexpectedly. Reloading will not clear sign-in data.",
                canRetry: canRetry
            ),
            symbol: "exclamationmark.arrow.triangle.2.circlepath",
            canRetry: canRetry,
            canOpenExternally: BrowserSupport.isWebURL(failureURL)
        )
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping WebKitCallback2<URLSession.AuthChallengeDisposition, URLCredential?>
    ) {
        if challenge.previousFailureCount > 0 {
            completionHandler(.cancelAuthenticationChallenge, nil)
            guard let tab = tab(for: webView) else { return }
            let failureURL = webView.url
                ?? tab.pendingMainFrameRequest?.url
                ?? tab.lastCommittedURL
            tab.failedURL = failureURL
            tab.failedRequest = tab.pendingMainFrameRequest
            let canRetry = BrowserSupport.isSafeToRetry(tab.failedRequest)
            tab.errorView.show(
                title: "Authentication Failed",
                message: retryAwareMessage(
                    "The server rejected the supplied credentials. Check the account or continue signing in with your default browser.",
                    canRetry: canRetry
                ),
                symbol: "lock.trianglebadge.exclamationmark",
                canRetry: canRetry,
                canOpenExternally: BrowserSupport.isWebURL(failureURL)
            )
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(
        _ webView: WKWebView,
        authenticationChallenge challenge: URLAuthenticationChallenge,
        shouldAllowDeprecatedTLS decisionHandler: @escaping WebKitCallback1<Bool>
    ) {
        decisionHandler(false)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        register(download)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        register(download)
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping WebKitCallback1<URL?>
    ) {
        destinationQueue.append(PendingDownloadDestination(
            downloadID: ObjectIdentifier(download),
            suggestedFilename: BrowserSupport.safeSuggestedFilename(suggestedFilename),
            completion: completionHandler
        ))
        presentNextDownloadDestinationPicker()
    }

    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping WebKitCallback1<WKDownload.RedirectPolicy>
    ) {
        decisionHandler(BrowserSupport.isWebURL(request.url) ? .allow : .cancel)
    }

    func download(
        _ download: WKDownload,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping WebKitCallback2<URLSession.AuthChallengeDisposition, URLCredential?>
    ) {
        completionHandler(challenge.previousFailureCount == 0
            ? .performDefaultHandling
            : .cancelAuthenticationChallenge, nil)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        activeDownloads.removeValue(forKey: id)
        guard let transaction = downloadTransactions.removeValue(forKey: id) else { return }
        do {
            try transaction.commit()
        } catch {
            discardDownloadTransaction(transaction)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could Not Save Download"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            present(alert, completion: { _ in })
            return
        }

        let destination = transaction.finalURL
        let alert = NSAlert()
        alert.messageText = "Download Complete"
        alert.informativeText = destination.path
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")
        present(alert) { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let id = ObjectIdentifier(download)
        activeDownloads.removeValue(forKey: id)
        if let transaction = downloadTransactions.removeValue(forKey: id) {
            discardDownloadTransaction(transaction)
        }
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Download Failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        present(alert, completion: { _ in })
    }

    private func register(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        activeDownloads[id] = download
        download.delegate = self
    }

    private func presentNextDownloadDestinationPicker() {
        guard !isPresentingDestinationPicker, !destinationQueue.isEmpty else { return }
        guard let panel else {
            let queue = destinationQueue
            destinationQueue.removeAll()
            queue.forEach { $0.completion(nil) }
            return
        }

        isPresentingDestinationPicker = true
        let pending = destinationQueue.removeFirst()
        let savePanel = NSSavePanel()
        activeSavePanel = savePanel
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = pending.suggestedFilename
        savePanel.message = "Choose where to save the downloaded file"
        savePanel.prompt = "Download"
        savePanel.beginSheetModal(for: panel) { [weak self] response in
            guard let self else {
                pending.completion(nil)
                return
            }
            var webKitDestination: URL?
            if response == .OK, let selectedURL = savePanel.url {
                do {
                    let transaction = try DownloadDestinationTransaction(
                        finalURL: selectedURL
                    )
                    self.downloadTransactions[pending.downloadID] = transaction
                    webKitDestination = transaction.stagingURL
                } catch {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Could Not Prepare Download"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK")
                    self.present(alert, completion: { _ in })
                }
            }
            pending.completion(webKitDestination)
            self.activeSavePanel = nil
            self.isPresentingDestinationPicker = false
            self.presentNextDownloadDestinationPicker()
        }
    }

    private func discardDownloadTransaction(_ transaction: DownloadDestinationTransaction) {
        do {
            try transaction.discard()
        } catch {
            fputs(
                "CornerFloat could not clean up a temporary download: \(error.localizedDescription)\n",
                stderr
            )
        }
    }

    private func show(error: Error, in webView: WKWebView) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled, let tab = tab(for: webView) else { return }
        let legacyFailureURL: URL?
        if #unavailable(macOS 15.4) {
            legacyFailureURL = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
                .flatMap(URL.init(string:))
        } else {
            legacyFailureURL = nil
        }
        let failureURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? legacyFailureURL
            ?? tab.pendingMainFrameRequest?.url
            ?? webView.url
        tab.failedURL = failureURL
        tab.failedRequest = tab.pendingMainFrameRequest
        let canRetry = BrowserSupport.isSafeToRetry(tab.failedRequest)
        let title: String
        var message: String
        let symbol: String
        switch BrowserSupport.failureKind(for: error) {
        case .offline:
            title = "No Internet Connection"
            message = "Check Wi-Fi or network settings, then try again."
            symbol = "wifi.slash"
        case .timedOut:
            title = "Website Timed Out"
            message = "The server did not respond in time. Try again when the network connection recovers."
            symbol = "clock.badge.exclamationmark"
        case .dns:
            title = "Website Not Found"
            message = "The website address could not be resolved. Check the spelling, or enter keywords as a search query."
            symbol = "network.slash"
        case .tls:
            title = "Could Not Establish a Secure Connection"
            message = "The website certificate is invalid or the connection uses insecure TLS. CornerFloat will not bypass certificate validation."
            symbol = "lock.trianglebadge.exclamationmark"
        case .accessDenied:
            title = "Website Denied Access"
            message = "Check your sign-in status and account access, or continue in your default browser."
            symbol = "person.crop.circle.badge.exclamationmark"
        case .generic:
            title = "Page Could Not Load"
            message = nsError.localizedDescription
            symbol = "exclamationmark.triangle"
        }
        message = retryAwareMessage(message, canRetry: canRetry)
        tab.errorView.show(
            title: title,
            message: message,
            symbol: symbol,
            canRetry: canRetry,
            canOpenExternally: BrowserSupport.isWebURL(failureURL),
            canDismiss: tab.lastCommittedURL != nil
        )
        updateNavigationButtons()
    }

    private func retry(_ tab: BrowserTab) {
        guard let request = tab.failedRequest,
              BrowserSupport.isSafeToRetry(request) else {
            NSSound.beep()
            return
        }
        tab.errorView.hide()
        tab.pendingMainFrameRequest = request
        tab.failedRequest = nil
        tab.failedURL = nil
        tab.webView.load(request)
    }

    private func openExternally(_ tab: BrowserTab) {
        guard let url = tab.failedURL
                ?? tab.pendingMainFrameRequest?.url
                ?? tab.webView.url
                ?? tab.lastCommittedURL,
              BrowserSupport.isWebURL(url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openVisiblePageExternally(_ tab: BrowserTab) {
        guard let url = tab.webView.url
                ?? tab.lastCommittedURL
                ?? tab.pendingMainFrameRequest?.url,
              BrowserSupport.isWebURL(url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func retryAwareMessage(_ message: String, canRetry: Bool) -> String {
        guard !canRetry else { return message }
        return message
            + " CornerFloat will not automatically resend form data. Return to the previous page and submit again only if you intend to."
    }

    private func openExternalApplicationURL(_ url: URL, requiresConfirmation: Bool) {
        guard requiresConfirmation else {
            NSWorkspace.shared.open(url)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Open Another App?"
        alert.informativeText = "This page wants to open the \(url.scheme ?? "other") app. Continue only if you expected a sign-in or another external action."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        present(alert) { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func presentUnsafeFormReplayNotice(url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Form Was Not Resubmitted"
        alert.informativeText = "CornerFloat blocked an automatic replay of form data to \(url.host ?? "this website"). Return to the original form and submit it again only if you intend to repeat the action."
        alert.addButton(withTitle: "OK")
        present(alert, completion: { _ in })
    }

    private func tab(for webView: WKWebView) -> BrowserTab? {
        tabs.first { $0.webView === webView }
    }

    private func updateTabTitle(_ tab: BrowserTab) {
        let title = tab.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = tab.webView.url?.host?.replacingOccurrences(of: "www.", with: "")
        tab.displayTitle = title?.isEmpty == false ? title! : (host ?? "New Tab")
        tabItemViews[tab.id]?.update(title: tab.displayTitle)
        if tab === selectedTab {
            updateWindowTitle(using: tab)
        }
    }

    private func updateWindowTitle(using tab: BrowserTab) {
        let host = tab.webView.url?.host?.replacingOccurrences(of: "www.", with: "")
            ?? tab.failedURL?.host?.replacingOccurrences(of: "www.", with: "")
            ?? tab.lastCommittedURL?.host?.replacingOccurrences(of: "www.", with: "")
            ?? tab.pendingMainFrameRequest?.url?.host?.replacingOccurrences(of: "www.", with: "")
            ?? "Web Page"
        updateDisplayName("Web · \(host)")
    }

    private func updateNavigationButtons() {
        backToolbarItem?.isEnabled = selectedTab?.webView.canGoBack == true
        forwardToolbarItem?.isEnabled = selectedTab?.webView.canGoForward == true
        guard let webView = selectedTab?.webView else {
            securityToolbarItem?.isEnabled = false
            return
        }
        let state = BrowserSupport.connectionSecurityState(
            for: webView.url,
            hasOnlySecureContent: webView.hasOnlySecureContent,
            hasServerTrust: webView.serverTrust != nil
        )
        let presentation: (symbol: String, label: String)
        switch state {
        case .secure:
            presentation = ("lock.fill", "Secure Connection")
        case .insecure:
            presentation = (
                "exclamationmark.triangle.fill",
                "Connection Is Not Fully Secure"
            )
        case .localContent:
            presentation = ("network", "Connection Information")
        }
        securityToolbarItem?.image = NSImage(
            systemSymbolName: presentation.symbol,
            accessibilityDescription: presentation.label
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        securityToolbarItem?.toolTip = presentation.label
        securityToolbarItem?.label = presentation.label
        securityToolbarItem?.isEnabled = webView.url != nil
    }

    private func makeWebsiteAlert(
        message: String,
        buttons: [String],
        webView: WKWebView
    ) -> NSAlert {
        let alert = NSAlert()
        let host = webView.url?.host ?? "Current Website"
        alert.messageText = host
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert
    }

    private func presentJavaScriptAlert(
        message: String,
        buttons: [String],
        webView: WKWebView,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        present(
            makeWebsiteAlert(message: message, buttons: buttons, webView: webView),
            completion: completion
        )
    }

    private func present(
        _ alert: NSAlert,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        if let panel {
            alert.beginSheetModal(for: panel, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    override func visibilityDidChange(isVisible: Bool) {
        if isVisible {
            presentPendingTabLimitNoticeIfPossible()
        }
    }

    override func prepareForClose() {
        if let tabCyclingMonitor {
            NSEvent.removeMonitor(tabCyclingMonitor)
            self.tabCyclingMonitor = nil
        }
        if let alertWindow = activeTabLimitAlert?.window,
           let sheetParent = alertWindow.sheetParent {
            sheetParent.endSheet(alertWindow, returnCode: .cancel)
        }
        activeTabLimitAlert = nil
        pendingTabLimitMessage = nil

        if let request = pendingVoiceRouteRequest {
            pendingVoiceRouteRequest = nil
            request.decisionHandler(.deny)
        }
        if let alertWindow = activeVoiceRouteAlert?.window,
           let sheetParent = alertWindow.sheetParent {
            sheetParent.endSheet(alertWindow, returnCode: .cancel)
        }
        activeVoiceRouteAlert = nil

        activeSavePanel?.cancel(nil)
        let pending = destinationQueue
        destinationQueue.removeAll()
        pending.forEach { $0.completion(nil) }
        let transactions = downloadTransactions
        downloadTransactions.removeAll()
        for (id, download) in activeDownloads {
            let transaction = transactions[id]
            download.cancel { _ in
                // A second cleanup after WebKit acknowledges cancellation closes
                // the small race where it creates the staging file while the
                // panel is tearing down.
                try? transaction?.discard()
            }
            download.delegate = nil
        }
        activeDownloads.removeAll()
        for transaction in transactions.values {
            discardDownloadTransaction(transaction)
        }

        for tab in tabs {
            Self.sharedVoiceAudioRouteCoordinator.unregister(tab.webView)
            tab.webView.stopLoading()
            tab.webView.navigationDelegate = nil
            tab.webView.uiDelegate = nil
        }
        tabs.removeAll()
        tabItemViews.removeAll()
    }

    private static func restoredContentSize() -> CGSize {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: savedWidthKey)
        let height = defaults.double(forKey: savedHeightKey)
        guard width >= 340, height >= 460, width <= 10_000, height <= 10_000 else {
            return CGSize(width: 420, height: 640)
        }
        return CGSize(width: width, height: height)
    }
}
