# CornerFloat Architecture

This document is the contributor map for the current application. It describes
ownership and safety boundaries, not a promise that every internal type is a
stable public API.

## Product boundary

CornerFloat is one native menu-bar application whose WebKit panels own their own
tabs and website data.

It is not a browser extension, remote-control service, or plugin host. Keeping
those boundaries explicit is part of the product's privacy model.

The decision to retire native window mirroring and keep ordinary browsing and
global access permission-free is recorded in
[`docs/decisions/0001-web-workspaces-without-window-mirroring.md`](decisions/0001-web-workspaces-without-window-mirroring.md).

## Component map

| Area | Primary files | Responsibility |
| --- | --- | --- |
| Application lifecycle | `main.swift`, `AppController.swift` | Start the menu-bar app, own controllers, coordinate panels, onboarding, sleep/wake, and app-level actions |
| Menus and global entry points | `MainMenuController.swift`, `StatusBarController.swift`, `GlobalHotKeyController.swift`, `LaunchAtLoginController.swift` | Native menus, status item, configurable permission-free hot key, and user-controlled Login Item registration |
| Floating window foundation | `FloatingPanelController.swift`, `WindowGeometry.swift`, `GlassUI.swift` | Panel style, native resizing, placement, Spaces behavior, edge auto-hide, and material fallback |
| Browser | `WebPanelController.swift`, `BrowserComponents.swift`, `BrowserSupport.swift`, `SmartAddressResolver.swift` | Tabs, WebKit delegates, address resolution, navigation and media-capture policy, uploads, downloads, dialogs, and recovery UI |
| Audio-route preflight | `AudioRouteSupport.swift`, `VoiceAudioRouteCoordinator.swift`, `WebPanelController.swift` | Read local Core Audio route facts, classify Bluetooth voice-quality risk, coordinate an explicit temporary input choice, and conditionally restore it |
| Local library | `WorkspaceLibrary.swift`, `WorkspaceLibraryController.swift` | Quick Sites, favorites, recents, saved layouts, persistence, and the management window |
| Passkeys | `PasskeyAuthorization.swift` | User-triggered browser passkey authorization state and recovery guidance |
| Updates | `UpdateController.swift` plus release scripts | Sparkle wiring for configured releases and offline-safe behavior for development builds |
| Product pages | `ProductExperience.swift`, `Resources/*.html` | Onboarding, privacy, support, and safe diagnostics |
| Diagnostics | `LifecycleDiagnostics.swift`, `scripts/*tests*` | Reproducible self-tests, AppKit acceptance, energy evidence, and release validation |

## Ownership and lifecycle

`AppController` owns the long-lived controllers. Panel controllers own their
window and feature-specific session. Closing a panel must unregister it from the
application controller and release its browser activity. Quitting the application
is intentionally different from closing the last panel because
CornerFloat is a menu-bar utility.

AppKit and application state mutations are main-actor work. Asynchronous WebKit
callbacks must cross back through an explicit, serialized path before changing
UI or shared lifecycle state.

## Browser navigation flow

User text first passes through `SmartAddressResolver`. A valid user-defined Quick
Site alias takes precedence, built-in shortcuts resolve to explicit HTTPS
destinations, host-like input becomes a URL, localhost uses HTTP, and everything
else becomes a percent-encoded Google search. Stored Quick Site destinations are
revalidated as HTTP/HTTPS every time they are resolved.

`WebPanelController` then applies navigation policy. The key invariants are:

- the address bar accepts only HTTP and HTTPS results;
- dangerous local or script schemes are blocked;
- external application schemes require user confirmation;
- HTTP/HTTPS OAuth redirects remain in the selected tab (or the popup tab
  created by WebKit) unless the provider itself refuses the session;
- WebKit generates the browser user-agent and appends only the truthful
  `CornerFloat/<version>` product token; navigation code must not impersonate
  Safari, Chrome, or another browser, inject credentials, or rewrite OAuth
  requests;
- the toolbar keeps the full URL visible and derives its connection indicator
  from WebKit's secure-content and server-trust state;
- only intact, body-free GET or HEAD requests may be retried automatically;
- persistent WebKit data belongs to the current macOS user, not to CornerFloat's
  workspace JSON.

When adding a built-in shortcut, update `SmartAddressResolver.swift` and the
resolver tests together. User-defined aliases belong in the versioned local
library and must reject duplicate normalized aliases. Do not add a built-in
shortcut that silently sends unexpected data to a new service.

## Website media-capture boundary

