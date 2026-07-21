# Contributing to CornerFloat

Thank you for helping make CornerFloat better. The project welcomes bug fixes,
tests, documentation, accessibility improvements, and focused feature work.

CornerFloat is a native macOS utility with browser, accessibility, and update
surfaces. A small change can cross a permission or security boundary, so
please keep pull requests narrow and explain the user-visible behavior.

## Before opening a change

- Search existing issues before starting duplicate work.
- Open an issue first for new permissions, persistent data, network behavior,
  dependencies, or large UI changes.
- Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component ownership and
  the invariants that changes must preserve.

Small fixes, tests, spelling corrections, and documentation improvements can go
straight to a pull request.

## Development setup

You need:

- a Mac running macOS 14 or later;
- Xcode or Apple Command Line Tools with Swift Package Manager;
- Git, Python 3, and the standard macOS developer command-line utilities.

Check the machine and resolve the pinned dependencies:

```bash
make bootstrap
```

Build and run the automated test suite:

```bash
make build
make run
make test
make check
```

The app bundle is written to `dist/CornerFloat.app`. It is ad-hoc signed for
local development and personal use; no Apple developer account is required.
It is not a public release artifact. See
[docs/SOURCE_BUILD.md](docs/SOURCE_BUILD.md) for the source/release distinction.

For a quick list of available commands, run `make help`.

## Making a change

1. Create a short-lived branch from the default branch.
2. Keep the change focused on one problem.
3. Add or update tests for behavior that can be tested without private accounts
   or macOS permission prompts.
4. Run `make check` before opening the pull request.
5. Complete the pull request template, including the privacy and permission
   checklist.

Use clear Swift names, prefer system frameworks over new dependencies, and keep
AppKit mutations on the main actor. Comments should explain a non-obvious reason
or invariant rather than restating the code.

## Testing levels

`make test` covers the reproducible contributor suite: build, application
self-test, address and browser helpers, passkey authorization state handling,
real local `WKWebView` integration, and release validators.

`make check` adds the environment audit, repository link/format checks, and a
complete strict-concurrency compile with warnings treated as errors. It is the
expected pre-pull-request command.

`make acceptance` additionally opens real AppKit windows and checks the global
hot key and lifecycle diagnostics. Run it from a logged-in macOS desktop.

Some behaviors require manual validation and must not be claimed from CI:

- physical multi-display disconnect and reconnect;
- system sleep and wake;
- third-party OAuth and passkey flows with disposable accounts;
- Developer ID signing, notarization, and Sparkle update installation.

For a focused ChatGPT Google-login check, build the app and launch:

```bash
dist/CornerFloat.app/Contents/MacOS/CornerFloat --google-login-acceptance
```

Use a disposable test account or a maintainer-controlled account. Confirm that
**Continue with Google** stays in the CornerFloat panel, returns to
`https://chatgpt.com/`, and remains signed in after quitting and relaunching the
same app. Credentials, one-time codes, OAuth query strings, and cookies must
never be recorded in logs, screenshots, fixtures, or issue reports.

See [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) and
[docs/LIFECYCLE_AND_ENERGY_TESTING.md](docs/LIFECYCLE_AND_ENERGY_TESTING.md).

## Privacy and permission rules

Changes must preserve these defaults:

- ordinary web panels do not request special macOS privacy permission;
- passkey authorization is requested only after an explicit user action;
- unsafe navigation schemes stay blocked, and external schemes require consent;
- failed form submissions are never replayed silently;
- no analytics, advertising identifiers, or credential logging.

If a change affects any of these rules, call it out explicitly in the issue and
pull request.

## Pull request expectations

A reviewable pull request includes:

- a concise explanation of the problem and solution;
- the exact commands used to test it;
- screenshots or a short recording for visible UI changes, with private data
  removed;
- documentation and release-note updates when behavior changes;
- no generated build output, credentials, provisioning profiles, or private
  account data.

Maintainers may ask to split a large pull request. Release signing and
publication remain maintainer-only because they use private Apple and Sparkle
credentials.

By contributing, you agree that your contribution is licensed under the
project's [MIT License](LICENSE).
