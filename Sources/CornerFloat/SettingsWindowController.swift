import AppKit

struct SettingsPresentationState: Equatable {
    let opensChatGPTOnLaunch: Bool
    let edgeAutoHideEnabled: Bool
    let shortcutDisplayName: String
    let shortcutRegistered: Bool
    let shortcutDetail: String
    let shortcutPresetRawValue: String
    let launchAtLoginState: LaunchAtLoginState
    let launchAtLoginDetail: String
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var appController: AppController?
    private let openOnLaunchButton = NSButton()
    private let edgeAutoHideButton = NSButton()
    private let shortcutPopUp = NSPopUpButton()
    private let shortcutSymbolView = NSImageView()
    private let shortcutValueLabel = NSTextField(labelWithString: "")
    private let shortcutDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let launchAtLoginButton = NSButton()
    private let launchAtLoginDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let openLoginItemsButton = NSButton()
    private var presentedShortcutRegistered = false

    init(owner: AppController) {
        appController = owner

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 610),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CornerFloat Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CornerFloat.Settings")
        window.center()
        super.init(window: window)
        window.delegate = self

        buildInterface()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    var presentationState: SettingsPresentationState {
        SettingsPresentationState(
            opensChatGPTOnLaunch: openOnLaunchButton.state == .on,
            edgeAutoHideEnabled: edgeAutoHideButton.state == .on,
            shortcutDisplayName: shortcutValueLabel.stringValue,
            shortcutRegistered: presentedShortcutRegistered,
            shortcutDetail: shortcutDetailLabel.stringValue,
            shortcutPresetRawValue: appController?.globalHotKeyPreset.rawValue ?? "",
            launchAtLoginState: appController?.launchAtLoginPresentation.state ?? .unavailable,
            launchAtLoginDetail: launchAtLoginDetailLabel.stringValue
        )
    }

    func show() {
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reload() {
        guard let appController else { return }
        openOnLaunchButton.state = appController.opensChatGPTOnLaunch ? .on : .off
        edgeAutoHideButton.state = appController.isEdgeAutoHideEnabled ? .on : .off

        if let index = GlobalHotKeyPreset.allCases.firstIndex(of: appController.globalHotKeyPreset) {
            shortcutPopUp.selectItem(at: index)
        }
        presentedShortcutRegistered = appController.isGlobalHotKeyRegistered
        if appController.isGlobalHotKeyRegistered {
            shortcutValueLabel.stringValue = "\(appController.globalShortcutDisplayName) · Active"
            if let configurationError = appController.globalHotKeyError {
                shortcutDetailLabel.stringValue = "The current shortcut remains active. Last change failed: \(configurationError)"
                shortcutSymbolView.image = NSImage(
                    systemSymbolName: "exclamationmark.triangle.fill",
                    accessibilityDescription: "Global shortcut active with warning"
                )
                shortcutSymbolView.contentTintColor = .systemOrange
            } else {
                shortcutDetailLabel.stringValue = "Works from any app without Accessibility or Input Monitoring access."
                shortcutSymbolView.image = NSImage(
                    systemSymbolName: "checkmark.circle.fill",
                    accessibilityDescription: "Global shortcut active"
                )
                shortcutSymbolView.contentTintColor = .systemGreen
            }
        } else {
            shortcutValueLabel.stringValue = "\(appController.globalShortcutDisplayName) · Unavailable"
            shortcutDetailLabel.stringValue = appController.globalHotKeyError
                ?? "Choose another shortcut; this one may already be used by macOS or another app."
            shortcutSymbolView.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "Global shortcut unavailable"
            )
            shortcutSymbolView.contentTintColor = .systemOrange
        }
        shortcutValueLabel.setAccessibilityLabel("Global shortcut \(shortcutValueLabel.stringValue)")
        shortcutDetailLabel.setAccessibilityLabel("Global shortcut status details")

        let launchPresentation = appController.launchAtLoginPresentation
        launchAtLoginButton.state = launchPresentation.isRegistered ? .on : .off
        launchAtLoginButton.isEnabled = launchPresentation.canToggle
        launchAtLoginDetailLabel.stringValue = launchPresentation.detail
        openLoginItemsButton.isHidden = launchPresentation.state != .requiresApproval
    }

