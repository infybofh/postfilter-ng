# Configuration examples

Each subdirectory contains one focused configuration scenario. The installer
does not copy these examples. Read the local README, compare the fragment with
`conf/postfilter.toml`, and copy the required tables into a file under `conf.d/`.

Regular expressions use Perl syntax. TOML literal strings (`'...'`) preserve
backslashes. Binary-group classification uses shell-style globs rather than Perl
regular expressions.

Validate copied fragments with:

```sh
postfilterctl check-config
postfilterctl rule-test
postfilterctl test-article
```

## Deployment examples

- `strict-text-only/` — 32 KiB text policy with yEnc and uuencode disabled.
- `text-mime-strict/` — MIME and Base64 policy with bounded PGP/GnuPG exceptions.
- `mixed-reader/` — independent text and binary limits, checks and save policy.
- `public-reader/` — unauthenticated public-reader limits.
- `authenticated-reader/` — authenticated-reader limits.
- `mixed-access-reader/` — public and authenticated identities on one reader.
- `audit-rollout/` — `would_reject` collection without ordinary enforcement.

## Policy examples

- `trusted-administrators/` — selective administrator bypass profiles.
- `rate-limits/` — public, domain and authenticated quotas.
- `badwords/` — exact, contains and regex content rules.
- `banlist/` — actions, score variables and sender-address regexes.
- `tor-encrypted-header/` — reversible administrator-only TOR identity token.
- `userdb/` — per-group authorised sender database.
- `custom-filter/` — local Perl extension and error policy.
- `html-report/` — static privacy-aware report generation.

Operational examples include `bofh.team` administrator identities,
`miakibot@miakinen.net`, local TOR networks and Steve Carroll sender variants.
Incorrect regex forms appear only in comments with corrected replacements.

## Companion Cleanfeed-NG hooks

- `cleanfeed-local-hooks/` — complete audit-first `cleanfeed.local` functions,
  adapted historical signatures and a modern composite spam example. These are
  copied manually into Cleanfeed-NG and are not loaded by Postfilter-NG.
