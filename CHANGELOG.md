# Changelog

Notable changes to CornerFloat are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and release versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.0] - 2026-07-20

### Added

- Conflict-safe global shortcut presets with persistent selection, accurate menu
  equivalents, system-reserved combinations excluded, and an in-place retry
  path when another app owns a combination.
- User-controlled Launch at Login through `SMAppService`, including approval
  guidance without any startup permission prompt.
- Validated JSON library export, preview, confirmed import, atomic replacement,
  Finder reveal, a data-format guide, and round-trip/rejection regression tests.
- Per-panel live-tab limits, `Control-Tab` / `Control-Shift-Tab` cycling, and
  accessible tab/close-button state with integration coverage.
- Safe confirmations for replacing or closing open windows, clearing recent
  history, and deleting local records.
- User-local `make install` / `make uninstall`, strict Swift concurrency checks,
  static Markdown/image/Python checks, and issue-ready first contributions.
- Release metadata preflight that rejects preview notes, mismatched versions, or
  an undated changelog before publication.
- Reproducible Universal 2 release builds with exact architecture validation for
  the app and every bundled Sparkle executable.

### Changed

- Settings now combines startup, login, edge behavior, global access, and local
  data portability in one reusable native surface.
- Contributor CI covers macOS 14 and 15 and treats complete concurrency warnings
  as errors.
- Developer ID releases default to a baseline mode that forbids the managed
  Passkey entitlement; the optional enhanced mode requires a validated profile
  and entitlements pair, while half-configured inputs fail closed.
- Source metadata advances to 0.8.0 (build 11).

### Fixed

- Saved workspaces now calculate the selected tab after filtering transient
  `about:`/`data:` tabs, preventing a different website from being selected on
  restore.
- Website popup bursts cannot create unbounded WebViews, and repeated limit
  notices are coalesced without stealing focus from a hidden panel.
- Repository screenshots now contain real PNG bytes matching their extensions.
- Rejected malformed or future-schema imports leave current in-memory state and
  on-disk bytes unchanged.

## [0.7.0] - 2026-07-20

### Added

- Contributor setup, architecture, governance, security, and community guides.
- Unified `make` commands plus local environment and bootstrap checks.
- Pull request CI, dependency update configuration, and structured issue and
  pull request templates.
- Explicit third-party license notices in source and application bundles.
- User-defined Quick Sites with multiple normalized aliases, local persistence,
  menu-bar access, editing, and safe HTTP/HTTPS-only resolution.
- `make run` for building and opening an ad-hoc local app without an Apple
  developer account.
- An English-first GitHub overview, complete Simplified Chinese README, compact
  architecture diagram, repository-safe product screenshots, and a decision
  record for the web-only product boundary.
- A reusable native Settings window for launch behavior, edge auto-hide, and
  global-shortcut registration status.
- Atomic download destination transactions and focused failure-preservation
  tests, so an incomplete download never deletes an existing chosen file.

### Changed

- Local source builds hide unavailable Passkey and automatic-update actions;
  those controls appear only in eligible configured release builds.
- The local library schema advances to version 4 with backward-compatible
  decoding for existing favorites, recents, and workspaces.
- Floating panels now share an integrated native macOS title bar, separator,
  traffic-light placement, and window material instead of mixing transparent
  and opaque window shells.
- Source metadata identifies release candidate 0.7.0 (build 10).
- Application menus now use standard macOS Settings, Hide, Hide Others, Show
  All, close-tab, and close-panel shortcuts.

### Removed

- Window mirroring, reconnectable mirror placeholders, and their Screen Recording
  and original-window Accessibility permission paths. Existing libraries still
  decode safely: web panels remain available while retired mirror entries are
  ignored.

### Fixed

- Narrow web panels collapse the single-tab strip and use a compact browser
  toolbar with navigation available in the More menu, avoiding the duplicate
  system overflow control and preserving useful address-field space.
- Dismissing onboarding with the red close button no longer opens ChatGPT; only
  completing the final primary action opens the default panel.
- Future library schemas are detected before nested decoding and opened
  read-only, while persisted URLs remove transient authentication values and
  overlong addresses.

## [0.6.1] - 2026-07-20

### Changed

- ChatGPT Google sign-in is no longer preemptively canceled before Google can
  evaluate the session. CornerFloat now identifies itself truthfully in the
  WebKit user-agent and exposes native connection-security details without
  spoofing another browser or rewriting authentication requests.

## [0.5.0] - 2026-07-19

### Added

- Global panel visibility shortcut and optional edge auto-hide.
- Browser tabs, smart destinations, persistent website data, OAuth fallback,
  uploads, downloads, and safe recovery states.
- Favorites, recents, and restorable multi-panel workspaces.
- Explicit passkey authorization, native window mirroring, and lower-energy
  capture lifecycle management.
- Multi-display and Spaces behavior, Liquid Glass support with macOS 14-15
  fallback, onboarding, privacy/support pages, and Sparkle release tooling.

Detailed user-facing notes are available in [RELEASE_NOTES.md](RELEASE_NOTES.md).