Ordinary browser features do not themselves ask for microphone or camera access. The
`WKUIDelegate` media callback maps WebKit capture types through the testable
`BrowserSupport` policy. Only a microphone request from an HTTPS origin returns
`prompt`; insecure, camera, combined camera-and-microphone, and unknown requests
return `deny`. A website controls when it requests access; returning `prompt`
does not grant capture, because the user still controls
both macOS microphone access for CornerFloat and WebKit permission for the
requesting website.

The app declares `NSMicrophoneUsageDescription`, and every local or formal
signature carries `com.apple.security.device.audio-input`. It deliberately has
no camera usage declaration or camera entitlement. CornerFloat does not own an
audio recorder, audio store, or audio upload path; after approval, the selected
website handles microphone audio under its own privacy policy.

Before returning `prompt` on a risky Bluetooth input/output route, the browser
controller pauses the decision and presents a native preflight. When a built-in
input is available, the user can explicitly choose one of three outcomes:

- temporarily set a currently available built-in Mac microphone as the system
  default input, then continue to WebKit's website decision;
- leave the Bluetooth route unchanged and continue to WebKit's website
  decision; or
- deny the current request.

Without a built-in alternative, the preflight omits the first outcome and offers
only continue or cancel.

Reading a route snapshot never changes system state. A switch effect is emitted
only after the first choice, and the Core Audio layer verifies that the target
is an available built-in input before writing the system default. The previous
input and the temporary replacement live only in the active preflight state.
When WebKit reports microphone capture ended, the panel closes, or the app
terminates, restoration is best effort and conditional: restore only if the
current default still equals CornerFloat's temporary input. A user or another
application that changes the input in the meantime also causes the shared
coordinator to relinquish restoration ownership when Core Audio reports the
default-input event.

Unknown metadata, a missing built-in alternative, or a failed input switch must
not cause a silent device change. Snapshot-inspection failure falls back to the
standard WebKit prompt; a missing built-in alternative removes the switch
option; an attempted switch failure denies that request and explains how to
choose an input manually. The preflight does not intercept microphone samples,
grant a website blanket permission, persist an audio-device choice, or inject
Web Audio processing. Keep Core Audio inspection and mutation behind the small
route controller, route policy in the pure state machine, and AppKit/WebKit
decisions on the main actor.

## Persistence

`WorkspaceLibrary` stores Quick Sites, favorites, recents, workspace descriptors,
and layout state under the current user's Application Support directory. It also
owns the validated, version-probed export/import transaction. User preferences
use macOS defaults. WebKit stores website data separately and never enters a
library export. See [`DATA_FORMAT.md`](DATA_FORMAT.md).

Persisted models need backwards-compatible decoding. New fields should have safe
defaults so an older library remains readable. Destructive schema migrations
need a rollback or backup plan and dedicated tests.

## Update trust boundary

Development builds are ad-hoc signed and omit the public Sparkle feed. Baseline
public updates require a Developer ID identity, Hardened Runtime, notarization
and stapling, an HTTPS appcast, and an EdDSA-signed update archive. The baseline
validator forbids a managed Passkey entitlement or embedded profile. An optional
Passkey-enhanced release additionally requires Apple approval and a matching
provisioning profile; this non-core capability never blocks the baseline path.

The private Apple and Sparkle credentials never belong in the repository. See
`docs/RELEASE_CHECKLIST.md` for the release-only trust chain.

## Testing strategy

- Pure helper tests exercise address resolution, filenames, retry safety, error
  mapping, media-capture policy, and external schemes.
- Audio-route tests exercise Bluetooth/low-rate risk classification, explicit
  state-machine choices, verified switching, and the rule that restoration
  never overwrites a later input-device change.
- Authorization tests use fakes to prove passkey prompts remain user-triggered.
- WebKit integration tests use a loopback-only fixture and production browser
  controller code, including microphone-decision wiring without claiming to
  reproduce Bluetooth hardware behavior.
- Application self-tests verify model and controller invariants without private
  services.
- AppKit acceptance runs real windows, the Carbon hot key, and lifecycle/energy
  diagnostics on a logged-in desktop.
- Repository and release validators verify the microphone purpose string and
  audio-input entitlement in source, built, baseline, and Passkey signing paths.
- Manual release checks cover real website microphone prompts, accounts,
  displays, sleep/wake, signing, notarization, and installed updates.

CI evidence must not be presented as proof of a hardware-, account-, or
permission-dependent behavior that CI did not perform.

## Adding a feature safely

Before coding, identify which of these contracts the feature changes:

- permission request timing;
- data written to disk;
- network destinations;
- navigation or download policy;
- background CPU or energy behavior;
- accessibility labels and keyboard operation;
- saved-workspace compatibility;
- release signing or entitlement requirements.

Prefer a small testable model or resolver outside the view controller, then wire
it into AppKit. If a feature needs a new dependency, document why a system API or
small local implementation is insufficient.
