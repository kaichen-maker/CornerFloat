# Prepared first contributions

These are issue-ready slices for a public repository. Each is intentionally small
enough to review independently; maintainers should create the matching GitHub
Issue and assign `good first issue` only after confirming it is still unclaimed.

## Add a Quick Site from the active page

- Scope: `AppController.swift`, browser More menu, Manager refresh.
- Acceptance: prefill the title and sanitized HTTP(S) URL; require at least one
  alias; cancel leaves the library unchanged.
- Verify: `make test` and `make acceptance`.

## Add a Duplicate Current Tab command

- Scope: `WebPanelController.swift` and the browser More menu.
- Acceptance: duplicate only the selected persistable HTTP(S) URL into a new
  tab; respect the 24-tab limit; transient form bodies and history are not
  replayed; the command is unavailable on a non-web tab.
- Verify: WebKit integration test plus `make acceptance`.

## Export a redacted diagnostic summary

- Scope: a new pure diagnostic formatter and Support page action.
- Acceptance: include app/macOS versions and feature state; exclude URLs, titles,
  cookies, paths under the home folder, and all website data.
- Verify: fixture-based redaction tests and `make test`.

## Add localization infrastructure

- Scope: replace the temporary `CFL10n` shim with string catalogs, starting with
  Settings and Manager.
- Acceptance: English remains the source language; Simplified Chinese follows
  system language; no mixed-language window; layout survives both languages.
- Verify: screenshot both languages and run `make acceptance`.

## Improve empty-state keyboard navigation

- Scope: Manager sidebar/content tables and accessibility labels.
- Acceptance: VoiceOver announces section, empty state, and available action;
  keyboard focus does not land on disabled controls.
- Verify: Accessibility Inspector notes plus `make acceptance`.

## Add a release artifact manifest

- Scope: release scripts and validator tests only.
- Acceptance: generate checksums and architecture, version, signing-mode, and
  notarization metadata for every DMG/ZIP without secrets or machine paths.
- Verify: release-validator fixture tests and `make test`.
