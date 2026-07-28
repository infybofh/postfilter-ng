# Changelog

## 2026.07.5-rc7 — 2026-07-28

FreeBSD candidate-validation regression fix after the external rc6 upgrade report.

- passes the installer-resolved `--config` and `--state-dir` paths to every
  `postfilterctl` candidate check, including the post-generation `check-config`
  and `db-check` calls that previously fell back to Linux defaults;
- keeps an independent clean-process verification of the generated
  `Postfilter::InstallPaths` module without making installation success depend
  on implicit path discovery in a second executable;
- resolves the `postfilterctl` release library from the real path of `__FILE__`
  instead of `FindBin`, including when the command is invoked through the
  installer-managed `/usr/local/sbin/postfilterctl` symlink;
- adds a lightweight `postfilterctl install-paths` diagnostic that requires no
  optional runtime modules and prints the loaded module, configuration and state
  paths;
- adds an executable regression test for direct and symlinked administration
  commands with FreeBSD-style `/usr/local/news` paths, and rejects any return to
  `/etc/news` or `/var/lib/news`;
- fixes the duplicated `runtime_config` argument in the installer plan output.

## 2026.07.5-rc6 — 2026-07-27

Immutable release deployment, explicit hook activation and guarded cleanup from
the first external FreeBSD rc5 deployment report.

- installs code into immutable `<prefix>/releases/<version>` directories instead
  of replacing the mutable base prefix;
- creates regular, version-pinned `filter_nnrpd.pl.ng` wrappers that work when
  loaded with Perl `do` and do not depend on a symlink or executable source mode;
- leaves the active `filter_nnrpd.pl` and its currently loaded flat release
  untouched during candidate installation;
- snapshots any recognised rc1–rc5 or otherwise versioned flat installation,
  preserving local modifications rather than reconstructing a theoretical
  release from the repository;
- validates legacy snapshots as rollback targets and disables automatic legacy
  cleanup when validation fails;
- adds explicit `--activate-candidate` and `--rollback` transactions with atomic
  hook replacement and automatic restoration on validation failure;
- verifies that active and rollback wrappers load `Postfilter::NG` and
  `Postfilter::InstallPaths` from the exact managed release directory and that
  the runtime version matches the wrapper metadata;
- records active, candidate and previous release state and maintains `current`
  and `previous` links only after successful activation;
- retains the active and at least one validated rollback release;
- removes the old flat prefix, obsolete managed releases and stale installer
  artifacts only after the active hook is verified as the latest installed
  release and a rollback wrapper is available;
- refuses cleanup when the active hook is older, unrecognised, outside the
  managed release root or unable to construct the engine;
- refuses uninstall while the active hook still depends on code below the
  prefix;
- documents `perl installer/install-postfilter` and `sh tests/run-tests` so
  repositories uploaded through GitHub Web remain usable without Git executable
  modes;
- adds release-marker, regular-wrapper, path-containment, source-mode and cleanup
  gate regression tests.

## 2026.07.5-rc5 — 2026-07-27

Non-destructive FreeBSD upgrade migration and installer self-diagnostics from
the first external rc4 upgrade report.

- validates the generated `Postfilter::InstallPaths` module in a clean new Perl
  process and prints the exact module, configuration and state paths loaded;
- clears inherited `PERL5LIB`, `PERLLIB`, `PERL5OPT` and Perl build variables
  during dependency, compile and runtime verification so an older site-local
  module cannot shadow the activated prefix;
- performs bootstrap `check-config` and `db-migrate` with explicit detected
  paths, then repeats validation and `db-check` without any path override;
- migrates only exact historical Linux path defaults in preserved TOML files,
  leaving genuinely custom paths unchanged;
- creates timestamped backups before changing operator configuration and writes
  path-adjusted `*.dist` files for manual comparison with the current release;
- preserves a failed activated code tree as `<prefix>.failed.<timestamp>.<pid>`
  before restoring the previous prefix, so generated paths and loaded modules
  remain available for diagnosis;
- adds functional regression tests for exact path migration, backup creation,
  custom-path preservation, distribution snapshots and repeated upgrades;

