import AppKit
import WebKit

@MainActor
final class BrowserTab {
    let id = UUID()
    let webView: WKWebView
    let containerView = NSView()
    let errorView = BrowserErrorView()
    /// The exact main-frame request WebKit most recently attempted. Keeping the
    /// method and headers matters: a failed sign-in POST must never be silently
    /// converted into a GET when the user presses Try Again.
    var pendingMainFrameRequest: URLRequest?
    var lastCommittedURL: URL?
    var failedRequest: URLRequest?
    var failedURL: URL?
    var displayTitle = "New Tab"

    init(webView: WKWebView) {
        self.webView = webView

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        webView.translatesAutoresizingMaskIntoConstraints = false
        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.isHidden = true
        containerView.addSubview(webView)
        containerView.addSubview(errorView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            errorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            errorView.topAnchor.constraint(equalTo: containerView.topAnchor),
            errorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
}

@MainActor
final class BrowserTabItemView: NSView {
    let tabID: UUID
    var onSelect: ((UUID) -> Void)?
    var onClose: ((UUID) -> Void)?

    private let titleButton = NSButton()
    private let closeButton = NSButton()
    private var currentTitle: String
    private var isSelected = false

    init(tabID: UUID, title: String) {
        self.tabID = tabID
        self.currentTitle = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        setAccessibilityElement(false)

        titleButton.title = title
        titleButton.isBordered = false
        titleButton.alignment = .left
        titleButton.font = .systemFont(ofSize: 12, weight: .medium)
        titleButton.lineBreakMode = .byTruncatingTail
        titleButton.target = self
        titleButton.action = #selector(selectTab)
        titleButton.setAccessibilityLabel("Select tab: \(title)")
        titleButton.setAccessibilityRole(.radioButton)
        titleButton.setAccessibilitySelected(false)
        titleButton.setAccessibilityValue("Not selected")
        titleButton.translatesAutoresizingMaskIntoConstraints = false

        closeButton.title = ""
        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Close tab"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTab)
        closeButton.setAccessibilityLabel("Close tab: \(title)")
        closeButton.toolTip = "Close tab: \(title)"
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleButton)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 116),
            widthAnchor.constraint(lessThanOrEqualToConstant: 210),
            heightAnchor.constraint(equalToConstant: 28),
            titleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleButton.topAnchor.constraint(equalTo: topAnchor),
            titleButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            closeButton.leadingAnchor.constraint(equalTo: titleButton.trailingAnchor, constant: 3),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String) {
        currentTitle = title
        titleButton.title = title
        titleButton.setAccessibilityLabel("Select tab: \(title)")
        closeButton.setAccessibilityLabel("Close tab: \(title)")
        closeButton.toolTip = "Close tab: \(title)"
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        titleButton.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        titleButton.setAccessibilitySelected(selected)
        titleButton.setAccessibilityValue(selected ? "Selected" : "Not selected")
    }

    #if CORNERFLOAT_WEBKIT_INTEGRATION_TESTS
    struct IntegrationAccessibilityState {
        let title: String
        let isSelected: Bool
        let titleButtonLabel: String
        let closeButtonLabel: String
    }

    var integrationAccessibilityState: IntegrationAccessibilityState {
        IntegrationAccessibilityState(
            title: currentTitle,
            isSelected: isSelected,
            titleButtonLabel: titleButton.accessibilityLabel() ?? "",
            closeButtonLabel: closeButton.accessibilityLabel() ?? ""
        )
    }
    #endif

    @objc private func selectTab() {
        onSelect?(tabID)
    }

    @objc private func closeTab() {
        onClose?(tabID)
    }
}

@MainActor
final class BrowserErrorView: NSVisualEffectView {
    var onRetry: (() -> Void)?
    var onOpenExternally: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton(title: "Try Again", target: nil, action: nil)
    private let externalButton = NSButton(title: "Open in Default Browser", target: nil, action: nil)
    private let dismissButton = NSButton(title: "Continue Showing Page", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active

        symbolView.imageScaling = .scaleProportionallyUpOrDown
        symbolView.contentTintColor = .secondaryLabelColor
        symbolView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 6

        retryButton.bezelStyle = .rounded
        retryButton.keyEquivalent = "\r"
        retryButton.target = self
        retryButton.action = #selector(retry)
        externalButton.bezelStyle = .rounded
        externalButton.target = self
        externalButton.action = #selector(openExternally)
        dismissButton.isBordered = false
        dismissButton.contentTintColor = .secondaryLabelColor
        dismissButton.target = self
        dismissButton.action = #selector(dismiss)

        let buttons = NSStackView(views: [retryButton, externalButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let stack = NSStackView(views: [symbolView, titleLabel, messageLabel, buttons, dismissButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 34),
            symbolView.heightAnchor.constraint(equalToConstant: 34),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        title: String,
        message: String,
        symbol: String,
        canRetry: Bool = true,
        canOpenExternally: Bool,
        canDismiss: Bool = false
    ) {
        titleLabel.stringValue = title
        messageLabel.stringValue = message
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        retryButton.isHidden = !canRetry
        externalButton.isHidden = !canOpenExternally
        dismissButton.isHidden = !canDismiss
        setAccessibilityLabel(title)
        setAccessibilityHelp(message)
        isHidden = false
    }

    func hide() {
        isHidden = true
    }

    @objc private func retry() { onRetry?() }
    @objc private func openExternally() { onOpenExternally?() }
    @objc private func dismiss() { onDismiss?() }
}
