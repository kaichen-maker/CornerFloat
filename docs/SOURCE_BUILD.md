# Build CornerFloat from Source

The normal open-source workflow requires no Apple developer account, paid
membership, Developer ID certificate, notarization credential, provisioning
profile, or Sparkle private key.

## Build and run

On macOS 14 or later with Xcode or Apple Command Line Tools installed, clone or
download this repository from its GitHub page. After Git creates or you unpack
the `CornerFloat` directory:

```bash
cd CornerFloat
make bootstrap
make run
```

`make bootstrap` checks the local tools and resolves the pinned Swift package.
`make run` builds `dist/CornerFloat.app`, applies an ad-hoc local signature, and
opens the app. The build stays entirely on the Mac except for normal website
traffic and the initial dependency download.

Use these commands while contributing:

```bash
make help
make build
make test
make check
make acceptance
```

`make check` includes complete Swift concurrency checking with compiler warnings
treated as errors. `make acceptance` additionally opens real AppKit windows and
therefore needs a logged-in desktop session.

`make universal` is the slower release-oriented build. It compiles independent
arm64 and x86_64 slices, combines them, and verifies the exact architectures in
the app and bundled Sparkle executables. The normal `make build` intentionally
uses only the current Mac architecture for a faster edit/run loop.

## Install and remove a local build

Install a reusable copy in the current user's Applications folder without
administrator access:

```bash
make install
```

The destination defaults to `~/Applications/CornerFloat.app`. Override it only
for an isolated test with `CORNERFLOAT_INSTALL_DIR=/path make install`.

Remove that app bundle while preserving all user data:

```bash
make uninstall
```

This does not remove preferences, library records, or WebKit website sessions.
For a deliberate full reset, quit CornerFloat and remove each layer separately:

```bash
defaults delete com.calvinkai.cornerfloat
rm -rf "$HOME/Library/Application Support/CornerFloat"
```

WebKit cookies and website data are separate. Remove them only when the goal is
also to sign out of every website; ordinary uninstall or library reset should
not delete them.

## What works in a source build

- native floating WebKit panels and tabs;
- smart search and user-defined Quick Sites;
- favorites, recents, and saved workspaces;
- global show/hide shortcut, resizing, opacity, click-through, and edge auto-hide.
- Launch at Login, conflict-safe shortcut presets, and local library export/import.

Two release-only controls stay hidden because they would be misleading in an
ad-hoc build:

- **Check for Updates** requires a release-injected HTTPS Sparkle feed and public
  verification key;
- **Enable or Review Passkey Access** requires an Apple-approved entitlement and
  matching embedded distribution provisioning profile.

Ordinary website password login remains a WebKit/site capability and does not
depend on either release-only control. Some OAuth providers still require the
system browser by policy.

## Source project versus binary distribution

| Goal | Apple developer account | Developer ID / notarization | Sparkle keys |
| --- | --- | --- | --- |
| Publish source on GitHub | No | No | No |
| Build and use on your own Mac | No | No | No |
| Accept pull requests and run CI | No | No | No |
| Distribute a trusted app or DMG to other users | Yes | Yes | Only if automatic updates are offered |

The optional maintainer release process is isolated in
[`docs/RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) and the manually triggered
release workflow. It is not part of contributor CI.

## Forks

MIT permits forks, modification, and redistribution. A fork that distributes
binaries should choose its own bundle identifier, application identity, privacy
text, signing certificate, update feed, and keys. Never reuse another project's
signing identity or present an unofficial fork as an official CornerFloat build.

Build output, certificates, private keys, provisioning profiles, and local user
data are excluded from Git. Before a pull request, run `git status` and `make
check`.
