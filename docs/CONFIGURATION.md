# Configuration guide

The authoritative annotated configuration is `conf/postfilter.toml`; rule lists
are under `conf/conf.d/`.  This guide explains the conventions used throughout.

## TOML

Postfilter-NG uses TOML::Tiny rather than a private parser.  Files are loaded in
this order:

1. `postfilter.toml`;
2. sorted `conf.d/*.toml` fragments.

Tables merge recursively.  Rule arrays (`ban_rule`, `badword`,
`trusted_profile`, access/reputation/structural arrays) append in file order.
Duplicate rule IDs disable the duplicate and produce a configuration warning.

## Installed runtime paths

The release tree contains portable source defaults. During installation,
`install-postfilter` writes the selected configuration file and state directory
to `lib/Postfilter/InstallPaths.pm` inside the installed prefix. Both the nnrpd
hook and `postfilterctl` read that module, so layouts discovered by `innconfval`
remain active after the installer exits.

The following environment variables are explicit one-shot overrides:

```text
POSTFILTER_CONFIG
POSTFILTER_STATE_DIR
```

They are not required for a normal installed invocation. The installer removes
them while performing its runtime-user validation, ensuring that generated
installation paths work independently.


## First site-specific settings to review

Before leaving audit mode, review these settings rather than accepting the
example values blindly:

- `[headers].organization` and `force_default_organization`;
- `[new_headers]` for any site-local informational headers;
- `[article_types]`, text/binary limits and Distribution policy;
- trusted/access profiles and local group exceptions;
- logging, saved-article and HTML-report destinations;
- DNS reputation modules and every enabled provider.

Postfilter-NG no longer ships an `X-Complaints-To` header. RFC 5536 defines the
standard `Injection-Info` `mail-complaints-to` parameter and notes that a server
generating `Injection-Info` has no need for the older non-standard complaint
header. With INN, set `complaints` in `inn.conf`; INN then writes the
`mail-complaints-to` value on locally posted articles.

The shipped configuration no longer contains the retired SORBS DNSBL.  It uses
DroneBL for IPv4 clients instead, restricted to conservative high-confidence
return codes.  Experimental/ambiguous classes, open DNS resolvers and abused VPN
services are deliberately not treated as positive listings.  DroneBL currently
publishes its public DNSBL for IPv4 only, so the provider is scoped with
`ip_versions = ["ipv4"]`; providers without `ip_versions` retain the historical
dual-stack lookup behaviour.

`conf/conf.d/40-reputation.toml` also contains disabled examples for Spamhaus
DQS XBL and AuthBL.  They require an operator-specific DQS key and must not be
enabled with the placeholder key.  XBL identifies compromised IPs.  AuthBL is
useful around authenticated services and the example uses `action = "mark"` so
it contributes a signal without automatically rejecting a posting.  Do not use
Spamhaus PBL (or an undifferentiated ZEN result) as an NNTP client-IP blocking
policy: PBL intentionally includes end-user/dynamic address space and is an SMTP
policy dataset rather than evidence that an NNTP user is abusive.

To disable DNS reputation globally, set `rbl = false`, `surbl = false` and
`uribl = false` under `[modules]` (and `tor = false` if TOR DNS checks are not
wanted). To disable only one configured provider, set its `enabled = false`.
`[timeouts].dns_query_seconds` limits one lookup and `dns_total_seconds` limits
the complete per-article DNS work. Provider `on_timeout` and `on_error` decide
whether lookup failure is fail-open (`accept`) or fail-closed (`reject`).

For compatibility with preserved pre-2026.08.1-rc1 configurations, the runtime still
accepts `paths.html_output` as a fallback for `html_report.output_file` and
`keys.database_privacy` as a fallback for `database.privacy.key_file`. New
configuration files should use only the canonical nested settings.

## Regex strings

Prefer literal TOML strings:

```toml
pattern = '(?i)^[^@\s]+@bofh\.team$'
```

Important rules:

