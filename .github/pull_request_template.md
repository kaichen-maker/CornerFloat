## What changed

<!-- Explain the user problem and the focused solution. -->

## Verification

<!-- List exact commands and manual scenarios. Do not claim hardware, account, or permission coverage that was not performed. -->

- [ ] `make check`
- [ ] AppKit acceptance, if relevant
- [ ] Manual macOS scenario, if relevant

## Visual evidence

<!-- Add sanitized before/after screenshots or a short recording for UI changes. Remove account data, private URLs, and window titles. -->

## Safety checklist

- [ ] Ordinary web panels still request no special macOS privacy permission.
- [ ] Passkey permission remains tied to an explicit user action.
- [ ] No credentials, private keys, provisioning profiles, cookies, or personal data are included.
- [ ] Navigation, downloads, persistence, and retry behavior remain safe or the change is explained above.
- [ ] Accessibility, reduced transparency, keyboard control, Spaces, and multiple displays were considered.
- [ ] Documentation and `CHANGELOG.md` are updated when user-visible behavior changes.
- [ ] Any new dependency, network destination, persistent field, or permission was discussed in an issue.

## Related issue

<!-- Example: Closes #123 -->