## 2026.07.5-rc4 — 2026-07-25

FreeBSD portability, persistent installer paths and hard DNS deadlines from the
first external deployment report.

- persists the installer-selected configuration file and state directory in an
  installed `Postfilter::InstallPaths` module used by both the nnrpd hook and
  `postfilterctl`;
- validates the generated runtime paths without environment variables or
  command-line path overrides;
- verifies the staged hook by loading it through `do` with an nnrpd-like `$0`
  and constructing the engine before activation;
- uses portable `#!/usr/bin/env perl` source shebangs and rewrites installed
  commands to the exact absolute Perl interpreter that ran the installer;
- performs DNS reputation queries through `bgsend`/`bgbusy`/`bgread` rather
  than the synchronous multi-retry API;
- applies the smaller of the per-query DNS limit, whole-article DNS limit and
  remaining article-processing budget as a hard wall-clock deadline;
- limits resolver retries to one and keeps the shipped total DNS budget at one
  second;
- records an exhausted article-processing budget once, reuses the first
  technical timeout result during audit finalisation and skips later header
  transformations after timeout;
- documents the intentional `root:<news-group>` read-only ownership of
  configuration and keys, with `news:news` ownership reserved for mutable state
  and saved articles;
- adds portability, generated-path, asynchronous-DNS and single-timeout
  regression tests.

## 2026.07.5-rc3 — 2026-07-24

Operational hardening from the first full day of live RC2 traffic.

- reuses a content-derived configuration generation across identical nnrpd processes;
- retains the current plus 31 historical configuration generations by default;
- avoids rewriting unchanged generation and last-known-good snapshots;
- caps both per-query and whole-article DNS reputation work at one second;
- sets the bounded check/header budget to 2700 ms and fails closed on timeout;
- starts that budget after context creation, identity logging and trusted-profile resolution;
- adds timings for configuration, context, trusted profile, pipeline, headers, SQLite event and finalization;
- adds `pipeline_ms` and `finalization_ms` to the final structured result;
- logs TOR header creation without exposing its value;
- drops installer real, effective and saved IDs with `POSIX::setgid`/`setuid`;
- adds regressions for generation reuse, pruning, timing boundaries and TOR observability.

## 2026.07.5-rc2 — 2026-07-21

Second release candidate with corrections verified during live deployment on an
INN reader.

### INN embedded-Perl loading

- resolves the installed module directory from `__FILE__` and the active hook
  symlink instead of relying on `$0`/`FindBin`;
- adds a regression test that loads the hook through `do` with `$0` set to the
  `nnrpd` executable path;
- documents a standalone pre-activation hook-load command;
- clarifies that `ctlinnd reload filter.perl` reloads the `innd` filter and does
  not reload `filter_nnrpd.pl` in existing reader processes.

### Runtime ownership and database diagnostics

- runs installer `check-config` and `db-migrate` commands after dropping to the
  configured INN user and group;
- recursively normalizes state and saved-article ownership after initialization,
  repairing files created by earlier installers as `root`;
- applies `0750/0640` modes to runtime state and saved articles;
- makes administrative commands request an explicit SQLite handle and report a
  clear error when the effective configuration disables the database;
- prevents `db-check` and related commands from calling DBI methods on `undef`.

### Header modification compatibility

- marks deleted nnrpd headers with `undef`, as documented by INN, instead of
  deleting hash keys;
- omits headers marked for deletion from saved/offline article serialization;
- adds live-deployment regressions for Sender removal and temporary diagnostic
  headers.

## 2026.07.5-rc1 — 2026-07-21

First release candidate. The feature set is frozen for staging, audit replay and
production-like validation.

### MIME and ASCII-armour hardening

- replaces the body-wide non-greedy ASCII-armour regex with a single-pass,
  line-oriented state machine;
- bounds incomplete and oversized armour handling without rescanning previous
  bytes;
- accepts MIME part headers with an empty field value;
- preserves `multipart/signed` bodies byte-for-byte during inspection;
- adds adversarial tests with 40,000 unterminated armour markers;
- documents the `armored_block_max_bytes` ceiling and oversized-block behavior.

