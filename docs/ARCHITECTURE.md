# Architecture

## Runtime model

INN loads the active `filter_nnrpd.pl` hook once for each nnrpd process.  The
installer creates `filter_nnrpd.pl.ng`, a symlink to `postfilter`, and leaves the
final rename to the newsmaster.  A client connection may issue multiple POST
commands, so immutable
configuration, the SQLite handle, active-file cache and bounded DNS cache may
survive between articles.  Every POST receives a new `Postfilter::Context`;
scores, verdicts, notes and rule hits never leak to the next article.

## Pipeline

1. inspect configuration generation mtimes and reload only a complete valid set;
2. build the article context and classify every Newsgroups value as text or binary;
3. reject a text/binary mixed crosspost before audit or trusted-profile relaxation;
4. classify public/authenticated identity and apply the effective article-type profile;
5. apply one highest-priority trusted profile;
6. run structural, content, UserDB and reputation checks not skipped by that profile;
7. evaluate type-scoped ban rules and badword scores;
8. query SQLite-backed, optionally type-separated multipost and rate history;
9. run the optional local custom module;
10. perform explicitly configured header transformations;
11. resolve technical verdict, audit policy and per-type diagnostic-save policy;
12. save a diagnostic article under the text or binary tree when requested;
13. write one typed event and its rule hits in one short SQLite transaction;
14. emit one level-1 result line plus any configured diagnostic detail;
15. return empty success text, documented `DROP`, or a rejection reason to INN.


## Text and binary worlds

The classifier uses group-name globs only.  It does not inspect yEnc, uuencode or
MIME to decide which limits apply; otherwise a payload could promote itself into
a more permissive policy.  `text-only` always selects the text world.  `mixed`
selects binary only when every posted group matches the configured binary list.

The context keeps an immutable base configuration plus the effective text or
binary profile.  Shared code obtains limits through `Context::limit` and content
permissions through `Context::content_setting`.  Rules and providers use
`Context::rule_applies_to_article_type`; absence of a scope means shared policy.

Mixed crossposts are rejected before trusted profiles, including full bypass,
and remain rejected in audit.  This is intentional isolation between the two
worlds rather than an ordinary spam-policy verdict.

## Article stages

Tests and CLI distinguish three representations:

- **raw client**: what a newsreader submits; Path may be absent;
- **INN hook stage**: what nnrpd supplies after its own header preparation;
- **offline CLI**: a file that may omit server-generated fields and should still
  produce a useful explanation rather than a misleading blanket failure.

## Configuration resilience

The source TOML set is parsed by TOML::Tiny.  Invalid individual regex entries
are disabled when isolation is safe; a malformed TOML generation is never
activated.  A successful load writes canonical JSON generations and
`last-known-good.json` atomically.  Bad reloads retain the previous in-memory
configuration.  New processes can start from last-known-good, then from a small
embedded fail-open configuration as a final availability measure.

## Persistence and concurrency

SQLite uses WAL, foreign keys, a busy timeout and short transactions. The
installer validates configuration and initializes SQLite after dropping to the
configured INN uid/gid; state and generation files therefore have the same
ownership used at runtime. DNS,
article scanning, report generation and file saving never occur inside a
transaction.  One writer at a time is normal SQLite behaviour; concurrent nnrpd
processes wait according to `busy_timeout_ms` rather than overwriting a flat
file.

Article events and rule hits are permanent by default.  Provider-health rows are
operational telemetry and may be pruned.  Explicit purge operations record who,
when, what cutoff and how many rows were removed.

## Cryptographic separation

Setup generates independent random key files for:

- TOR header reversible encryption;
- HMAC pseudonyms in article headers;
- HTML report privacy;
- database privacy and deterministic hidden lookup values.

Key reuse across purposes is forbidden.  Runtime code never substitutes a known
fallback key.  Reversible values use random-IV encryption plus HMAC
authentication; stable pseudonyms use HMAC-SHA-256.


## Text attachment stage

`Postfilter::Checks::Attachments` is a separate pipeline stage because MIME
attachments and unlabelled Base64 are different from yEnc/uuencode markers.  It
uses the already selected article-type profile: text enables strict inspection,
while binary disables it by default.  The stage is bounded by MIME depth, MIME
part count, body scan bytes and the global article-processing deadline.
