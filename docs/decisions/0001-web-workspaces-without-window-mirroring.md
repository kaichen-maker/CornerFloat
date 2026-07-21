# ADR 0001: Keep CornerFloat focused on web workspaces

- Status: Accepted
- Date: 2026-07-20
- Applies from: 0.7.0 source preview

## Context

CornerFloat originally included a window-mirroring mode. A user could select a
window owned by another application, and CornerFloat would capture it into a
floating panel. Supporting that mode required ScreenCaptureKit, Screen Recording
permission, optional Accessibility access for interaction with the source
window, capture lifecycle management, source-window reconnection, and saved
placeholder state.

That behavior overlapped with the web-panel experience at the window level but
not at the product or security level. A CornerFloat web panel owns an interactive
`WKWebView`; a mirrored panel observes and coordinates a window owned by another
process. The two modes therefore had different permission, energy, failure, and
testing boundaries.

## Decision

CornerFloat is a native floating **web workspace**, not a general window
mirroring or remote-control utility. The application owns and floats its own
interactive HTTP and HTTPS panels. It does not capture or control windows from
other applications.

The window-mirroring UI, capture runtime, reconnectable placeholders,
ScreenCaptureKit dependency, and Screen Recording and source-window
Accessibility permission paths are removed.

## Why

### Product boundary

A narrower promise is easier for users and contributors to understand:
CornerFloat keeps selected websites available beside other work. It does not
claim to make every native application always-on-top.

### Permissions and privacy

Core browsing, saved workspaces, and the global show/hide hot key now require no
Screen Recording or Accessibility permission. The app no longer receives image
frames from unrelated application windows, even temporarily.

### Energy and lifecycle

An owned `WKWebView` still consumes resources according to the loaded website,
but CornerFloat no longer runs a separate capture stream, frame pipeline, or
source-window polling and reconnection lifecycle. Sleep, wake, display changes,
Spaces, and app termination have fewer cross-process states to reconcile.

### Open-source maintainability

Contributors can build and exercise the core product without granting capture
permissions or arranging a second application window. Removing the additional
system frameworks and permission-dependent acceptance path reduces the number
of macOS-version-specific behaviors that a small project must support.

## Compatibility

Saved libraries remain readable. During library sanitization, legacy mirror
panel records are recognized for backwards-compatible decoding and then ignored.
Compatible web panels, Quick Sites, favorites, recents, and other workspace data
remain available. CornerFloat does not convert a captured native window into a
web destination because there is no reliable or privacy-preserving one-to-one
mapping.

This is a one-way product migration: current builds do not restore legacy mirror
panels. Users who need to inspect an old library should preserve their own backup
before replacing an older build.

## Alternatives considered

- **Keep both panel types.** Rejected because it preserves two distinct product,
  permission, energy, and failure models behind one similar-looking UI.
- **Keep mirroring as an optional module.** Rejected for now because optional
  code still carries release, compatibility, testing, and support costs. A future
  extension boundary would require a separate security and lifecycle design.
- **Control the original window through Accessibility only.** Rejected because
  it does not provide the independent floating web-workspace behavior and would
  retain a broad permission for a secondary capability.
- **Convert every selected window to a website.** Rejected because many native
  applications have no equivalent URL or transferable session.

Users who need generic application-window pinning should use a purpose-built
macOS window-pinning tool. When a service has a web interface, it can be opened
directly as a CornerFloat panel and saved in a workspace.

## Consequences

Positive consequences:

- a clearer product description and contribution boundary;
- no Screen Recording or Accessibility permission for core use;
- fewer background capture and cross-process lifecycle states;
- simpler builds, tests, privacy documentation, and support guidance.

Trade-offs:

- native application windows can no longer be floated through CornerFloat;
- legacy mirror entries disappear when a saved workspace is restored;
- web panels cannot inherit another browser or application's in-memory session.

Reintroducing window mirroring would require a new decision record covering its
user problem, permission timing, capture-energy budget, compatibility contract,
test evidence, and separation from the default web-only experience.
