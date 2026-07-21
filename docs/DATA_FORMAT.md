# Local library and portability

CornerFloat keeps its small, user-curated library in a versioned JSON file at:

```text
~/Library/Application Support/CornerFloat/Library-v1.json
```

The library contains favorites, recent destinations, Quick Sites, and saved
workspace geometry. It does **not** contain website cookies, passwords, Google
or ChatGPT sessions, downloads, browsing-page contents, or a copy of WebKit's
website data.

## Export and import

Settings → Local Data provides three explicit actions:

- **Export Library…** writes a portable JSON backup chosen by the user.
- **Import Library…** validates and previews a backup, then asks before replacing
  the current library.
- **Reveal Data** opens the local file in Finder for inspection or manual backup.

An import is parsed and schema-checked completely before the active library is
changed. Malformed files and schemas created by a newer CornerFloat release are
rejected without rewriting the current bytes. A successful replacement is an
atomic file write. URL credentials, authentication fragments, and known secret
query parameters are removed at persistence boundaries.

Import replaces the four library collections. It does not close open panels or
modify WebKit cookies and sign-ins. Export first when merging by hand or moving
between machines.

## Compatibility contract

The top-level `version` field is the compatibility boundary. This release writes
schema 4 and can migrate supported older web-only schemas. If it encounters a
higher version at normal startup, it opens the library read-only and leaves the
original file untouched. Retired mirror-window records remain decode-compatible
but are deliberately omitted from current data.

The JSON layout is an implementation format rather than a stable public API.
Contributors changing it must update the schema number when necessary, preserve
safe forward-version behavior, extend `WorkspaceLibrarySelfTest`, and document
the migration in the changelog.

## Full reset

Removing the app does not remove user data. See [Source build and local use](SOURCE_BUILD.md)
for the separate app, preferences, library, and WebKit-data cleanup paths. Never
delete WebKit data merely to remove the CornerFloat library: that would also sign
the user out of websites.
