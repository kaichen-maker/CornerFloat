import AppKit

/// Supplies a complete, conventional Mac menu bar even though CornerFloat is
/// primarily a menu-bar utility.
@MainActor
final class MainMenuController: NSObject, NSMenuItemValidation {
    private weak var owner: AppController?
    private weak var globalShortcutItem: NSMenuItem?

    init(owner: AppController) {
        self.owner = owner
        super.init()
    }

    func install() {
        let mainMenu = NSMenu(title: "Main Menu")

        let applicationMenu = NSMenu(title: "CornerFloat")
        applicationMenu.addItem(item("About CornerFloat", action: #selector(showAbout), key: ""))
        if owner?.hasConfiguredUpdateChannel == true {
            applicationMenu.addItem(item("Check for Updates…", action: #selector(checkForUpdates), key: ""))
        }
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(item("Settings…", action: #selector(showSettings), key: ","))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(item("Show Welcome", action: #selector(showWelcome), key: ""))
        if owner?.canManagePasskeyAccess == true {
            applicationMenu.addItem(item(
                "Enable or Review Passkey Access…",
                action: #selector(enableOrReviewPasskeyAccess),
                key: ""
            ))
        }
        applicationMenu.addItem(item("Privacy Policy", action: #selector(showPrivacy), key: ""))
        applicationMenu.addItem(item("CornerFloat Support", action: #selector(showSupport), key: ""))
        applicationMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        applicationMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        applicationMenu.addItem(.separator())
        applicationMenu.addItem(item("Hide CornerFloat", action: #selector(hideApplication), key: "h"))
        applicationMenu.addItem(item(
            "Hide Others",
            action: #selector(hideOtherApplications),
            key: "h",
            modifiers: [.command, .option]
        ))
        applicationMenu.addItem(item("Show All", action: #selector(showAllApplications), key: ""))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(item("Quit CornerFloat", action: #selector(quit), key: "q"))
        addTopLevelMenu(applicationMenu, to: mainMenu)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("New ChatGPT Panel", action: #selector(openChatGPT), key: "n"))
        fileMenu.addItem(item(
            "Open Web Page…",
            action: #selector(openWebPage),
            key: "n",
            modifiers: [.command, .shift]
        ))
        fileMenu.addItem(item("Manage Quick Sites…", action: #selector(showQuickSites), key: ""))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("New Tab", action: #selector(newTab), key: "t"))
        fileMenu.addItem(item("Close Tab", action: #selector(closeTab), key: "w"))
        fileMenu.addItem(item(
            "Close Panel",
            action: #selector(closeCurrentPanel),
            key: "w",
            modifiers: [.command, .shift]
        ))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Add Current Page to Favorites", action: #selector(bookmarkCurrentPage), key: "d"))
        fileMenu.addItem(item(
            "Save Current Workspace…",
            action: #selector(saveCurrentWorkspace),
            key: "s",
            modifiers: [.command, .option]
        ))
        addTopLevelMenu(fileMenu, to: mainMenu)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(responderItem("Undo", selector: Selector(("undo:")), key: "z"))
        editMenu.addItem(responderItem(
            "Redo",
            selector: Selector(("redo:")),
            key: "z",
            modifiers: [.command, .shift]
        ))
        editMenu.addItem(.separator())
        editMenu.addItem(responderItem("Cut", selector: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(responderItem("Copy", selector: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(responderItem("Paste", selector: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(responderItem("Select All", selector: #selector(NSText.selectAll(_:)), key: "a"))
        addTopLevelMenu(editMenu, to: mainMenu)

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(item("Focus Address Bar", action: #selector(focusAddress), key: "l"))
        viewMenu.addItem(item("Reload", action: #selector(reloadPage), key: "r"))
        viewMenu.addItem(item("Back", action: #selector(goBack), key: "["))
        viewMenu.addItem(item("Forward", action: #selector(goForward), key: "]"))
        viewMenu.addItem(.separator())
        let globalShortcutItem = item(
            "Show or Hide All Panels",
            action: #selector(toggleAllPanels),
            key: " ",
            modifiers: owner?.globalShortcutMenuModifiers ?? [.command, .shift]
        )
        viewMenu.addItem(globalShortcutItem)
        self.globalShortcutItem = globalShortcutItem
        let edgeItem = item("Edge Auto-Hide", action: #selector(toggleEdgeAutoHide), key: "")
        edgeItem.state = owner?.isEdgeAutoHideEnabled == true ? .on : .off
        viewMenu.addItem(edgeItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(item(
            "Make Panel Smaller",
            action: #selector(shrinkPanel),
            key: "-",
            modifiers: [.command, .option]
        ))
        viewMenu.addItem(item(
            "Restore Standard Size",
            action: #selector(resetPanelSize),
            key: "0",
            modifiers: [.command, .option]
        ))
        viewMenu.addItem(item(
            "Make Panel Larger",
            action: #selector(expandPanel),
            key: "+",
            modifiers: [.command, .option]
        ))
        addTopLevelMenu(viewMenu, to: mainMenu)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item(
            "Windows & Library…",
            action: #selector(showLibraryManager),
            key: "m",
            modifiers: [.command, .shift]
        ))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Move to Bottom Right", action: #selector(moveToBottomRight), key: ""))
        windowMenu.addItem(item("Minimize", action: #selector(minimizePanel), key: "m"))
        addTopLevelMenu(windowMenu, to: mainMenu)
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(item("CornerFloat Support", action: #selector(showSupport), key: "?"))
        helpMenu.addItem(item("Privacy Policy", action: #selector(showPrivacy), key: ""))
        helpMenu.addItem(item("Show Welcome", action: #selector(showWelcome), key: ""))
        addTopLevelMenu(helpMenu, to: mainMenu)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    func refreshGlobalShortcut() {
        globalShortcutItem?.keyEquivalentModifierMask = owner?.globalShortcutMenuModifiers
            ?? [.command, .shift]
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let owner else { return false }
        if menuItem.action == #selector(toggleEdgeAutoHide) {
            menuItem.state = owner.isEdgeAutoHideEnabled ? .on : .off
        }
        if menuItem.action == #selector(toggleAllPanels) {
            menuItem.keyEquivalentModifierMask = owner.globalShortcutMenuModifiers
        }
        switch menuItem.action {
        case #selector(focusAddress), #selector(reloadPage), #selector(goBack),
             #selector(goForward), #selector(closeTab):
            return owner.activeWebPanel != nil
        case #selector(closeCurrentPanel), #selector(shrinkPanel), #selector(resetPanelSize),
             #selector(expandPanel), #selector(moveToBottomRight), #selector(minimizePanel):
            return owner.activePanel != nil
        case #selector(bookmarkCurrentPage):
            return owner.canBookmarkActivePage
        default:
            return true
        }
    }

    private func addTopLevelMenu(_ submenu: NSMenu, to mainMenu: NSMenu) {
        let rootItem = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        rootItem.submenu = submenu
        mainMenu.addItem(rootItem)
    }

    private func item(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func responderItem(
        _ title: String,
        selector: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = nil
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc private func showAbout() { owner?.showAbout() }
    @objc private func checkForUpdates() { owner?.checkForUpdates() }
    @objc private func showSettings() { owner?.showSettings() }
    @objc private func showWelcome() { owner?.showWelcome() }
    @objc private func enableOrReviewPasskeyAccess() { owner?.enableOrReviewPasskeyAccess() }
    @objc private func showPrivacy() { owner?.showPrivacyPolicy() }
    @objc private func showSupport() { owner?.showSupport() }
    @objc private func openChatGPT() { owner?.openChatGPTPanel() }
    @objc private func openWebPage() { owner?.promptForWebPage() }
    @objc private func newTab() { owner?.openNewTabInActivePanel() }
    @objc private func closeTab() { owner?.closeCurrentTab() }
    @objc private func bookmarkCurrentPage() { owner?.bookmarkActivePage() }
    @objc private func saveCurrentWorkspace() { owner?.promptToSaveCurrentWorkspace() }
    @objc private func showLibraryManager() { owner?.showLibraryManager() }
    @objc private func showQuickSites() { owner?.showLibraryManager(section: .shortcuts) }
    @objc private func closeCurrentPanel() { owner?.closeActivePanel() }
    @objc private func toggleAllPanels() { owner?.toggleAllPanelsVisibility() }
    @objc private func toggleEdgeAutoHide() { owner?.toggleEdgeAutoHide() }
    @objc private func hideApplication() { NSApp.hide(nil) }
    @objc private func hideOtherApplications() { NSApp.hideOtherApplications(nil) }
    @objc private func showAllApplications() { NSApp.unhideAllApplications(nil) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func focusAddress() { owner?.activeWebPanel?.focusAddressField() }
    @objc private func reloadPage() { owner?.activeWebPanel?.reloadCurrentPage() }
    @objc private func goBack() { owner?.activeWebPanel?.navigateBack() }
    @objc private func goForward() { owner?.activeWebPanel?.navigateForward() }
    @objc private func shrinkPanel() { owner?.shrinkActivePanel() }
    @objc private func resetPanelSize() { owner?.resetActivePanelSize() }
    @objc private func expandPanel() { owner?.expandActivePanel() }
    @objc private func moveToBottomRight() { owner?.moveActivePanelToBottomRight() }
    @objc private func minimizePanel() { owner?.minimizeActivePanel() }
}
