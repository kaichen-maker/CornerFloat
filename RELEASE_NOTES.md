# CornerFloat 0.8.0

CornerFloat 0.8.0 (build 11) turns the native floating web workspace into a
safer daily-use utility and a more reproducible open-source project.

## Highlights

- **Choose the global shortcut.** Settings offers four permission-free presets.
  If macOS or another app owns a combination, CornerFloat keeps the previous
  working shortcut and explains the conflict.
- **Launch at Login when you want it.** The new switch uses macOS Login Items,
  changes registration only after an explicit action, and links to System
  Settings when approval is required.
- **Own and move your local data.** Export favorites, recents, Quick Sites, and
  saved workspaces as versioned JSON. Import validates and previews the entire
  file before a confirmed atomic replacement. Website cookies and sign-ins are
  never included.
- **Safer browser tabs.** `Control-Tab` and `Control-Shift-Tab` cycle tabs, real
  tab buttons expose selected state to assistive technology, and each panel
  limits popup bursts to 24 live tabs with coalesced feedback.
- **Fewer accidental losses.** Replacing or closing windows, clearing all
  recents, and deleting local library records now require specific native
  confirmations that explain what changes and what remains.
- **Use website voice and dictation safely.** An HTTPS site can ask for the
  microphone, normally after you start its voice or dictate feature. macOS and
  the site each keep their own approval, while camera access remains blocked.

## Reliability and contributor improvements

- Fixed saved-workspace selection when transient `about:` or `data:` tabs are
  filtered out, so the intended website remains selected after restoration.
- Added malformed/future import rejection tests that prove existing bytes and
  in-memory data remain untouched.
- Added `make install`, `make uninstall`, dependency-free repository checks,
  complete Swift concurrency checking with warnings as errors, and macOS 14/15
  contributor CI coverage.
- Converted repository screenshots to genuine PNG assets and added automatic
  format/link verification.
- Added release metadata validation and decoupled ordinary Developer ID releases
  from Apple's optional managed Passkey entitlement. Baseline artifacts reject
  that entitlement; an enhanced release requires a complete validated profile
  and entitlements pair.
- Formal release builds now compile and combine arm64 and x86_64 slices, verify
  every app and Sparkle Mach-O, and publish consistently named Universal 2 ZIP
  and DMG artifacts.

## Permissions and compatibility

CornerFloat requires macOS 14 or later. Normal panels, tabs, search, Quick
Sites, workspaces, global shortcuts, library portability, and Login Item control
need no Accessibility, Input Monitoring, Screen Recording, camera, or microphone
permission by themselves. When an HTTPS website requests the microphone, WebKit
may prompt. The user must separately approve macOS access
for CornerFloat and access for that website. CornerFloat does not automatically
grant access or itself record, store, or upload audio; the selected website
handles approved audio under its own policy. Camera and combined capture remain
denied.

Google, Microsoft, or an organization may still reject OAuth inside `WKWebView`.
CornerFloat does not bypass provider policy or copy a system-browser session;
**More → Open in Default Browser** remains the explicit fallback. Cross-site
Passkeys remain available only in an Apple-approved enhanced signed build.
