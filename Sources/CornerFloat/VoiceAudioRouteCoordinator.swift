import CoreAudio
import Foundation
import WebKit

/// Coordinates one temporary input route across every floating web panel.
/// The shared coordinator prevents one panel from restoring AirPods input
/// while another panel is still using a website microphone session.
@MainActor
final class VoiceAudioRouteCoordinator {
    private let routeController: any AudioRouteControlling
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var activeCaptureIDs: Set<ObjectIdentifier> = []
    private var pendingCaptureTimeouts: [ObjectIdentifier: DispatchWorkItem] = [:]
    private var ownership = VoiceRouteOwnershipTracker()
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var inputMonitoringAvailable = false

    init(
        routeController: any AudioRouteControlling = CoreAudioRouteController(),
        monitorsSystemInput: Bool = true
    ) {
        self.routeController = routeController
        if monitorsSystemInput {
            installDefaultInputListener()
        } else {
            // Deterministic test controllers drive input-change events directly.
            inputMonitoringAvailable = true
        }
    }

    func register(_ webView: WKWebView) {
        let id = ObjectIdentifier(webView)
        guard observations[id] == nil else { return }

        observations[id] = webView.observe(
            \.microphoneCaptureState,
            options: [.new]
        ) { [weak self, weak webView] _, change in
            guard let self, let webView, let state = change.newValue else { return }
            MainActor.assumeIsolated {
                self.captureStateDidChange(state, webView: webView)
            }
        }
    }

    func unregister(_ webView: WKWebView) {
        let id = ObjectIdentifier(webView)
        observations.removeValue(forKey: id)?.invalidate()
        activeCaptureIDs.remove(id)
        pendingCaptureTimeouts.removeValue(forKey: id)?.cancel()
        restoreIfIdle()
    }

    func assessment() throws -> VoiceRouteAssessment {
        VoiceRouteRiskClassifier.assess(try routeController.snapshot())
    }

    /// The caller reaches this method only after the user explicitly chooses
    /// the recommended button in the native preflight sheet.
    @discardableResult
    func useBuiltInInput(_ deviceID: AudioDeviceID) throws -> AudioDeviceID {
        guard inputMonitoringAvailable else {
            throw VoiceAudioRouteCoordinatorError.inputMonitoringUnavailable
        }
        if let lease = ownership.lease {
            guard lease.temporaryID == deviceID else {
                throw VoiceAudioRouteCoordinatorError.conflictingTemporaryInput
            }
            return lease.previousID
        }

        ownership.beginSwitch(to: deviceID)
        do {
            let previousID = try routeController.setDefaultInput(toBuiltIn: deviceID)
            if previousID != deviceID {
                ownership.completeSwitch(
                    previousID: previousID,
                    temporaryID: deviceID
                )
            } else {
                ownership.cancelSwitch()
            }
            return previousID
        } catch {
            ownership.cancelSwitch()
            throw error
        }
    }

    /// WebKit can show both a macOS permission prompt and a per-site decision.
    /// Keep the temporary route armed while those choices are pending, then
    /// restore it if capture never starts.
    func prepareForCapture(in webView: WKWebView) {
        guard ownership.lease != nil else { return }
        let id = ObjectIdentifier(webView)
        pendingCaptureTimeouts.removeValue(forKey: id)?.cancel()

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCaptureTimeouts.removeValue(forKey: id)
            self.restoreIfIdle()
        }
        pendingCaptureTimeouts[id] = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: timeout)
    }

    func restoreForShutdown() {
        for timeout in pendingCaptureTimeouts.values {
            timeout.cancel()
        }
        pendingCaptureTimeouts.removeAll()
        activeCaptureIDs.removeAll()
        restoreIfIdle()
    }

    private func captureStateDidChange(
        _ state: WKMediaCaptureState,
        webView: WKWebView
    ) {
        let id = ObjectIdentifier(webView)
        switch state {
        case .active, .muted:
            pendingCaptureTimeouts.removeValue(forKey: id)?.cancel()
            activeCaptureIDs.insert(id)
        case .none:
            let wasActive = activeCaptureIDs.remove(id) != nil
            let pending = pendingCaptureTimeouts.removeValue(forKey: id)
            pending?.cancel()
            let wasPending = pending != nil
            if wasActive || wasPending {
                restoreIfIdle()
            }
        @unknown default:
            break
        }
    }

    private func restoreIfIdle() {
        guard activeCaptureIDs.isEmpty,
              pendingCaptureTimeouts.isEmpty,
              let route = ownership.beginRestore() else { return }

        do {
            try routeController.restoreDefaultInput(
                previousID: route.previousID,
                temporaryID: route.temporaryID
            )
            ownership.completeRestore()
        } catch CoreAudioRouteError.defaultInputChangedExternally {
            // The user chose another input while voice mode was active. Their
            // newer choice always wins, so this session no longer owns a route.
            ownership.cancelRestore(relinquish: true)
        } catch {
            // Restoration is best effort. Retain ownership so a later panel
            // teardown gets one more safe opportunity to restore the route.
            ownership.cancelRestore(relinquish: false)
            fputs("CornerFloat could not restore the previous audio input: \(error)\n", stderr)
        }
    }

    private func installDefaultInputListener() {
        var address = Self.defaultInputAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.defaultInputDidChange()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
        guard status == noErr else {
            fputs("CornerFloat could not monitor default audio input changes: \(status)\n", stderr)
            return
        }
        defaultInputListener = listener
        inputMonitoringAvailable = true
    }

    private func defaultInputDidChange() {
        let currentID = try? routeController.defaultInput()?.id
        defaultInputDidChange(currentID: currentID)
    }

    private func defaultInputDidChange(currentID: AudioDeviceID?) {
        let hadLease = ownership.lease != nil
        ownership.observeDefaultInputChange(currentID: currentID)
        if hadLease, ownership.lease == nil {
            for timeout in pendingCaptureTimeouts.values {
                timeout.cancel()
            }
            pendingCaptureTimeouts.removeAll()
        }
    }

    #if CORNERFLOAT_WEBKIT_INTEGRATION_TESTS
    var integrationHasTemporaryInputLease: Bool {
        ownership.lease != nil
    }

    var integrationPendingCaptureCount: Int {
        pendingCaptureTimeouts.count
    }

    func integrationObserveDefaultInputChange(currentID: AudioDeviceID?) {
        defaultInputDidChange(currentID: currentID)
    }

    func integrationCaptureStateDidChange(
        _ state: WKMediaCaptureState,
        webView: WKWebView
    ) {
        captureStateDidChange(state, webView: webView)
    }
    #endif

    private static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

enum VoiceAudioRouteCoordinatorError: Error, Equatable {
    case conflictingTemporaryInput
    case inputMonitoringUnavailable
}
