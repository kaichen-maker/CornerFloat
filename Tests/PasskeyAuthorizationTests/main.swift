import AppKit
import AuthenticationServices
import Foundation

private func fail(_ message: String) -> Never {
    fputs("CornerFloat passkey-authorization test failed: \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fail(message) }
}

@MainActor
private final class FakePasskeyProvider: PasskeyAuthorizationProviding {
    var authorizationStatus: PasskeyAuthorizationStatus
    var requestedStatus: PasskeyAuthorizationStatus
    private(set) var requestCount = 0

    init(
        status: PasskeyAuthorizationStatus,
        requestedStatus: PasskeyAuthorizationStatus = .authorized
    ) {
        authorizationStatus = status
        self.requestedStatus = requestedStatus
    }

    func requestAuthorization() async -> PasskeyAuthorizationStatus {
        requestCount += 1
        authorizationStatus = requestedStatus
        return requestedStatus
    }
}

@MainActor
private final class RecordingPasskeyPresenter: PasskeyAuthorizationNoticePresenting {
    private(set) var notices: [PasskeyAuthorizationNotice] = []

    func presentPasskeyAuthorizationNotice(_ notice: PasskeyAuthorizationNotice) {
        notices.append(notice)
    }
}

@main
private struct PasskeyAuthorizationTestRunner {
    @MainActor
    static func main() async {
        expect(
            SystemPasskeyAuthorizationProvider.status(from: .authorized) == .authorized,
            "authorized system-state mapping"
        )
        expect(
            SystemPasskeyAuthorizationProvider.status(from: .notDetermined) == .notDetermined,
            "not-determined system-state mapping"
        )
        expect(
            SystemPasskeyAuthorizationProvider.status(from: .denied) == .denied,
            "denied system-state mapping"
        )

        let deniedNotice = PasskeyAuthorizationNotice.notice(for: .denied)
        expect(deniedNotice.offersSystemSettings, "denied state must offer System Settings")
        expect(
            deniedNotice.message.contains("Passkeys Access for Web Browsers"),
            "denied guidance must name the macOS setting"
        )
        let restrictedNotice = PasskeyAuthorizationNotice.notice(for: .restricted)
        expect(restrictedNotice.offersSystemSettings, "restricted state must offer System Settings")
        expect(
            restrictedNotice.message.contains("administrator"),
            "restricted guidance must mention managed Macs"
        )

        let undecidedProvider = FakePasskeyProvider(status: .notDetermined)
        let authorizedPresenter = RecordingPasskeyPresenter()
        let coordinator = PasskeyAuthorizationCoordinator(
            provider: undecidedProvider,
            presenter: authorizedPresenter
        )
        expect(undecidedProvider.requestCount == 0, "construction must not request authorization")
        await coordinator.handleExplicitUserAction()
        expect(undecidedProvider.requestCount == 1, "explicit action must request when undetermined")
        expect(
            authorizedPresenter.notices.last?.title == "Passkey Access Ready",
            "authorized result notice"
        )
        await coordinator.handleExplicitUserAction()
        expect(undecidedProvider.requestCount == 1, "authorized state must not request again")

        let deniedProvider = FakePasskeyProvider(status: .denied)
        let deniedPresenter = RecordingPasskeyPresenter()
        let deniedCoordinator = PasskeyAuthorizationCoordinator(
            provider: deniedProvider,
            presenter: deniedPresenter
        )
        await deniedCoordinator.handleExplicitUserAction()
        expect(deniedProvider.requestCount == 0, "denied state must not re-prompt")
        expect(
            deniedPresenter.notices == [deniedNotice],
            "denied state must show actionable guidance"
        )

        print("CornerFloat passkey-authorization tests OK: state mapping, explicit request gating and recovery guidance")
    }
}