    private func buildInterface() {
        guard let window else { return }

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let iconView = NSImageView()
        iconView.image = NSImage(
            systemSymbolName: "rectangle.on.rectangle.circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 34, weight: .medium))
        iconView.contentTintColor = .controlAccentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "CornerFloat Settings")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        let subtitleLabel = NSTextField(
            wrappingLabelWithString: "Control startup, global access, and your local CornerFloat data."
        )
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor

        let headingStack = verticalStack([titleLabel, subtitleLabel], spacing: 4)
        let heading = NSStackView(views: [iconView, headingStack])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 14
        heading.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        openOnLaunchButton.setButtonType(.switch)
        openOnLaunchButton.title = "Open ChatGPT when CornerFloat starts"
        openOnLaunchButton.target = self
        openOnLaunchButton.action = #selector(openOnLaunchDidChange)

        let openOnLaunchHelp = helpLabel(
            "Turn this off to start quietly in the menu bar with no web panel."
        )

        edgeAutoHideButton.setButtonType(.switch)
        edgeAutoHideButton.title = "Enable edge auto-hide for floating panels"
        edgeAutoHideButton.target = self
        edgeAutoHideButton.action = #selector(edgeAutoHideDidChange)

        let edgeAutoHideHelp = helpLabel(
            "Panels docked near the left or right screen edge collapse after the pointer leaves."
        )

        let generalStack = sectionStack(
            title: "General",
            views: [openOnLaunchButton, openOnLaunchHelp, edgeAutoHideButton, edgeAutoHideHelp]
        )
        generalStack.setCustomSpacing(14, after: openOnLaunchHelp)

        shortcutPopUp.removeAllItems()
        for preset in GlobalHotKeyPreset.allCases {
            shortcutPopUp.addItem(withTitle: preset.shortcut.displayName)
        }
        shortcutPopUp.target = self
        shortcutPopUp.action = #selector(shortcutDidChange)
        shortcutPopUp.setAccessibilityLabel("Global shortcut")

        let shortcutChoiceLabel = NSTextField(labelWithString: "Show or hide all panels")
        shortcutChoiceLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let shortcutChoice = NSStackView(views: [shortcutChoiceLabel, NSView(), shortcutPopUp])
        shortcutChoice.orientation = .horizontal
        shortcutChoice.alignment = .centerY
        shortcutChoice.spacing = 8

        shortcutSymbolView.imageScaling = .scaleProportionallyUpOrDown
        shortcutSymbolView.translatesAutoresizingMaskIntoConstraints = false
        shortcutValueLabel.font = .systemFont(ofSize: 13, weight: .medium)
        shortcutDetailLabel.font = .systemFont(ofSize: 12)
        shortcutDetailLabel.textColor = .secondaryLabelColor
        shortcutDetailLabel.maximumNumberOfLines = 3
        shortcutDetailLabel.isSelectable = true
        let shortcutTextStack = verticalStack([shortcutValueLabel, shortcutDetailLabel], spacing: 3)
        let shortcutStatus = NSStackView(views: [shortcutSymbolView, shortcutTextStack])
        shortcutStatus.orientation = .horizontal
        shortcutStatus.alignment = .top
        shortcutStatus.spacing = 10
        let shortcutStack = sectionStack(
            title: "Global Shortcut",
            views: [shortcutChoice, shortcutStatus]
        )

        launchAtLoginButton.setButtonType(.switch)
        launchAtLoginButton.title = "Launch CornerFloat at login"
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(launchAtLoginDidChange)
        launchAtLoginDetailLabel.font = .systemFont(ofSize: 12)
        launchAtLoginDetailLabel.textColor = .secondaryLabelColor
        launchAtLoginDetailLabel.maximumNumberOfLines = 2
        openLoginItemsButton.title = "Open Login Items…"
        openLoginItemsButton.bezelStyle = .rounded
        openLoginItemsButton.target = self
        openLoginItemsButton.action = #selector(openLoginItems)
        let loginDetailRow = NSStackView(views: [launchAtLoginDetailLabel, NSView(), openLoginItemsButton])
        loginDetailRow.orientation = .horizontal
        loginDetailRow.alignment = .centerY
        loginDetailRow.spacing = 10
        let launchStack = sectionStack(
            title: "Login",
            views: [launchAtLoginButton, loginDetailRow]
        )

        let dataHelp = helpLabel(
            "Back up or move favorites, recents, Quick Sites, and saved workspaces. Website cookies and sign-ins stay in WebKit on this Mac."
        )
        dataHelp.maximumNumberOfLines = 2
        let exportButton = NSButton(title: "Export Library…", target: self, action: #selector(exportLibrary))
        let importButton = NSButton(title: "Import Library…", target: self, action: #selector(importLibrary))
        let revealButton = NSButton(title: "Reveal Data", target: self, action: #selector(revealData))
        for button in [exportButton, importButton, revealButton] {
            button.bezelStyle = .rounded
        }
        let dataButtons = NSStackView(views: [exportButton, importButton, revealButton, NSView()])
        dataButtons.orientation = .horizontal
        dataButtons.alignment = .centerY
        dataButtons.spacing = 8
        let dataStack = sectionStack(title: "Local Data", views: [dataHelp, dataButtons])

        let contentStack = verticalStack(
            [generalStack, shortcutStack, launchStack, dataStack],
            spacing: 20
        )
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        for view in [heading, separator, contentStack] {
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 42),
            iconView.heightAnchor.constraint(equalToConstant: 42),
            shortcutSymbolView.widthAnchor.constraint(equalToConstant: 20),
            shortcutSymbolView.heightAnchor.constraint(equalToConstant: 20),

            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            heading.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),

            separator.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            separator.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 18),

            contentStack.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -22),
            shortcutTextStack.widthAnchor.constraint(
                lessThanOrEqualTo: shortcutStack.widthAnchor,
                constant: -30
            )
        ])
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func sectionStack(title: String, views: [NSView]) -> NSStackView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let stack = verticalStack([heading] + views, spacing: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func helpLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func openOnLaunchDidChange() {
        appController?.setOpenChatGPTOnLaunch(openOnLaunchButton.state == .on)
        reload()
    }

    @objc private func edgeAutoHideDidChange() {
        appController?.setEdgeAutoHideEnabled(edgeAutoHideButton.state == .on)
        reload()
    }

    @objc private func shortcutDidChange() {
        let presets = GlobalHotKeyPreset.allCases
        guard shortcutPopUp.indexOfSelectedItem >= 0,
              shortcutPopUp.indexOfSelectedItem < presets.count else { return }
        _ = appController?.setGlobalHotKeyPreset(presets[shortcutPopUp.indexOfSelectedItem])
        reload()
    }

    @objc private func launchAtLoginDidChange() {
        appController?.setLaunchAtLoginEnabled(launchAtLoginButton.state == .on)
        reload()
    }

    @objc private func openLoginItems() {
        appController?.openLoginItemsSettings()
    }

    @objc private func exportLibrary() {
        appController?.exportLibrary()
    }

    @objc private func importLibrary() {
        appController?.importLibrary()
    }

    @objc private func revealData() {
        appController?.revealLibraryData()
    }
}
