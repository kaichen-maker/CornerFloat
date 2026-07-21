import AppKit

#if canImport(Sparkle)
import Sparkle
#endif

/// Owns CornerFloat's secure update channel. Development builds intentionally
/// remain usable without a feed; release builds inject `SUFeedURL` and
/// `SUPublicEDKey` before signing.
@MainActor
final class UpdateController: NSObject {
#if canImport(Sparkle)
    private var standardController: SPUStandardUpdaterController?
#endif

    override init() {
        super.init()
#if canImport(Sparkle)
        if isConfigured {
            standardController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
#endif
    }

    var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed),
              ["https", "file"].contains(url.scheme?.lowercased() ?? ""),
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    var canCheckForUpdates: Bool {
#if canImport(Sparkle)
        standardController?.updater.canCheckForUpdates == true
#else
        false
#endif
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
#if canImport(Sparkle)
        guard let standardController else {
            showUnconfiguredMessage()
            return
        }
        standardController.checkForUpdates(sender)
#else
        showUnconfiguredMessage()
#endif
    }

    private func showUnconfiguredMessage() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update Channel Not Configured"
        alert.informativeText = "This local development build has no signed update feed. Public releases inject an HTTPS feed URL and Sparkle EdDSA public key before Developer ID signing."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
