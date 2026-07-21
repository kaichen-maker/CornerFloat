import AppKit
import AuthenticationServices

/// CornerFloat's stable view of macOS passkey authorization. `restricted`
/// preserves a safe, actionable fallback for future system states or managed
/// configurations without making the UI depend directly on AuthenticationServices.
enum PasskeyAuthorizationStatus: String, Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

struct PasskeyAuthorizationNotice: Equatable {
    let title: String
    let message: String
    let offersSystemSettings: Bool

    static func notice(for status: PasskeyAuthorizationStatus) -> PasskeyAuthorizationNotice {
        switch status {
        case .authorized:
            return PasskeyAuthorizationNotice(
                title: "Passkey Access Ready",
                message: "CornerFloat is allowed to use passkeys stored in Apple Passwords and compatible credential managers. Continue on a website that supports passkeys.",
                offersSystemSettings: false
            )
        case .notDetermined:
            return PasskeyAuthorizationNotice(
                title: "Passkey Access Was Not Changed",
                message: "macOS has not received a permission choice yet. Choose Enable or Review Passkey Access again when you are ready to respond to the system prompt.",
                offersSystemSettings: false
            )
        case .denied:
            return PasskeyAuthorizationNotice(
                title: "Passkey Access Is Off",
                message: "Open System Settings → Privacy & Security → Passkeys Access for Web Browsers, then enable CornerFloat. Reload the affected sign-in page after changing the setting.",
                offersSystemSettings: true
            )
        case .restricted:
            return PasskeyAuthorizationNotice(
                title: "Passkey Access Is Restricted",
                message: "This Mac cannot grant CornerFloat access to passkeys. Check System Settings → Privacy & Security → Passkeys Access for Web Browsers. If the setting is unavailable, contact the administrator who manages this Mac.",
                offersSystemSettings: true
            )
        }
    }
}

@MainActor
protocol PasskeyAuthorizationProviding: AnyObject {
    var authorizationStatus: PasskeyAuthorizationStatus { get }
    func requestAuthorization() async -> PasskeyAuthorizationStatus
}

@MainActor
protocol PasskeyAuthorizationNoticePresenting: AnyObject {
    func presentPasskeyAuthorizationNotice(_ notice: PasskeyAuthorizationNotice)
}

@MainActor
final class SystemPasskeyAuthorizationProvider: PasskeyAuthorizationProviding {
    private let manager: ASAuthorizationWebBrowserPublicKeyCredentialManager

    init(manager: ASAuthorizationWebBrowserPublicKeyCredentialManager = .init()) {
        self.manager = manager
    }

    var authorizationStatus: PasskeyAuthorizationStatus {
        Self.status(from: manager.authorizationStateForPlatformCredentials)
    }

    func requestAuthorization() async -> PasskeyAuthorizationStatus {
        let state = await manager.requestAuthorizationForPublicKeyCredentials()
        return Self.status(from: state)
    }

    static func status(
        from state: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState
    ) -> PasskeyAuthorizationStatus {
        switch state {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .restricted
        }
    }
}

@MainActor
final class AppKitPasskeyAuthorizationPresenter: PasskeyAuthorizationNoticePresenting {
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_PasskeyAccess"
    )!

    func presentPasskeyAuthorizationNotice(_ notice: PasskeyAuthorizationNotice) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = notice.offersSystemSettings ? .warning : .informational
        alert.messageText = notice.title
        alert.informativeText = notice.message
        if notice.offersSystemSettings {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Not Now")
        } else {
            alert.addButton(withTitle: "OK")
        }

        if alert.runModal() == .alertFirstButtonReturn, notice.offersSystemSettings {
            NSWorkspace.shared.open(Self.settingsURL)
        }
    }
}

/// Coordinates the explicit user action with the system authorization request.
/// Constructing this object only reads state; it never presents a prompt.
@MainActor
final class PasskeyAuthorizationCoordinator {
    private let provider: PasskeyAuthorizationProviding
    private let presenter: PasskeyAuthorizationNoticePresenting
    private(set) var isRequestInFlight = false

    init() {
        provider = SystemPasskeyAuthorizationProvider()
        presenter = AppKitPasskeyAuthorizationPresenter()
    }

    init(
        provider: PasskeyAuthorizationProviding,
        presenter: PasskeyAuthorizationNoticePresenting
    ) {
        self.provider = provider
        self.presenter = presenter
    }

    var authorizationStatus: PasskeyAuthorizationStatus {
        provider.authorizationStatus
    }

    func handleExplicitUserAction() async {
        guard !isRequestInFlight else { return }

        let status: PasskeyAuthorizationStatus
        if provider.authorizationStatus == .notDetermined {
            isRequestInFlight = true
            status = await provider.requestAuthorization()
            isRequestInFlight = false
        } else {
            status = provider.authorizationStatus
        }
        presenter.presentPasskeyAuthorizationNotice(.notice(for: status))
    }
}
