# Security Policy

CornerFloat embeds web content, opens external applications, downloads files,
and installs signed updates. Please report security problems privately so a fix
can be prepared before public disclosure.

## Supported versions

| Version | Security updates |
| --- | --- |
| Current default branch | Yes |
| Latest published minor release | Best effort |
| Older releases | No |

Until the first public release is available, only the current source tree is
considered supported.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for the repository when it is
available. If it is not enabled, contact the maintainer through a private channel
listed on their GitHub profile. Do not include the vulnerability in a public
issue or discussion.

Include:

- affected CornerFloat version or commit;
- macOS version and Mac architecture;
- a minimal reproduction and expected security boundary;
- realistic impact and whether user interaction is required;
- sanitized logs, screenshots, or proof-of-concept files;
- any disclosure deadline that you need the project to consider.

Never send passwords, session cookies, passkeys, Apple signing credentials,
Sparkle private keys, provisioning profiles, or another person's data.

The maintainer aims to acknowledge a complete report within seven days and will
coordinate validation, remediation, and disclosure. This is a volunteer project,
so complex fixes may take longer; reporters will be told when the assessment or
timeline changes.

## Particularly sensitive areas

- URL parsing, navigation policy, external URL schemes, and OAuth fallback;
- cookie/session persistence and website data isolation;
- download filenames, destinations, and filesystem access;
- JavaScript dialogs, uploads, popups, and failed-request retry behavior;
- passkey authorization and managed entitlements;
- Sparkle feed validation, signature verification, and release publication.

Normal product bugs, crashes without a security impact, and feature requests can
use the public issue templates.