### GitHub publication

- adds the project banner, release and runtime badges, repository metadata and
  Calendar Versioning reference;
- adds GitHub Actions testing, issue forms, pull-request template and code
  ownership metadata;
- adds contribution and security-reporting policies;
- removes internal build reports, generated inventory tables and release-gate
  artifacts from the public package;
- limits `SHA256SUMS` to source, executable, test and migration code.

### Installation safety and public examples

- removes the repository-root `filter_nnrpd.pl` link from the source package;
- stages `filter_nnrpd.pl.ng` without changing the active INN hook;
- prints explicit newsmaster activation and rollback instructions;
- replaces unprofessional abuse-rule responses with neutral policy messages;
- removes the redundant narrow Steve Carroll rule and retains the normalized
  variant-matching rule.

### Documentation

- updates operator documentation for release-candidate status;
- consolidates migration instructions and the Postfilter 0.9.x parameter map;
- rewrites README files as direct operational descriptions;
- updates package metadata for Perl 5.38+, INN 2.x and the GitHub repository.

## 2026.07.4-alpha4 — 2026-07-21

Fourth alpha.  This release makes the text article policy strict against
email-style and disguised attachments without treating normal cryptographic
material as binary abuse.

### MIME attachment policy

- adds `Postfilter::Checks::Attachments` as a dedicated profile-aware pipeline
  stage;
- rejects `multipart/mixed` in text groups with `PF-MIME-109`;
- rejects forbidden MIME media types such as `application/*`, images, audio,
  video, fonts and attached `message/rfc822` with `PF-MIME-110`;
- rejects `Content-Disposition: attachment`, filename-bearing inline parts and
  historical `Content-Type; name=` attachment metadata with `PF-MIME-111`;
- rejects unapproved multipart containers with `PF-MIME-114`;
- handles malformed boundaries, part headers, depth and part-count overflow
  through configurable fail-open/fail-closed policy (`PF-MIME-113` by default);
- leaves the binary profile independent and disabled for these strict checks by
  default.

### PGP/GnuPG and certificate protection

- allows configurable `multipart/signed` and `multipart/alternative`
  containers to reach recursive MIME validation;
- allows an explicit, size-bounded list of PGP/S/MIME signature, public-key and
  certificate media types;
- permits attachment-style disposition metadata only for those explicitly
  allowed cryptographic media types;
- removes bounded configured ASCII-armoured PGP/GnuPG/key/certificate blocks
  before Base64 heuristics;
- prevents media-type spoofing from becoming a bypass by enforcing independent
  decoded-size ceilings.

### Base64 attachment heuristic

- adds `PF-BODY-112` for long unlabelled Base64 runs in text articles;
- requires both a configurable contiguous-line threshold and a configurable
  estimated decoded-byte threshold;
- ignores quoted Base64 examples by default and makes indented-example handling
  configurable;
- accepts short technical examples, ordinary signatures and certificates under
  their documented limits;
- uses the existing per-type expensive-scan byte budget to bound work.

### Documentation and tests

- documents every MIME and Base64 setting directly in the main TOML file;
- adds a complete strict-text MIME example with accepted and rejected article
  fixtures;
- adds dedicated error-code documentation for 109–114;
- adds release tests for multipart, application media, attachment metadata,
  raw Base64, PGP/MIME, ASCII armour, malformed MIME and binary-profile
  separation.

## 2026.07.3-alpha3 — 2026-07-21

Third alpha.  This release adds first-class separation between the text and
binary worlds of a modern mixed INN reader.  It deliberately does not offer a
"binary-only" server mode: operators may run either a strict text-only reader
or a mixed reader that carries both text and binary hierarchies.

### Article classification and policy

- adds the early `Postfilter::ArticleType` classification stage;
- supports `article_types.mode = "text-only"` and `"mixed"`;
- classifies by configurable, case-insensitive shell globs applied to every
  group in `Newsgroups`;
- rejects direct crossposts between text and binary groups before trusted
  profiles, audit relaxation or content checks;
