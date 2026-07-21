import AppKit

enum CornerFloatManagerSection: Int, CaseIterable {
    case panels
    case bookmarks
    case shortcuts
    case recents
    case workspaces

    var title: String {
        switch self {
        case .panels: return CFL10n.text("窗口", "Windows")
        case .bookmarks: return CFL10n.text("收藏", "Favorites")
        case .shortcuts: return CFL10n.text("快捷网站", "Quick Sites")
        case .recents: return CFL10n.text("最近访问", "Recent")
        case .workspaces: return CFL10n.text("工作区", "Workspaces")
        }
    }

    var detail: String {
        switch self {
        case .panels:
            return CFL10n.text("集中显示、隐藏和关闭当前悬浮窗口", "Show, hide, and close floating windows in one place")
        case .bookmarks:
            return CFL10n.text("保存常用网页，一次点击重新打开", "Keep useful pages ready to open in one click")
        case .shortcuts:
            return CFL10n.text("为任意网站设置可在地址栏输入的快捷词", "Open any site by typing your own shortcut words in the address bar")
        case .recents:
            return CFL10n.text("最近打开或访问过的网页", "Pages you opened or visited recently")
        case .workspaces:
            return CFL10n.text("保存并恢复网页窗口与标签页布局", "Save and restore web windows and tab layouts")
        }
    }

    var symbol: String {
        switch self {
        case .panels: return "rectangle.3.group"
        case .bookmarks: return "star"
        case .shortcuts: return "bolt"
        case .recents: return "clock.arrow.circlepath"
        case .workspaces: return "square.grid.2x2"
        }
    }
}

/// Keeps destructive Manager copy and policy independent from AppKit controls.
/// The UI always presents Cancel as the default button; callers only receive a
/// destructive result after the user explicitly chooses the second button.
enum CornerFloatDestructiveAction: Equatable {
    struct Confirmation: Equatable {
        let title: String
        let message: String
        let destructiveButtonTitle: String
    }

    case replaceCurrentWindows(
        workspaceName: String,
        currentWindowCount: Int,
        replacementWindowCount: Int
    )
    case closePanel(name: String)
    case removeFavorite(title: String)
    case removeQuickSite(name: String)
    case removeRecent(title: String)
    case deleteWorkspace(name: String, windowCount: Int)
    case closeAllPanels(windowCount: Int)
    case clearRecents(count: Int)

