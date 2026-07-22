import AppKit
import WebKit

enum CornerFloatProductPage: Hashable {
    case privacy
    case support

    var title: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .support: return "CornerFloat Support"
        }
    }

    var resourceName: String {
        switch self {
        case .privacy: return "PrivacyPolicy"
        case .support: return "Support"
        }
    }
}

@MainActor
final class ProductPagesController {
    private var controllers: [CornerFloatProductPage: ProductPageWindowController] = [:]

    func show(_ page: CornerFloatProductPage) {
        let controller = controllers[page] ?? ProductPageWindowController(page: page) { [weak self] page in
            self?.show(page)
        }
        controllers[page] = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class ProductPageWindowController: NSWindowController, WKNavigationDelegate {
    private let page: CornerFloatProductPage
    private let webView: WKWebView
    private let openPage: (CornerFloatProductPage) -> Void

    init(page: CornerFloatProductPage, openPage: @escaping (CornerFloatProductPage) -> Void) {
        self.page = page
        self.openPage = openPage

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = page.title
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 520, height: 460)
        window.isReleasedWhenClosed = false
        super.init(window: window)

        webView.navigationDelegate = self
        buildInterface()
        loadPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildInterface() {
        guard let window else { return }
        let root = NSVisualEffectView()
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .active

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setAccessibilityLabel(page.title)
        root.addSubview(webView)

        let closeButton = NSButton(title: "Done", target: self, action: #selector(closePage))
        closeButton.keyEquivalent = "\r"
        closeButton.bezelStyle = .rounded

        let secondaryButton: NSButton
        switch page {
        case .privacy:
            secondaryButton = NSButton(
                title: "Open Support",
                target: self,
                action: #selector(openOtherPage)
            )
        case .support:
            secondaryButton = NSButton(
                title: "Copy Diagnostics",
                target: self,
                action: #selector(copyDiagnostics)
            )
        }
        secondaryButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [secondaryButton, closeButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(buttons)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: root.topAnchor),
            webView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            buttons.heightAnchor.constraint(greaterThanOrEqualToConstant: 28)
        ])
        window.contentView = root
    }

    private func loadPage() {
        guard let url = Bundle.main.url(
            forResource: page.resourceName,
            withExtension: "html"
        ) else {
            webView.loadHTMLString(
                "<main style='font: 15px -apple-system; padding: 40px'><h1>Page unavailable</h1><p>The packaged resource could not be found.</p></main>",
                baseURL: nil
            )
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping WebKitCallback1<WKNavigationActionPolicy>
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    @objc private func closePage() {
        close()
    }

    @objc private func openOtherPage() {
        guard page == .privacy else { return }
        openPage(.support)
    }

    @objc private func copyDiagnostics(_ sender: NSButton) {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
#if arch(arm64)
        let architecture = "Apple Silicon (arm64)"
#elseif arch(x86_64)
        let architecture = "Intel (x86_64)"
#else
        let architecture = "Unknown architecture"
#endif
        let diagnostics = """
        CornerFloat \(version) (\(build))
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        \(architecture)
        Locale: \(Locale.current.identifier)
        Preferred languages: \(Locale.preferredLanguages.joined(separator: ", "))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        sender.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak sender] in
            sender?.title = "Copy Diagnostics"
        }
    }
}

@MainActor
enum OnboardingResult: Equatable {
    case completed
    case dismissed
}

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let completionKey = "hasCompletedOnboarding.v1"

    private struct Page {
        let symbol: String
        let eyebrow: String
        let title: String
        let message: String
        let details: [String]
    }

    private let pages = [
        Page(
            symbol: "rectangle.on.rectangle.angled",
            eyebrow: "WELCOME TO CORNERFLOAT",
            title: "Your work, one glance away",
            message: "Keep interactive websites above your workspace without turning them into a separate desktop.",
            details: [
                "Open ChatGPT, mail, docs, or any website in a compact floating panel.",
                "Create Quick Sites for your own address-bar words, then resize, move, and save layouts."
            ]
        ),
        Page(
            symbol: "command.circle.fill",
            eyebrow: "AVAILABLE EVERYWHERE",
            title: "Show or hide instantly",
            message: "Press Shift–Command–Space from any app to show or hide every CornerFloat panel.",
            details: [
                "The shortcut is registered by macOS and needs no Accessibility permission.",
                "Optional edge auto-hide keeps panels out of the way until your pointer returns."
            ]
        ),
        Page(
            symbol: "hand.raised.fill",
            eyebrow: "PRIVATE BY DEFAULT",
            title: "Your workspace stays yours",
            message: "Ordinary web browsing needs no special macOS privacy permission, and CornerFloat has no account or analytics service.",
            details: [
                "Quick Sites, favorites, recents, and saved workspaces remain in your macOS user account; WebKit manages website sessions locally.",
                "An HTTPS site may ask for microphone access, normally after you start voice or dictation. CornerFloat never auto-approves it, keeps camera access blocked, and does not store or upload audio.",
                "The red window button closes a panel but leaves CornerFloat in the menu bar; press Command–Q to quit the app."
            ]
        )
    ]

    var onFinish: ((OnboardingResult) -> Void)?

    private let symbolView = NSImageView()
    private let eyebrowLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let detailsStack = NSStackView()
    private let pageControl = NSSegmentedControl()
    private let backButton = NSButton()
    private let continueButton = NSButton()
    private var pageIndex = 0
    private var didFinish = false
    private var pendingResult: OnboardingResult?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 570),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to CornerFloat"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildInterface()
        renderPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func begin() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildInterface() {
        guard let window else { return }
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active

        let cardContent = NSView()
        cardContent.translatesAutoresizingMaskIntoConstraints = false
        let card = GlassSurfaceView(contentView: cardContent, cornerRadius: 24)
        card.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(card)

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.imageScaling = .scaleProportionallyUpOrDown
        symbolView.contentTintColor = .controlAccentColor
        eyebrowLabel.font = .systemFont(ofSize: 11, weight: .bold)
        eyebrowLabel.textColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.maximumNumberOfLines = 2
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 4

        detailsStack.orientation = .vertical
        detailsStack.alignment = .leading
        detailsStack.spacing = 10

        backButton.title = "Back"
        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(goBack)
        continueButton.title = "Continue"
        continueButton.bezelStyle = .rounded
        continueButton.keyEquivalent = "\r"
        continueButton.target = self
        continueButton.action = #selector(advance)

        pageControl.segmentCount = pages.count
        pageControl.segmentStyle = .texturedRounded
        pageControl.trackingMode = .selectOne
        pageControl.isEnabled = false
        for index in pages.indices {
            pageControl.setLabel("", forSegment: index)
            pageControl.setWidth(24, forSegment: index)
        }

        let navigation = NSStackView(views: [backButton, pageControl, continueButton])
        navigation.orientation = .horizontal
        navigation.alignment = .centerY
        navigation.distribution = .gravityAreas

        let content = NSStackView(views: [
            symbolView,
            eyebrowLabel,
            titleLabel,
            messageLabel,
            detailsStack,
            navigation
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        cardContent.addSubview(content)

        navigation.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 38),
            card.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -38),
            card.topAnchor.constraint(equalTo: background.topAnchor, constant: 48),
            card.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -38),
            symbolView.widthAnchor.constraint(equalToConstant: 58),
            symbolView.heightAnchor.constraint(equalToConstant: 58),
            content.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 34),
            content.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -34),
            content.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 32),
            content.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor, constant: -28)
        ])
        window.contentView = background
    }

    private func renderPage() {
        let page = pages[pageIndex]
        symbolView.image = NSImage(
            systemSymbolName: page.symbol,
            accessibilityDescription: page.title
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 46, weight: .medium))
        eyebrowLabel.stringValue = page.eyebrow
        titleLabel.stringValue = page.title
        messageLabel.stringValue = page.message
        detailsStack.arrangedSubviews.forEach {
            detailsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for detail in page.details {
            let label = NSTextField(wrappingLabelWithString: "•  \(detail)")
            label.font = .systemFont(ofSize: 13)
            label.textColor = .labelColor
            label.maximumNumberOfLines = 3
            detailsStack.addArrangedSubview(label)
        }
        pageControl.selectedSegment = pageIndex
        backButton.isHidden = pageIndex == 0
        continueButton.title = pageIndex == pages.count - 1 ? "Start Using CornerFloat" : "Continue"
        continueButton.setAccessibilityLabel(continueButton.title)
    }

    @objc private func goBack() {
        guard pageIndex > 0 else { return }
        pageIndex -= 1
        renderPage()
    }

    @objc private func advance() {
        if pageIndex < pages.count - 1 {
            pageIndex += 1
            renderPage()
        } else {
            pendingResult = .completed
            window?.performClose(nil)
        }
    }

    private func markFinished(with result: OnboardingResult) {
        guard !didFinish else { return }
        didFinish = true
        UserDefaults.standard.set(true, forKey: Self.completionKey)
        onFinish?(result)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        markFinished(with: pendingResult ?? .dismissed)
        pendingResult = nil
        return true
    }

    /// Drives the same final primary action used by the onboarding CTA while
    /// keeping the AppKit acceptance test independent from private view details.
    func completeForAcceptanceTesting() {
        pageIndex = pages.count - 1
        renderPage()
        advance()
    }

}
