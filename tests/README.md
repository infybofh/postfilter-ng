# Test suite

The suite covers pure Perl behaviour, optional runtime integrations, schema
checks, realistic article fixtures and concurrent SQLite writers.

Test groups:

- `00-compile.t` — production module compilation and INN entry-point validation.
- `01-codes.t` — symbolic and numeric result-code mappings.
- `02`–`04` — raw-client and INN-hook input, public/auth identities and custom
  error policy.
- `05`–`11` — content, rules, saved articles, configuration isolation,
  dependency degradation, header policy, audit, `DROP` and deadlines.
- `12-crypto-and-installer.t` — key generation and installer safeguards.
- `13-schema-retention.t` — permanent audit history and administrative actions.
- `14-directories-and-docs.t` — documented package directories.
- `15-comments-and-style.t` — function documentation and source formatting.
- `16-article-types.t` — text-only/mixed classification, binary globs, codes
  95–102, independent limits, scoped rules and save policy.
- `17-sqlite-concurrency.t` — sixteen SQLite writers and 1,600 event
  transactions against migrations 001–004.
- `18-text-attachments.t` — MIME, Base64, PGP/GnuPG, malformed MIME, empty part
  headers, byte-preserving signed content and linear adversarial armour scans.
- `19-live-deployment-regressions.t` — embedded-Perl hook loading, INN-compatible
  header deletion, runtime ownership initialization and database diagnostics.
- `20-operational-hardening.t` — stable generation reuse/retention, delayed budget
  start, phase timing, TOR-header observability and irreversible privilege drop.
- `21-portability-and-dns-deadlines.t` — portable source shebangs,
  installer-generated runtime paths, asynchronous hard DNS deadlines and
  single-shot processing-timeout reporting.
- `25-julien-feedback.t` — PATH-only `innconfval` discovery, locale-independent
  article dates, audit-mode header finalisation, canonical shipped config and
  retired-provider cleanup.

`sqlite-concurrency.py` uses Python's standard `sqlite3` module for WAL and
schema stress. Repeat load testing through Perl DBI/DBD::SQLite on the target INN
reader before production enforcement.

Fixtures under `examples/minimal-reader`, `examples/mixed-reader` and
`examples/text-mime-strict` distinguish raw client input, INN hook input, text
payload rejection, binary payload acceptance and mixed-crosspost rejection.
- `22-installer-upgrade-paths.t` — exact historical-path migration, timestamped
  backups, custom-path preservation, path-adjusted `.dist` snapshots and failed
  upgrade diagnostics.

- `23-release-layout-and-cleanup.t` — immutable release markers, regular wrappers, managed-path containment, GitHub Web source modes and cleanup gates.

- `24-runtime-path-bootstrap.t` — executable direct/symlink path bootstrap and explicit candidate-validation paths.

## Privileges and locale

The Perl regression suite does not require root and should pass when run as the
INN account, for example `su -m news -c 'sh tests/run-tests'` where supported.
Realistic Date-header fixtures are generated with fixed English RFC tokens and
do not depend on the account's `LC_TIME`. Root-only success is therefore a test
regression and should be reported rather than documented as a requirement.