    var confirmation: Confirmation {
        switch self {
        case let .replaceCurrentWindows(workspaceName, currentWindowCount, replacementWindowCount):
            let currentWindowDescription = Self.count(
                currentWindowCount,
                chineseUnit: "个窗口",
                singular: "window",
                plural: "windows"
            )
            let replacementWindowDescription = Self.count(
                replacementWindowCount,
                chineseUnit: "个窗口",
                singular: "window",
                plural: "windows"
            )
            return Confirmation(
                title: CFL10n.text("替换当前窗口？", "Replace Current Windows?"),
                message: CFL10n.text(
                    "这会关闭当前的 \(currentWindowDescription)，包括其中的标签页和未提交的表单内容，然后打开“\(workspaceName)”中的 \(replacementWindowDescription)。未保存的网页状态无法恢复。",
                    "This closes \(currentWindowDescription), including all tabs and any unsaved form input, then opens \(replacementWindowDescription) from “\(workspaceName)”. Unsaved page state cannot be restored."
                ),
                destructiveButtonTitle: CFL10n.text("替换窗口", "Replace Windows")
            )
        case let .closePanel(name):
            return Confirmation(
                title: CFL10n.text("关闭“\(name)”？", "Close “\(name)”?"),
                message: CFL10n.text(
                    "这会关闭此窗口及其所有标签页。未提交的表单内容和正在进行的下载可能会丢失；CornerFloat 本身仍会继续运行。",
                    "This closes the panel and all of its tabs. Unsaved form input and active downloads may be lost; CornerFloat itself will keep running."
                ),
                destructiveButtonTitle: CFL10n.text("关闭窗口", "Close Panel")
            )
        case let .removeFavorite(title):
            return Confirmation(
                title: CFL10n.text("移除收藏“\(title)”？", "Remove “\(title)” from Favorites?"),
                message: CFL10n.text(
                    "这会从本地资料库中移除此收藏。已打开的标签页、网站会话和 Cookie 不会改变。",
                    "This removes the saved favorite from the local library. Open tabs, website sessions, and cookies are not changed."
                ),
                destructiveButtonTitle: CFL10n.text("移除收藏", "Remove Favorite")
            )
        case let .removeQuickSite(name):
            return Confirmation(
                title: CFL10n.text("移除快捷网站“\(name)”？", "Remove Quick Site “\(name)”?"),
                message: CFL10n.text(
                    "这会删除此快捷网站及其地址栏快捷词。目标网站和已打开的标签页不会改变。",
                    "This deletes the quick site and its address-bar aliases. The destination website and open tabs are not changed."
                ),
                destructiveButtonTitle: CFL10n.text("移除快捷网站", "Remove Quick Site")
            )
        case let .removeRecent(title):
            return Confirmation(
                title: CFL10n.text("移除最近访问“\(title)”？", "Remove Recent Destination “\(title)”?"),
                message: CFL10n.text(
                    "这只会移除此条最近访问记录。收藏、Cookie、网站会话和已打开的标签页不会改变。",
                    "This removes only this recent-history entry. Favorites, cookies, website sessions, and open tabs are not changed."
                ),
                destructiveButtonTitle: CFL10n.text("移除记录", "Remove Recent")
            )
        case let .deleteWorkspace(name, windowCount):
            let windowDescription = Self.count(
                windowCount,
                chineseUnit: "个窗口",
                singular: "window",
                plural: "windows"
            )
            return Confirmation(
                title: CFL10n.text("删除工作区“\(name)”？", "Delete Workspace “\(name)”?"),
                message: CFL10n.text(
                    "这会永久删除包含 \(windowDescription) 的已保存布局。当前打开的窗口不会关闭，但删除操作无法撤销。",
                    "This permanently deletes the saved layout for \(windowDescription). Currently open windows stay open, but this deletion cannot be undone."
                ),
                destructiveButtonTitle: CFL10n.text("删除工作区", "Delete Workspace")
            )
        case let .closeAllPanels(windowCount):
            let windowDescription = Self.count(
                windowCount,
                chineseUnit: "个窗口",
                singular: "window",
                plural: "windows"
            )
            return Confirmation(
                title: CFL10n.text("关闭全部悬浮窗口？", "Close All Floating Windows?"),
                message: CFL10n.text(
                    "这会关闭当前的 \(windowDescription)，包括其中的全部标签页。未提交的表单内容和正在进行的下载可能会丢失；CornerFloat 本身仍会继续运行。",
                    "This closes all \(windowDescription) and their tabs. Unsaved form input and active downloads may be lost; CornerFloat itself will keep running."
                ),
                destructiveButtonTitle: CFL10n.text("关闭全部窗口", "Close All Windows")
            )
        case let .clearRecents(count):
            let entryDescription = Self.count(
                count,
                chineseUnit: "条记录",
                singular: "entry",
                plural: "entries"
            )
            return Confirmation(
                title: CFL10n.text("清除最近访问记录？", "Clear Recent Destinations?"),
                message: CFL10n.text(
                    "这会永久移除 \(entryDescription)。收藏、快捷网站、Cookie、网站会话和已打开的标签页不会改变。",
                    "This permanently removes \(entryDescription). Favorites, Quick Sites, cookies, website sessions, and open tabs are not changed."
                ),
                destructiveButtonTitle: CFL10n.text("清除记录", "Clear Recents")
            )
        }
    }

    private static func count(
        _ value: Int,
        chineseUnit: String,
        singular: String,
        plural: String
    ) -> String {
        if CFL10n.usesChinese {
            return "\(value) \(chineseUnit)"
        }
        return "\(value) \(value == 1 ? singular : plural)"
    }
}

