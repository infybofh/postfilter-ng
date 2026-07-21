# Documentation

This directory contains the operator and maintainer documentation shipped with
Postfilter-NG.

- `INSTALL.md` — installation, upgrade, rollback and path overrides.
- `CONFIGURATION.md` — configuration loading, validation and policy structure.
- `TEXT-AND-BINARY.md` — article classification, type-specific limits and mixed
  reader operation.
- `TEXT-MIME-ATTACHMENTS.md` — MIME, Base64, PGP/GnuPG and certificate policy.
- `ERROR-CODES.md` — symbolic and numeric result codes.
- `FUNCTION-REFERENCE.md` — documented production functions.
- `MIGRATION.md` — migration from Postfilter 0.9.x configurations.
- `ARCHITECTURE.md` — nnrpd process model and filter pipeline.
- `SECURITY.md` — keys, identity storage, retention and threat boundaries.
- `postfilter-ng-banner.png` — GitHub repository banner, 1280×640 PNG.

Documentation and installed code are read-only at runtime and may remain
`root:root`. Runtime state and saved articles use the configured INN account;
configuration and keys normally use `root:news`.
