import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private weak var owner: AppController?
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var needsRefresh = true
    private var isMenuOpen = false

    init(owner: AppController) {
        self.owner = owner
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle.circle.fill",
                accessibilityDescription: "CornerFloat"
            )
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "CornerFloat"
        }

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func requestRefresh() {
        needsRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isMenuOpen else { return }
            self.rebuildMenu()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        if needsRefresh {
            rebuildMenu()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if needsRefresh {
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        needsRefresh = false
        menu.removeAllItems()

        addItem(
            title: "Open ChatGPT Panel",
            symbol: "message.fill",
            action: #selector(openChatGPT),
            keyEquivalent: "n"
        )
        addItem(title: "Open Web Page…", symbol: "globe", action: #selector(openWebPage))

        menu.addItem(.separator())
        let shortcut = NSMenuItem(
            title: "Show or Hide All Panels",
            action: #selector(toggleAll),
            keyEquivalent: " "
        )
        shortcut.target = self
        shortcut.keyEquivalentModifierMask = owner?.globalShortcutMenuModifiers ?? [.command, .shift]
        shortcut.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        menu.addItem(shortcut)

        let edgeAutoHide = NSMenuItem(
            title: "Edge Auto-Hide",
            action: #selector(toggleEdgeAutoHide),
            keyEquivalent: ""
        )
        edgeAutoHide.target = self
        edgeAutoHide.state = owner?.isEdgeAutoHideEnabled == true ? .on : .off
        edgeAutoHide.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
        menu.addItem(edgeAutoHide)

        if owner?.isGlobalHotKeyRegistered == false {
            let warning = NSMenuItem(title: "Global shortcut unavailable", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            warning.toolTip = owner?.globalHotKeyError
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warning)
        }

        menu.addItem(.separator())
        addItem(
            title: CFL10n.text("窗口与资料库管理…", "Windows & Library…"),
            symbol: "rectangle.3.group",
            action: #selector(showLibraryManager)
        )
        menu.addItem(makeBookmarksMenuItem())
        menu.addItem(makeQuickSitesMenuItem())
        menu.addItem(makeRecentsMenuItem())
        menu.addItem(makeWorkspacesMenuItem())

        if let panels = owner?.panels, !panels.isEmpty {
            menu.addItem(.separator())

            let header = NSMenuItem(title: "Current Floating Windows", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for panel in panels {
                menu.addItem(makePanelItem(panel))
            }

            menu.addItem(.separator())
            let visibilityTitle = owner?.hasVisiblePanels == true
                ? "Hide All Floating Windows"
                : "Show All Floating Windows"
            addItem(
                title: visibilityTitle,
                symbol: owner?.hasVisiblePanels == true ? "eye.slash" : "eye",
                action: #selector(toggleAll)
            )
            addItem(title: "Close & Remove All Floating Windows", symbol: "xmark.circle", action: #selector(closeAll))
        }

        menu.addItem(.separator())

        let openOnLaunch = NSMenuItem(
            title: "Open ChatGPT When CornerFloat Starts",
            action: #selector(toggleOpenOnLaunch),
            keyEquivalent: ""
        )
        openOnLaunch.target = self
        openOnLaunch.state = owner?.opensChatGPTOnLaunch == true ? .on : .off
        menu.addItem(openOnLaunch)

        if owner?.canManagePasskeyAccess == true {
            let passkeys = NSMenuItem(
                title: "Enable or Review Passkey Access…",
                action: #selector(enableOrReviewPasskeyAccess),
                keyEquivalent: ""
            )
            passkeys.target = self
            passkeys.image = NSImage(systemSymbolName: "key", accessibilityDescription: nil)
            menu.addItem(passkeys)
        }

        if owner?.hasConfiguredUpdateChannel == true {
            addItem(title: "Check for Updates…", symbol: "arrow.triangle.2.circlepath", action: #selector(checkForUpdates))
        }
        addItem(title: "Settings…", symbol: "gearshape", action: #selector(showSettings))
        addItem(title: "Show Welcome", symbol: "sparkles", action: #selector(showWelcome))
        addItem(title: "Privacy Policy", symbol: "hand.raised", action: #selector(showPrivacy))
        addItem(title: "CornerFloat Support", symbol: "questionmark.circle", action: #selector(showSupport))
        addItem(title: "About CornerFloat", symbol: "info.circle", action: #selector(showAbout))
        menu.addItem(.separator())
        addItem(title: "Quit CornerFloat", symbol: "power", action: #selector(quit), keyEquivalent: "q")
    }

    private func makePanelItem(_ panel: FloatingPanelController) -> NSMenuItem {
        let submenu = NSMenu()

        let visibility = NSMenuItem(
            title: panel.isEdgeAutoHidden ? "Reveal & Focus" : (panel.isVisible ? "Hide" : "Show"),
            action: #selector(togglePanelVisibility(_:)),
            keyEquivalent: ""
        )
        visibility.target = self
        visibility.representedObject = panel
        submenu.addItem(visibility)

        let corner = NSMenuItem(title: "Move to Bottom Right", action: #selector(moveToCorner(_:)), keyEquivalent: "")
        corner.target = self
        corner.representedObject = panel
        submenu.addItem(corner)

        let edgeAutoHide = NSMenuItem(
            title: "Edge Auto-Hide",
            action: #selector(togglePanelEdgeAutoHide(_:)),
            keyEquivalent: ""
        )
        edgeAutoHide.target = self
        edgeAutoHide.representedObject = panel
        edgeAutoHide.state = panel.isEdgeAutoHideEnabled ? .on : .off
        submenu.addItem(edgeAutoHide)

        let sizeMenu = NSMenu()
        for preset in PanelSizePreset.allCases {
            let action = PanelSizeAction(panel: panel, preset: preset)
            let item = NSMenuItem(
                title: preset.title,
                action: #selector(applySizePreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = action
            sizeMenu.addItem(item)
        }
        sizeMenu.addItem(.separator())

        let shrink = NSMenuItem(title: "Make Smaller", action: #selector(shrinkPanel(_:)), keyEquivalent: "")
        shrink.target = self
        shrink.representedObject = panel
        shrink.image = NSImage(systemSymbolName: "minus", accessibilityDescription: nil)
        sizeMenu.addItem(shrink)

        let expand = NSMenuItem(title: "Make Larger", action: #selector(expandPanel(_:)), keyEquivalent: "")
        expand.target = self
        expand.representedObject = panel
        expand.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        sizeMenu.addItem(expand)

        let sizeItem = NSMenuItem(title: "Window Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        submenu.addItem(sizeItem)

        let opacityMenu = NSMenu()
        for value in [1.0, 0.85, 0.7, 0.5, 0.3] {
            let percent = Int(value * 100)
            let action = OpacityAction(panel: panel, value: value)
            let item = NSMenuItem(title: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            item.state = abs(panel.opacity - value) < 0.01 ? .on : .off
            opacityMenu.addItem(item)
        }
        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacity.submenu = opacityMenu
        submenu.addItem(opacity)

        let clickThrough = NSMenuItem(title: "Click-Through", action: #selector(toggleClickThrough(_:)), keyEquivalent: "")
        clickThrough.target = self
        clickThrough.representedObject = panel
        clickThrough.state = panel.isClickThrough ? .on : .off
        clickThrough.toolTip = "When enabled, mouse input passes through the window; disable it to drag or resize"
        submenu.addItem(clickThrough)

        submenu.addItem(.separator())
        let close = NSMenuItem(title: "Close & Remove", action: #selector(closePanel(_:)), keyEquivalent: "")
        close.target = self
        close.representedObject = panel
        submenu.addItem(close)

        let panelTitle = panel.displayName.count > 44
            ? String(panel.displayName.prefix(43)) + "…"
            : panel.displayName
        let item = NSMenuItem(title: panelTitle, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func addItem(
        title: String,
        symbol: String,
        action: Selector,
        keyEquivalent: String = ""
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menu.addItem(item)
    }

    private func makeBookmarksMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let bookmarks = owner?.bookmarks ?? []
        if bookmarks.isEmpty {
            let empty = NSMenuItem(
                title: CFL10n.text("还没有收藏", "No Favorites Yet"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for bookmark in bookmarks.prefix(10) {
                submenu.addItem(libraryActionItem(
                    title: shortened(bookmark.title),
                    symbol: "star.fill",
                    action: #selector(openBookmark(_:)),
                    id: bookmark.id
                ))
            }
        }
        submenu.addItem(.separator())
        let addCurrent = NSMenuItem(
            title: CFL10n.text("收藏当前网页", "Add Current Page to Favorites"),
            action: #selector(bookmarkCurrentPage),
            keyEquivalent: "d"
        )
        addCurrent.target = self
        addCurrent.isEnabled = owner?.canBookmarkActivePage == true
        addCurrent.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        submenu.addItem(addCurrent)
        submenu.addItem(managerSectionItem(
            title: CFL10n.text("管理收藏…", "Manage Favorites…"),
            section: .bookmarks
        ))

        let item = NSMenuItem(title: CFL10n.text("收藏", "Favorites"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        item.submenu = submenu
        return item
    }

    private func makeRecentsMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let recents = owner?.recentDestinations ?? []
        if recents.isEmpty {
            let empty = NSMenuItem(
                title: CFL10n.text("没有最近访问记录", "No Recent Destinations"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for recent in recents.prefix(10) {
                submenu.addItem(libraryActionItem(
                    title: shortened(recent.title),
                    symbol: "clock",
                    action: #selector(openRecent(_:)),
                    id: recent.id
                ))
            }
            submenu.addItem(.separator())
            let clear = NSMenuItem(
                title: CFL10n.text("清除最近访问记录", "Clear Recent Destinations"),
                action: #selector(clearRecents),
                keyEquivalent: ""
            )
            clear.target = self
            submenu.addItem(clear)
        }
        submenu.addItem(managerSectionItem(
            title: CFL10n.text("查看全部最近访问…", "Show All Recent Destinations…"),
            section: .recents
        ))

        let item = NSMenuItem(title: CFL10n.text("最近访问", "Recent"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        item.submenu = submenu
        return item
    }

    private func makeQuickSitesMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let shortcuts = owner?.quickSites ?? []
        if shortcuts.isEmpty {
            let empty = NSMenuItem(
                title: CFL10n.text("还没有快捷网站", "No Quick Sites Yet"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for shortcut in shortcuts.prefix(12) {
                let alias = shortcut.aliases.first.map { " · \($0)" } ?? ""
                submenu.addItem(libraryActionItem(
                    title: shortened(shortcut.name) + alias,
                    symbol: "bolt.fill",
                    action: #selector(openQuickSite(_:)),
                    id: shortcut.id
                ))
            }
        }
        submenu.addItem(.separator())
        let add = NSMenuItem(
            title: CFL10n.text("添加快捷网站…", "Add Quick Site…"),
            action: #selector(addQuickSite),
            keyEquivalent: ""
        )
        add.target = self
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        submenu.addItem(add)
        submenu.addItem(managerSectionItem(
            title: CFL10n.text("管理快捷网站…", "Manage Quick Sites…"),
            section: .shortcuts
        ))

        let item = NSMenuItem(title: CFL10n.text("快捷网站", "Quick Sites"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)
        item.submenu = submenu
        return item
    }

    private func makeWorkspacesMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let workspaces = owner?.savedWorkspaces ?? []
        if workspaces.isEmpty {
            let empty = NSMenuItem(
                title: CFL10n.text("还没有保存的工作区", "No Saved Workspaces"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for workspace in workspaces.prefix(10) {
                let title = "\(shortened(workspace.name))  ·  \(workspace.panels.count)"
                submenu.addItem(libraryActionItem(
                    title: title,
                    symbol: "square.grid.2x2",
                    action: #selector(openWorkspace(_:)),
                    id: workspace.id
                ))
            }
        }
        submenu.addItem(.separator())
        let save = NSMenuItem(
            title: CFL10n.text("保存当前工作区…", "Save Current Workspace…"),
            action: #selector(saveCurrentWorkspace),
            keyEquivalent: "s"
        )
        save.target = self
        save.keyEquivalentModifierMask = [.command, .option]
        save.image = NSImage(systemSymbolName: "plus.square.on.square", accessibilityDescription: nil)
        submenu.addItem(save)
        submenu.addItem(managerSectionItem(
            title: CFL10n.text("管理工作区…", "Manage Workspaces…"),
            section: .workspaces
        ))

        let item = NSMenuItem(title: CFL10n.text("工作区", "Workspaces"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        item.submenu = submenu
        return item
    }

    private func libraryActionItem(
        title: String,
        symbol: String,
        action: Selector,
        id: UUID
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id.uuidString
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private func managerSectionItem(title: String, section: CornerFloatManagerSection) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(showManagerSection(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = section.rawValue
        return item
    }

    private func shortened(_ text: String) -> String {
        text.count > 46 ? String(text.prefix(45)) + "…" : text
    }

    @objc private func openChatGPT() { owner?.openChatGPTPanel() }
    @objc private func openWebPage() { owner?.promptForWebPage() }
    @objc private func showLibraryManager() { owner?.showLibraryManager() }
    @objc private func bookmarkCurrentPage() { owner?.bookmarkActivePage() }
    @objc private func clearRecents() { owner?.requestClearRecentDestinations() }
    @objc private func saveCurrentWorkspace() { owner?.promptToSaveCurrentWorkspace() }
    @objc private func addQuickSite() { owner?.promptToAddQuickSite() }
    @objc private func closeAll() { owner?.requestCloseAllPanels() }
    @objc private func toggleAll() { owner?.toggleAllPanelsVisibility() }
    @objc private func toggleEdgeAutoHide() { owner?.toggleEdgeAutoHide() }
    @objc private func toggleOpenOnLaunch() { owner?.toggleOpenChatGPTOnLaunch() }
    @objc private func enableOrReviewPasskeyAccess() { owner?.enableOrReviewPasskeyAccess() }
    @objc private func showAbout() { owner?.showAbout() }
    @objc private func checkForUpdates() { owner?.checkForUpdates() }
    @objc private func showSettings() { owner?.showSettings() }
    @objc private func showWelcome() { owner?.showWelcome() }
    @objc private func showPrivacy() { owner?.showPrivacyPolicy() }
    @objc private func showSupport() { owner?.showSupport() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openBookmark(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String, let id = UUID(uuidString: string) else { return }
        owner?.openBookmark(id: id)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String, let id = UUID(uuidString: string) else { return }
        owner?.openRecentDestination(id: id)
    }

    @objc private func openQuickSite(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String,
              let id = UUID(uuidString: string) else { return }
        owner?.openQuickSite(id: id)
    }

    @objc private func openWorkspace(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String, let id = UUID(uuidString: string) else { return }
        owner?.restoreWorkspace(id: id, replacingCurrentPanels: false)
    }

    @objc private func showManagerSection(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int,
              let section = CornerFloatManagerSection(rawValue: rawValue) else { return }
        owner?.showLibraryManager(section: section)
    }

    @objc private func togglePanelVisibility(_ sender: NSMenuItem) {
        guard let panel = sender.representedObject as? FloatingPanelController else { return }
        if panel.isEdgeAutoHidden {
            panel.revealFromEdge(activating: true)
        } else {
            panel.toggleVisibility()
        }
    }

    @objc private func togglePanelEdgeAutoHide(_ sender: NSMenuItem) {
        guard let panel = sender.representedObject as? FloatingPanelController else { return }
        owner?.toggleEdgeAutoHide(for: panel)
    }

    @objc private func moveToCorner(_ sender: NSMenuItem) {
        (sender.representedObject as? FloatingPanelController)?.moveToBottomRight()
    }

    @objc private func applySizePreset(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? PanelSizeAction else { return }
        action.panel?.applySizePreset(action.preset)
    }

    @objc private func shrinkPanel(_ sender: NSMenuItem) {
        (sender.representedObject as? FloatingPanelController)?.resizeWindow(by: 0.86)
    }

    @objc private func expandPanel(_ sender: NSMenuItem) {
        (sender.representedObject as? FloatingPanelController)?.resizeWindow(by: 1.16)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? OpacityAction else { return }
        action.panel?.setOpacity(action.value)
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        (sender.representedObject as? FloatingPanelController)?.toggleClickThrough()
    }

    @objc private func closePanel(_ sender: NSMenuItem) {
        (sender.representedObject as? FloatingPanelController)?.close()
    }
}

@MainActor
private final class OpacityAction: NSObject {
    weak var panel: FloatingPanelController?
    let value: CGFloat

    init(panel: FloatingPanelController, value: CGFloat) {
        self.panel = panel
        self.value = value
    }
}

@MainActor
private final class PanelSizeAction: NSObject {
    weak var panel: FloatingPanelController?
    let preset: PanelSizePreset

    init(panel: FloatingPanelController, preset: PanelSizePreset) {
        self.panel = panel
        self.preset = preset
    }
}
