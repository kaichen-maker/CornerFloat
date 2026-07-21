# CornerFloat Roadmap

CornerFloat is early-stage software. This roadmap communicates direction; it is
not a promise of dates or a guarantee that every item will ship.

## Current focus: open-source readiness

- reproducible setup, build, test, and CI commands;
- contributor, governance, security, and community documentation;
- clearer architecture and permission boundaries;
- source-first local execution without an Apple developer account;
- user-defined Quick Sites with safe, inspectable HTTP/HTTPS destinations;
- accessibility and keyboard-quality review across every native surface;
- focused regression tests around persistence, navigation, and lifecycle;
- conflict-safe shortcut presets, Launch at Login, and portable local library data;
- baseline signed releases that do not depend on optional managed entitlements.

## Good first contributions

Issue-ready versions with file scope and acceptance criteria are maintained in
[Prepared first contributions](GOOD_FIRST_ISSUES.md).

- add resolver tests for more malformed URLs and internationalized search text;
- audit missing VoiceOver labels, tooltips, and keyboard focus order;
- improve empty-state and error copy without changing permission behavior;
- add documentation screenshots with all account data removed;
- improve developer diagnostics for unsupported Xcode or SDK combinations;
- test backwards-compatible decoding of saved workspace data.

## Next candidates

- localization infrastructure and a complete Simplified Chinese translation;
- optional merge workflows on top of the documented replace-only library import;
- clearer per-site data controls and an in-app path to remove website data;
- stronger UI automation for resizing, tabs, edge auto-hide, and multiple panels;
- a fully signed, notarized public beta and verified Sparkle update path.

## Later exploration

- optional agent-oriented task surfaces that use explicit provider integrations;
- a documented extension model, only after sandboxing, permissions, update trust,
  and compatibility can be kept understandable;
- broader architecture support if it can be tested and released reliably.

## Explicit non-goals today

- bypassing website OAuth or macOS privacy controls;
- copying cookies or credentials between CornerFloat and another browser;
- accepting unreviewed executable plugins inside the app process.

Please open an issue before starting a roadmap item that changes permissions,
persistence, networking, dependencies, or the extension boundary.