- `.` matches any character; write `\.` for a literal dot;
- `^` and `$` anchor the whole normalised value;
- avoid leading/trailing `.*` unless substring matching is intentional;
- use `exact` or `contains` instead of regex when possible;
- test with `postfilterctl rule-test RULE_ID ARTICLE`;
- a bad regex disables only its own rule and logs a precise error.

The historical expression `@bofh.team` was too broad because the dot was not
escaped and the value was unanchored.  A parsed mailbox target is better:

```toml
[[ban_rule]]
id = "block-untrusted-bofh-mailbox"
target = "from.address"
match_type = "regex"
pattern = '(?i)^[^@\s]+@bofh\.team$'
```

## Rule targets

Prefer semantic targets:

- `from.address` — normalised mailbox extracted from From;
- `from.raw` — complete original From value;
- `subject`, `body`, `client.ip`, `client.domain`, `auth.user`;
- `newsgroups`;
- `header.Header-Name`;
- `any.header` with separate name/value patterns.

## Rule actions

- `reject`: return a normal rejection;
- `drop`: request INN's silent `DROP` result in enforce mode;
- `log`: write the configured administrative output;
- `save`: save to the main diagnostic store or a selected external format;
- `score`: add, clear or verify a named score;
- `set_score_limit`: define a per-score threshold;
- `add_metric`: add groups, followups, lines or byte counts to a score;
- `set_article_config`: create a per-article configuration overlay.

Names describe behaviour.  Historical compatibility is recorded by
`legacy_code` only where the old numeric return code must remain searchable.


## Text-only and mixed-reader policy

Article classification happens before trusted profiles and ordinary checks.  The
main selector is:

```toml
[article_types]
mode = "text-only"       # text-only | mixed
pattern_syntax = "glob"  # currently the only supported syntax
mixed_crosspost_policy = "reject"
```

In `text-only` mode every post uses the text profile, even when the group name
looks binary.  This is useful on a conventional text reader that may carry a few
unusual local group names but must never accept yEnc or uuencode.

In `mixed` mode each group in `Newsgroups` is compared with
`binary_group_patterns`:

- all groups match: the article is `binary`;
- no groups match: the article is `text`;
- some match and some do not: compatibility code 95 is returned immediately.

Patterns are shell globs rather than regexes.  For example:

```toml
binary_group_patterns = [
  "alt.binaries.*",  # glob: * means any sequence of characters
  "*.mp3*",
  "*.pictures*",
]
```

Do not write regex escapes in this list.  The glob `alt.binaries.*` is correct;
`^alt\.binaries\.` would be a regex and would not mean what the classifier
expects.

The complete design, shipped defaults and all supplied patterns are explained in
`TEXT-AND-BINARY.md`.

### Independent limits

Each article type overrides the shared compatibility values under `[limits]`:

```toml
[article_types.text.limits]
max_body_size = 32768
max_header_size = 8192
max_total_size = 40960
max_body_scan_bytes = 32768

[article_types.binary.limits]
max_body_size = 10485760
max_header_size = 65536
max_total_size = 10551296
max_body_scan_bytes = 1048576
```

`max_body_scan_bytes` limits work done by expensive regex/URL scanners; it does
not truncate the article and does not replace the absolute body/total limits.
Keeping it lower than the binary body limit prevents every 10 MiB segment from
being scanned repeatedly by text-oriented rules.

### Independent content policy

```toml
[article_types.text.content]
allow_yenc = false
allow_uuencode = false
allow_html = false

[article_types.binary.content]
allow_yenc = true
allow_uuencode = true
allow_html = false
```

Classification is never inferred from these payloads.  A yEnc marker in a text
group is still evaluated by the text profile and rejected, even if the complete
article is smaller than 32 KiB.

### Type-specific skipped checks

A profile may skip checks that have little value for segmented binary payloads:

```toml
[article_types.binary.checks]
skip = [
  "style.line_statistics",
  "style.html",
  "style.content_type",
  "badwords",
  "uribl",
]
```

Structural integrity, group validity, identity, database recording and explicitly
unskipped security checks remain shared.  The text profile should normally have
an empty skip list.

