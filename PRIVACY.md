# CornerFloat Privacy Policy

Effective July 22, 2026.

CornerFloat does not operate an account service, analytics service, or advertising service. Preferences, user-defined Quick Sites (names, aliases, and destination URLs), favorites, recent destinations, and saved web-workspace layouts stay in the current macOS user account. Web sessions and cookies are stored by Apple WebKit. Downloads are saved only where the user chooses.

The Settings window can export the CornerFloat library as versioned JSON. That
file contains the four library collections only; it does not contain website
cookies, passwords, account sessions, downloads, or WebKit website data. Import
validates a file before an explicit confirmed replacement. Launch at Login is
registered with macOS only after the user changes that switch.

A local source build hides the release-only passkey action. In an eligible signed release, CornerFloat does not request passkey access at launch. Only the explicit **Enable or Review Passkey Access…** menu action checks the system state and, when it is not yet determined, asks macOS for access to passkeys stored in Apple Passwords or compatible credential managers. CornerFloat does not copy passkeys into its own library; authentication remains in the macOS, WebKit, and website flow.

Ordinary browsing, tabs, workspaces, and global shortcuts do not themselves need
microphone or camera access. When an HTTPS website requests the microphone—
normally after the user starts voice or dictation—CornerFloat allows WebKit to
present a microphone decision.
Microphone use then remains behind two separate user-controlled permissions:
macOS access for CornerFloat and WebKit access for the requesting website.
CornerFloat never grants either automatically. Camera requests, including
combined camera-and-microphone requests, are denied.

CornerFloat does not itself record, store, or upload microphone audio. After
both permissions are granted, audio is captured for and handled by the selected
website under that website's terms and privacy policy. The website may transmit
or retain audio independently of CornerFloat, so review its policy before use.

Traffic to websites is governed by those websites’ policies. If automatic updates are enabled, the configured update feed receives a normal HTTP request that can include version, macOS version, IP address, and user agent. CornerFloat adds no advertising or cross-site identifier.

To delete Quick Sites, favorites, recents, and saved workspaces, quit CornerFloat and remove `~/Library/Application Support/CornerFloat`. Preferences are stored separately by macOS; run `defaults delete com.calvinkai.cornerfloat` while CornerFloat is quit to reset them. WebKit cookies and website data are separate and must also be removed if the goal is to clear website sessions. See the in-app Privacy Policy for the complete policy.