/// One confirmation path is shared by the Manager and menu-bar bulk actions so
/// a higher-risk shortcut cannot bypass the safer local-library policy.
@MainActor
func confirmDestructiveAction(_ action: CornerFloatDestructiveAction) -> Bool {
    let presentation = action.confirmation
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = presentation.title
    alert.informativeText = presentation.message

    // Cancel is intentionally first so Return takes the safe path. The
    // destructive choice still uses the system destructive-button style.
    alert.addButton(withTitle: CFL10n.text("取消", "Cancel"))
    alert.addButton(withTitle: presentation.destructiveButtonTitle)
    alert.buttons.first?.keyEquivalent = "\r"
    alert.buttons.last?.hasDestructiveAction = true
    return alert.runModal() == .alertSecondButtonReturn
}

@MainActor
final class WorkspaceLibraryController: NSObject, NSWindowDelegate, NSTableViewDataSource,
    NSTableViewDelegate {
    private weak var owner: AppController?
    private var window: NSWindow?
    private let sidebarTable = NSTableView()
    private let contentTable = NSTableView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let contextActionButton = NSButton()
    private let primaryButton = NSButton()
    private let secondaryButton = NSButton()
    private let deleteButton = NSButton()
    private var section: CornerFloatManagerSection = .panels
    private var isReloading = false

    init(owner: AppController) {
        self.owner = owner
        super.init()
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(section requestedSection: CornerFloatManagerSection? = nil) {
        if let requestedSection {
            section = requestedSection
        }
        if window == nil {
            buildWindow()
        }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() {
        guard window != nil else { return }
        guard !isReloading else { return }
        isReloading = true
        defer { isReloading = false }

        sidebarTable.reloadData()
        sidebarTable.selectRowIndexes(IndexSet(integer: section.rawValue), byExtendingSelection: false)

        let selected = contentTable.selectedRow
        contentTable.reloadData()
        if selected >= 0, selected < rowCount {
            contentTable.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        } else {
            contentTable.deselectAll(nil)
        }

        titleLabel.stringValue = section.title
        detailLabel.stringValue = section.detail
        emptyLabel.stringValue = emptyMessage
        emptyLabel.isHidden = rowCount != 0
        contextActionButton.isHidden = section != .workspaces && section != .shortcuts
        contextActionButton.title = section == .shortcuts
            ? CFL10n.text("添加快捷网站…", "Add Quick Site…")
            : CFL10n.text("保存当前工作区…", "Save Current Workspace…")
        contextActionButton.image = NSImage(
            systemSymbolName: section == .shortcuts ? "plus" : "plus.square.on.square",
            accessibilityDescription: nil
        )
        contextActionButton.imagePosition = .imageLeading
        updateButtons()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = CFL10n.text("CornerFloat 管理中心", "CornerFloat Manager")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 420)
        window.setFrameAutosaveName("CornerFloat.LibraryManager")
        window.delegate = self

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)

        let sidebarHeading = NSTextField(labelWithString: CFL10n.text("资料库", "LIBRARY"))
        sidebarHeading.font = .systemFont(ofSize: 11, weight: .semibold)
        sidebarHeading.textColor = .secondaryLabelColor
        sidebarHeading.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarHeading)

        configureTable(sidebarTable, rowHeight: 44)
        let sidebarColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        sidebarColumn.resizingMask = .autoresizingMask
        sidebarTable.addTableColumn(sidebarColumn)
        let sidebarScroll = NSScrollView()
        sidebarScroll.documentView = sidebarTable
        sidebarScroll.drawsBackground = false
        sidebarScroll.hasVerticalScroller = false
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarScroll)

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(detailLabel)

        configureButton(
            contextActionButton,
            title: "",
            symbol: "plus.square.on.square",
            action: #selector(performContextAction)
        )
        contextActionButton.bezelStyle = .rounded
        contextActionButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(contextActionButton)

        configureTable(contentTable, rowHeight: 58)
        contentTable.doubleAction = #selector(performPrimaryAction)
        let contentColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content"))
        contentColumn.resizingMask = .autoresizingMask
        contentTable.addTableColumn(contentColumn)
        let contentScroll = NSScrollView()
        contentScroll.documentView = contentTable
        contentScroll.drawsBackground = false
        contentScroll.hasVerticalScroller = true
        contentScroll.autohidesScrollers = true
        contentScroll.borderType = .bezelBorder
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(contentScroll)

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.maximumNumberOfLines = 3
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyLabel)

        configureButton(primaryButton, title: "", symbol: nil, action: #selector(performPrimaryAction))
        primaryButton.keyEquivalent = "\r"
        primaryButton.bezelStyle = .rounded
        configureButton(secondaryButton, title: "", symbol: nil, action: #selector(performSecondaryAction))
        secondaryButton.bezelStyle = .rounded
        configureButton(deleteButton, title: "", symbol: "trash", action: #selector(performDeleteAction))
        deleteButton.bezelStyle = .rounded
        deleteButton.contentTintColor = .systemRed

        let buttonStack = NSStackView(views: [deleteButton, NSView(), secondaryButton, primaryButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.setHuggingPriority(.defaultLow, for: .horizontal)
        content.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 190),

            sidebarHeading.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            sidebarHeading.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 18),
            sidebarScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            sidebarScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            sidebarScroll.topAnchor.constraint(equalTo: sidebarHeading.bottomAnchor, constant: 8),
            sidebarScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12),

            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contextActionButton.leadingAnchor, constant: -12),
            contextActionButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            contextActionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),

            contentScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            contentScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            contentScroll.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 18),
            contentScroll.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -14),

            emptyLabel.centerXAnchor.constraint(equalTo: contentScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentScroll.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),

            buttonStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            buttonStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            buttonStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            buttonStack.heightAnchor.constraint(equalToConstant: 30)
        ])

        self.window = window
    }

    private func configureTable(_ table: NSTableView, rowHeight: CGFloat) {
        table.headerView = nil
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.usesAlternatingRowBackgroundColors = false
        table.delegate = self
        table.dataSource = self
    }

    private func configureButton(_ button: NSButton, title: String, symbol: String?, action: Selector) {
        button.title = title
        button.target = self
        button.action = action
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === sidebarTable { return CornerFloatManagerSection.allCases.count }
        return rowCount
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sidebarTable {
            let item = CornerFloatManagerSection.allCases[row]
            let cell = ManagerSidebarCell()
            cell.configure(title: item.title, symbol: item.symbol)
            return cell
        }

        let cell = ManagerContentCell()
        let values = rowValues(at: row)
        cell.configure(title: values.title, detail: values.detail, symbol: values.symbol)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading else { return }
        if notification.object as? NSTableView === sidebarTable {
            let selected = sidebarTable.selectedRow
            guard let newSection = CornerFloatManagerSection(rawValue: selected) else { return }
            guard newSection != section else { return }
            section = newSection
            contentTable.deselectAll(nil)
            reload()
        } else {
            updateButtons()
        }
    }

    @objc private func performContextAction() {
        switch section {
        case .shortcuts:
            owner?.promptToAddQuickSite()
        case .workspaces:
            owner?.promptToSaveCurrentWorkspace()
        default:
            break
        }
    }

    @objc private func performPrimaryAction() {
        guard let owner, contentTable.selectedRow >= 0 else { return }
        let row = contentTable.selectedRow
        switch section {
        case .panels:
            guard row < owner.panels.count else { return }
            owner.panels[row].show()
        case .bookmarks:
            guard row < owner.bookmarks.count else { return }
            owner.openBookmark(id: owner.bookmarks[row].id)
        case .shortcuts:
            guard row < owner.quickSites.count else { return }
            owner.openQuickSite(id: owner.quickSites[row].id)
        case .recents:
            guard row < owner.recentDestinations.count else { return }
            owner.openRecentDestination(id: owner.recentDestinations[row].id)
        case .workspaces:
            guard row < owner.savedWorkspaces.count else { return }
            owner.restoreWorkspace(id: owner.savedWorkspaces[row].id, replacingCurrentPanels: false)
        }
        reload()
    }

    @objc private func performSecondaryAction() {
        guard let owner, contentTable.selectedRow >= 0 else { return }
        let row = contentTable.selectedRow
        switch section {
        case .panels:
            guard row < owner.panels.count else { return }
            owner.panels[row].hide()
        case .bookmarks:
            owner.bookmarkActivePage()
        case .shortcuts:
            guard row < owner.quickSites.count else { return }
            owner.promptToEditQuickSite(id: owner.quickSites[row].id)
        case .recents:
            guard row < owner.recentDestinations.count else { return }
            owner.bookmarkRecentDestination(id: owner.recentDestinations[row].id)
        case .workspaces:
            guard row < owner.savedWorkspaces.count else { return }
            let workspace = owner.savedWorkspaces[row]
            if !owner.panels.isEmpty {
                let action = CornerFloatDestructiveAction.replaceCurrentWindows(
                    workspaceName: workspace.name,
                    currentWindowCount: owner.panels.count,
                    replacementWindowCount: workspace.panels.count
                )
                guard confirmDestructiveAction(action) else { return }
            }
            owner.restoreWorkspace(id: workspace.id, replacingCurrentPanels: true)
        }
        reload()
    }

    @objc private func performDeleteAction() {
        guard let owner, contentTable.selectedRow >= 0 else { return }
        let row = contentTable.selectedRow
        switch section {
        case .panels:
            guard row < owner.panels.count else { return }
            let panel = owner.panels[row]
            guard confirmDestructiveAction(.closePanel(name: panel.displayName)) else { return }
            panel.close()
        case .bookmarks:
            guard row < owner.bookmarks.count else { return }
            let bookmark = owner.bookmarks[row]
            guard confirmDestructiveAction(.removeFavorite(title: bookmark.title)) else { return }
            owner.removeBookmark(id: bookmark.id)
        case .shortcuts:
            guard row < owner.quickSites.count else { return }
            let shortcut = owner.quickSites[row]
            guard confirmDestructiveAction(.removeQuickSite(name: shortcut.name)) else { return }
            owner.removeQuickSite(id: shortcut.id)
        case .recents:
            guard row < owner.recentDestinations.count else { return }
            let recent = owner.recentDestinations[row]
            guard confirmDestructiveAction(.removeRecent(title: recent.title)) else { return }
            owner.removeRecentDestination(id: recent.id)
        case .workspaces:
            guard row < owner.savedWorkspaces.count else { return }
            let workspace = owner.savedWorkspaces[row]
            guard confirmDestructiveAction(.deleteWorkspace(
                name: workspace.name,
                windowCount: workspace.panels.count
            )) else { return }
            owner.removeWorkspace(id: workspace.id)
        }
        reload()
    }

    private var rowCount: Int {
        guard let owner else { return 0 }
        switch section {
        case .panels: return owner.panels.count
        case .bookmarks: return owner.bookmarks.count
        case .shortcuts: return owner.quickSites.count
        case .recents: return owner.recentDestinations.count
        case .workspaces: return owner.savedWorkspaces.count
        }
    }

    private var emptyMessage: String {
        switch section {
        case .panels:
            return CFL10n.text("还没有悬浮窗口。\n从菜单栏打开一个网页。", "No floating windows yet.\nOpen a web page from the menu bar.")
        case .bookmarks:
            return CFL10n.text("还没有收藏。\n打开网页后使用“收藏当前网页”。", "No favorites yet.\nOpen a page, then choose Add Current Page to Favorites.")
        case .shortcuts:
            return CFL10n.text("还没有快捷网站。\n添加一个名称、快捷词和目标网址。", "No quick sites yet.\nAdd a name, shortcut words, and destination URL.")
        case .recents:
            return CFL10n.text("访问过的网页会显示在这里。", "Pages you visit will appear here.")
        case .workspaces:
            return CFL10n.text("把当前网页窗口保存为可恢复布局。", "Save web windows as a restorable layout.")
        }
    }

    private func rowValues(at row: Int) -> (title: String, detail: String, symbol: String) {
        guard let owner else { return ("", "", "") }
        switch section {
        case .panels:
            let panel = owner.panels[row]
            let visibility = panel.isVisible
                ? CFL10n.text("正在显示", "Visible")
                : CFL10n.text("已隐藏", "Hidden")
            return (panel.displayName, "\(CFL10n.text("网页", "Web")) · \(visibility)", "globe")
        case .bookmarks:
            let bookmark = owner.bookmarks[row]
            return (bookmark.title, shortURL(bookmark.url), "star.fill")
        case .shortcuts:
            let shortcut = owner.quickSites[row]
            return (
                shortcut.name,
                "\(shortcut.aliases.joined(separator: ", ")) · \(shortURL(shortcut.url))",
                "bolt.fill"
            )
        case .recents:
            let recent = owner.recentDestinations[row]
            return (recent.title, "\(shortURL(recent.url)) · \(relativeDate(recent.visitedAt))", "clock")
        case .workspaces:
            let workspace = owner.savedWorkspaces[row]
            let webCount = workspace.panels.count
            let panelSummary = webCount == 1 ? "1 web window" : "\(webCount) web windows"
            let detail = "\(panelSummary) · \(relativeDate(workspace.updatedAt))"
            return (workspace.name, detail, "square.grid.2x2.fill")
        }
    }

    private func updateButtons() {
        let hasSelection = contentTable.selectedRow >= 0 && contentTable.selectedRow < rowCount
        primaryButton.isEnabled = hasSelection
        secondaryButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection

        switch section {
        case .panels:
            primaryButton.title = CFL10n.text("显示并激活", "Show & Focus")
            secondaryButton.title = CFL10n.text("隐藏", "Hide")
            deleteButton.title = CFL10n.text("关闭并移除", "Close & Remove")
        case .bookmarks:
            primaryButton.title = CFL10n.text("打开", "Open")
            secondaryButton.title = CFL10n.text("收藏当前网页", "Favorite Current Page")
            deleteButton.title = CFL10n.text("移除收藏", "Remove Favorite")
            secondaryButton.isEnabled = owner?.canBookmarkActivePage == true
        case .shortcuts:
            primaryButton.title = CFL10n.text("打开", "Open")
            secondaryButton.title = CFL10n.text("编辑…", "Edit…")
            deleteButton.title = CFL10n.text("移除快捷网站", "Remove Quick Site")
        case .recents:
            primaryButton.title = CFL10n.text("再次打开", "Open Again")
            secondaryButton.title = CFL10n.text("加入收藏", "Add to Favorites")
            deleteButton.title = CFL10n.text("移除记录", "Remove")
        case .workspaces:
            primaryButton.title = CFL10n.text("追加打开", "Open Alongside")
            secondaryButton.title = CFL10n.text("替换当前窗口", "Replace Current Windows")
            deleteButton.title = CFL10n.text("删除工作区", "Delete Workspace")
        }
    }

    private func shortURL(_ string: String) -> String {
        guard let url = URL(string: string) else { return string }
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? string
        let path = url.path == "/" ? "" : url.path
        return host + path
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private final class ManagerSidebarCell: NSTableCellView {
    private let symbolView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        addSubview(label)
        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 18),
            symbolView.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(title: String, symbol: String) {
        label.stringValue = title
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        symbolView.contentTintColor = .secondaryLabelColor
    }
}

private final class ManagerContentCell: NSTableCellView {
    private let symbolView = NSImageView()
    private let primaryLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        primaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        primaryLabel.lineBreakMode = .byTruncatingTail
        primaryLabel.translatesAutoresizingMaskIntoConstraints = false
        secondaryLabel.font = .systemFont(ofSize: 11)
        secondaryLabel.textColor = .secondaryLabelColor
        secondaryLabel.lineBreakMode = .byTruncatingMiddle
        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        addSubview(primaryLabel)
        addSubview(secondaryLabel)
        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 22),
            symbolView.heightAnchor.constraint(equalToConstant: 22),
            primaryLabel.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: 11),
            primaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            primaryLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1),
            secondaryLabel.leadingAnchor.constraint(equalTo: primaryLabel.leadingAnchor),
            secondaryLabel.trailingAnchor.constraint(equalTo: primaryLabel.trailingAnchor),
            secondaryLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 2)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(title: String, detail: String, symbol: String) {
        primaryLabel.stringValue = title
        secondaryLabel.stringValue = detail
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        symbolView.contentTintColor = .controlAccentColor
    }
}