- records the article type and matching text/binary groups in the article
  context, SQLite event, logs and diagnostic saved copy;
- adds optional `article_types = ["text"]` or `["binary"]` scope to rules,
  access profiles, trusted profiles and reputation providers.

### Independent text and binary limits

- adds separate body, header, total-size and expensive-scan limits for text and
  binary articles;
- adds compatibility codes 95 through 103 for mixed crossposts and type-specific
  size failures;
- permits binary articles to skip text-oriented checks such as blank-line ratio,
  quoted-line ratio, HTML heuristics, badwords and URI reputation checks;
- preserves strict yEnc/uuencode rejection in text groups even when the payload
  is smaller than the text article limit;
- keeps binary content permissions and scan budgets independently configurable;
- optionally separates SQLite rate-limit counters by article type.

### Diagnostic storage and reporting

- adds independent reject-save policy for text and binary articles;
- each world supports `none`, `all` or `selected` saving by symbolic reason,
  numeric compatibility code or rule ID;
- stores text and binary diagnostic articles below separate configurable
  directory trees;
- adds `X-Postfilter-Article-Type` only to saved diagnostic copies;
- adds article-type filters to `postfilterctl query` and type-separated
  statistics to `postfilterctl stats` and the HTML report;
- adds SQLite schema migration 004 and indexes article type with event time.

### Documentation and tests

- adds `docs/TEXT-AND-BINARY.md` as the complete operator guide;
- adds a realistic mixed-reader example with accepted binary yEnc, rejected
  text yEnc and rejected mixed-crosspost fixtures;
- documents every shipped binary-group glob and the distinction between glob
  syntax and Perl regular expressions;
- adds release tests for classification, size codes, content policy, rule scope,
  save selection, schema changes and report/query separation.

## 2026.07.2-alpha2 — 2026-07-20

Second alpha and complete internal review of the clean rewrite.

### Correctness

- accepts an absent incoming `Path` while still rejecting malformed supplied
  values;
- classifies empty/undefined users as public and named users as authenticated;
- supports explicit public synthetic user IDs without the unsafe `.+` default;
- fixes custom-filter `on_error` precedence and missing-module handling;
- treats a missing Date::Parse module as a runtime capability failure;
- separates default and absolute multipost limits;
- applies whole-article and whole-DNS deadlines;
- applies `max_body_scan_bytes` to expensive scanners;
- fixes privacy lookup keys used by SQLite rate-limit queries;
- compares configuration generation IDs rather than numeric reference values.

### Security and privacy

- removes every hard-coded emergency key/salt;
- creates four independent 512-bit key files from `/dev/urandom` during every
  fresh setup, whether or not their features are enabled;
- preserves existing keys on upgrades;
- renames reversible `sha256` modes to `encrypted`; old spellings are accepted
  only as deprecated aliases;
- preserves `Sender` and `From` by default;
- makes database identity storage policy explicit;
- retains legal/audit history forever by default and permits deletion only via
  an explicit audited command.

### Maintainability

- removes the private TOML parser in favour of TOML::Tiny;
- expands compressed one-line code and documents modules/functions;
- adds per-directory documentation and removes unexplained empty directories;
- replaces historical-origin action names with functional names;
- adds extensive deployment, regex, banlist, badword and trusted-profile
  examples based on the operational Postfilter-NG rules;
- adds style configuration for perltidy and Perl::Critic.

### Testing

- adds separate raw-client, INN-hook-stage and offline CLI fixtures;
- covers absent Path, anonymous users, authenticated users, synthetic public IDs,
  custom fail-open/fail-closed, DROP, deadlines, key creation and retention;
- validates every TOML file with a standard parser during release validation;
- retains the full historical function and parameter coverage checks.

## 2026.07.1-alpha1 — 2026-07-19

Initial architectural rewrite introducing per-article state, SQLite WAL,
symbolic plus numeric historical codes, trusted profiles, audit mode,
last-known-good configuration, DNS reputation modules, encrypted TOR markers,
`postfilterctl`, a static HTML report and a portable installer.

Alpha1 is retained only as an architectural milestone.  It must not be deployed.
