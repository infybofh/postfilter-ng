# Security policy

## Supported versions

Security fixes are prepared for the current stable release and the latest
release candidate. Older alpha and release-candidate archives are retained as
history and do not receive fixes.

## Reporting a vulnerability

Use the repository's private security advisory form:

https://github.com/infybofh/postfilter-ng/security/advisories/new

Include the affected version, configuration, reproduction steps, impact and any
available patch or mitigation. Do not open a public issue containing exploit
code, private article data, server credentials, cryptographic keys or complete
production logs.

## Response process

A report is reviewed for reproducibility and impact. Confirmed issues receive a
tracked fix, regression test, release note and coordinated release. Public
details are published after an updated package is available.

## Operational security

Deployment assumptions, key permissions, database privacy, retention and
fail-open/fail-closed controls are documented in
[`docs/SECURITY.md`](docs/SECURITY.md).
