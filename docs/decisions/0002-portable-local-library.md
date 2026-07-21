# ADR 0002: Keep the library local, inspectable, and portable

- Status: Accepted
- Date: 2026-07-20

## Context

Favorites, Quick Sites, recents, and workspaces become valuable only if users can
back them up and move them without trusting an account service. Import is also a
destructive boundary: a malformed or future file must not corrupt a working
library, and browser authentication data must not leak into a convenient export.

## Decision

CornerFloat stores a small versioned JSON document locally and exposes explicit
export, preview, confirmed replacement, and reveal actions. Import candidates are
version-probed, decoded, capped, and URL-sanitized before the live snapshot is
modified. Rejected imports leave both in-memory state and on-disk bytes intact;
successful writes use the platform's atomic replacement behavior.

WebKit cookies, credentials, and website storage are intentionally outside this
format. A library import never mutates them. Future schemas are preserved
read-only rather than treated as corruption.

## Consequences

- Users can inspect and back up the useful product data without an account.
- Contributors have a documented compatibility and privacy boundary to test.
- Sync and merge are not implied; import deliberately replaces collections.
- Any future cloud sync must build on this boundary without silently absorbing
  website data or weakening forward-version safety.
