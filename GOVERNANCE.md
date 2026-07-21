# Governance

CornerFloat is currently a maintainer-led open-source project.

The maintainer sets release scope, reviews changes, manages security reports, and
holds the Apple signing and Sparkle update credentials. Contributors influence
the direction through issues, design discussions, tests, documentation, and pull
requests.

## How decisions are made

Small, reversible changes are decided in pull-request review. Changes that add a
permission, network service, dependency, persistent data, public extension point,
or broad interaction pattern should begin with an issue and include:

- the user problem;
- the proposed behavior;
- macOS-native alternatives considered;
- privacy, accessibility, energy, and compatibility effects;
- a test and rollback strategy.

The project prioritizes, in order:

1. user control and understandable permission boundaries;
2. native macOS behavior and accessibility;
3. reliability, security, and low background resource use;
4. focused usefulness over feature count;
5. maintainability for a small contributor community.

Consensus is preferred, but the maintainer makes the final call when a decision
is needed. Important decisions should remain visible in the issue or pull request
that motivated them.

## Becoming a regular contributor

There is no formal role ladder yet. Repeated high-quality contributions may lead
to issue-triage or review responsibilities after a public discussion. Merge,
release, security-advisory, and signing access are granted separately and use the
least privilege required.

This governance model can be revised as the contributor community grows.