### Rule and provider scope

Rule-like entries are shared by default.  Restrict one with:

```toml
article_types = ["text"]
```

or:

```toml
article_types = ["binary"]
```

The field is accepted by badwords, ban rules, trusted profiles, access profiles,
DNSBL, URIBL/SURBL and applicable structural rules.  Use no field when a rule is
truly common to both worlds.

### Separate diagnostic saving

Text and binary reject saving is independent:

```toml
[article_types.text.save_rejected]
mode = "selected"        # none | all | selected
subdirectory = "text"
reason_codes = ["PF-RULE-201", "PF-BODY-062"]
compatibility_codes = []
rule_ids = []

[article_types.binary.save_rejected]
mode = "none"
subdirectory = "binary"
reason_codes = []
compatibility_codes = []
rule_ids = []
```

`selected` is useful for debugging a single rule without saving every rejected
article.  A saved copy includes `X-Postfilter-Article-Type`; that diagnostic header
is removed from the live article immediately after serialization.

## Trusted profiles

Each configured condition contributes to `match_mode = "all"` or `"any"`.
Profiles may match authenticated users, source CIDRs, From patterns, groups or
specific headers.  `skip_checks` is fully configurable.  `full_bypass` must be
explicit and is discouraged because malformed input can still be an operational
problem even for an administrator.

## Public identity

An undefined or empty nnrpd user is public.  Named values are authenticated
unless they appear in `access.public_user_ids`, which exists for readers.conf
setups that assign a synthetic value such as `anonymous`.  A catch-all regex is
not used.

## Sender and From

Both default to `preserve`.  Transformations are opt-in because these headers
belong to the posted article and may be used for reader identity or mail reply.
Pseudonymisation exists only for installations that deliberately want to hide a
local account exposed by a client.

## Retention

`events`, `rule_hits` and `saved_articles` default to `forever`.  The filter has
no automatic event deletion path.  Use `postfilterctl purge --before ...` first
without `--confirm` to inspect a dry-run, then repeat with explicit confirmation.


## Text MIME and Base64 policy

The complete reference is the commented `[article_types.text.mime]` table in
`conf/postfilter.toml`.  Media-type lists use anchored case-insensitive MIME
globs such as `application/*`; they are not Perl regular expressions.

The strict defaults reject email-style attachments while explicitly preserving
bounded PGP/GnuPG signatures, public keys and certificates.  Tune both
`base64_min_contiguous_lines` and `base64_min_decoded_bytes`: lowering only one
can create false positives in technical groups.  `on_malformed = "accept"` is a
fail-open option for MIME parsing only and does not disable other checks.

## Operational budgets and generation retention

The shipped defaults set both `dns_query_seconds` and `dns_total_seconds` to one
second. Reputation lookups use Net::DNS's background interface and stop at the
first of these deadlines:

- the current provider-query deadline;
- the shared whole-article DNS deadline;
- the remaining article-processing deadline.

The resolver is limited to one attempt. A slow or unreachable provider therefore
cannot inherit the synchronous resolver's multi-retry wall-clock delay. Provider
`on_timeout`/`on_error` policy determines whether that lookup is skipped or
becomes a technical rejection.

`max_processing_ms = 2700` applies to bounded checks and header transformations;
timeout handling defaults to rejection. Context creation, preliminary identity
logging and trusted-profile resolution are measured before the deadline starts.
SQLite event persistence and final logging are measured separately. Level-9
logging emits phase timings, while the final result includes `pipeline_ms` and
`finalization_ms`.

One exhausted processing budget creates one cached `PF-INTERNAL-096` or
`PF-INTERNAL-097` technical result. Later audit/finalisation checks reuse it,
do not emit duplicate timeout warnings and do not run header transformations
after the deadline.

Configuration generations are content-addressed. Identical effective TOML sets
reuse the same generation across nnrpd processes.
`retention.config_generations = 32` keeps the active generation and recent
rollback history; zero disables pruning.
