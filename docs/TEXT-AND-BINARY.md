# Text and binary article policies

Postfilter-NG 2026.07.5-rc6 classifies articles before policy checks. A single
INN reader can apply independent limits and content rules to discussion traffic
and multi-megabyte binary segments.

## Supported server modes

### `text-only`

Every article uses `article_types.text`, regardless of group name.  This mode is
for discussion readers and text archives.  The default text content policy rejects
yEnc and uuencode even when the payload is smaller than the configured byte limit.

Supported modes are `text-only` and `mixed`. Mixed mode applies the binary
profile only when every group matches a configured binary pattern.

### `mixed`

Each `Newsgroups` entry is matched against `binary_group_patterns` before trusted
profiles or ordinary checks run:

- all groups match: `article_type = binary`;
- no group matches: `article_type = text`;
- at least one of each: compatibility code 95 / `PF-GROUP-095`.

Code 95 is enforced even while the rest of the filter runs in audit mode.  This
prevents a binary group from raising the allowed size or enabling yEnc for a text
group in the same crosspost.

## Binary group pattern language

Patterns are case-insensitive shell-style globs anchored to the entire group:

- `*` matches zero or more characters;
- `?` matches one character;
- dots and other regex characters are literal.

Examples:

| Glob | Matches | Does not match |
|---|---|---|
| `alt.binaries.*` | `alt.binaries.example` | `free.alt.binaries.example` |
| `*.pictures*` | `free.pictures.test` | `pictures.test` |
| `*music.bin*` | `free.music.binary` | `free.music.audio` |
| `*.bin*` | `free.binary.test` | `binary.test` when no dot precedes `bin` |

The release configuration contains the complete historical list supplied by the
newsmaster and may be changed without touching the source.

## Independent limits

Every key accepted in shared `[limits]` may be overridden under:

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

Omitted keys inherit the shared value.  This allows only byte limits to differ,
or permits completely different crosspost, line, URL and rule-evaluation limits
when a newsmaster needs that separation.

Size rejections have distinct codes:

| Type | Body | Headers | Total |
|---|---:|---:|---:|
| text | 96 | 97 | 98 |
| binary | 99 | 100 | 101 |

The older generic codes remain available for old rules and historical queries,
but the built-in size checks use the type-specific values.

## Independent content policy

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

Classification is group-based.  A yEnc body in a text group therefore remains a
text article and is rejected with code 62.  A plain text body in a binary group
uses binary limits and policy but does not need to contain an attachment.  If a
newsmaster explicitly disables yEnc or uuencode in the binary profile, a matching
binary article is rejected with type-policy code 102.

## Strict MIME attachment policy in the text world

The attachment stage runs after structural validation and before yEnc/uuencode
checks. It is enabled by default for text articles and disabled by default for
binary articles.

The text profile can independently reject:

- `multipart/mixed`, the normal email-style attachment container;
- `Content-Disposition: attachment`;
- `inline` parts carrying `filename=` and `Content-Type; name=` metadata;
- `application/*`, `image/*`, `audio/*`, `video/*`, fonts, models and attached
  `message/rfc822` parts;
- multipart subtypes not explicitly allowed;
- malformed MIME boundaries and headers;
- long unlabelled Base64 runs which satisfy both line-count and decoded-size
  thresholds.

The default PGP/GnuPG policy allows `multipart/signed`, common PGP/S/MIME
signature, key and certificate media types, and configured ASCII-armoured
blocks. Each exception has an independent size ceiling.

The Base64 heuristic ignores quoted examples by default and accepts short
examples below the configured thresholds. Indented examples remain inspectable
unless `base64_ignore_indented_lines` is enabled.

See `docs/TEXT-MIME-ATTACHMENTS.md` and the fully commented
`[article_types.text.mime]` table in `conf/postfilter.toml`.

## Skipping text-oriented checks for binary segments

Each world has a check skip list.  Pipeline check names include:

- `style`, `binary`, `userdb`, `tor`, `rbl`, `uribl`, `banlist`, `badwords`,
  `rate_limit`, `custom`, `headers`;
- fine-grained style checks: `style.line_statistics`, `style.html`,
  `style.content_type`.

The default binary profile skips line/quote ratios, HTML scanning, MIME content
policy, badwords and URI DNS lists.  Structural group/date/header checks, access
control, IP reputation, ban rules and custom policy remain active unless the
newsmaster explicitly skips them.

## Shared and type-scoped rules

Rule/provider entries are shared when `article_types` is absent.  Add a scope to
run one entry only in one world:

```toml
[[badword]]
id = "text-pharmaceutical-spam"
article_types = ["text"]
pattern = '(?i)cheap\s+viagra'
targets = ["subject", "body"]
action = "reject"

[[ban_rule]]
id = "binary-segment-name-policy"
article_types = ["binary"]
target = "subject"
match_type = "contains"
pattern = "forbidden-release-name"
action = "reject"
```

The same scope is supported by trusted profiles, access profiles, DNSBL/URIBL/
SURBL providers, content-type rules, forbidden-crosspost rules and forbidden
header rules.

## Separate rate counters

`access.separate_counters_by_article_type = true` is the default.  Rate snapshots
and multipost counts then query only events of the current type.  A 10 MiB binary
segment cannot consume the byte allowance intended for text posts.

Article-type-scoped access profiles can define different quotas.  Set the option
to false only when one combined user quota is intentionally desired.

## Independent rejected-article saving

Each world has its own save policy and subdirectory:

```toml
[article_types.text.save_rejected]
mode = "selected"
reason_codes = ["PF-BODY-052", "PF-BODY-062"]
compatibility_codes = []
rule_ids = []
subdirectory = "text"

[article_types.binary.save_rejected]
mode = "none"
reason_codes = []
compatibility_codes = []
rule_ids = []
subdirectory = "binary"
```

Modes:

- `none`: do not save automatically;
- `all`: save every technical reject of that type;
- `selected`: save when symbolic code, numeric compatibility code or rule ID
  matches one selector.

A rule-level `save_article = true` and global policy action `save` still override
these settings.  The recommended global action is `reject`, leaving the
per-type policies in control.

Files are stored below separate trees while retaining the approved filename:

```text
.../rejected/text/2026/07/21/1784488123.483921.PF-BODY-062.hash.post
.../rejected/binary/2026/07/21/1784488124.123456.PF-BODY-099.hash.post
```

## SQLite and reports

Every event contains an indexed `article_type` column.  Rate limiting, CLI
queries, statistics and the HTML report can therefore distinguish text and
binary traffic throughout a multi-year legal archive.

Useful commands:

```sh
postfilterctl stats 24
postfilterctl query --article-type text --reason PF-BODY-062
postfilterctl query --article-type binary --reason PF-BODY-099
postfilterctl report-generate
```

## Administrative queries

Article type is a first-class SQLite field rather than an inference from current
group patterns.  Historical queries remain correct even after the pattern list is
changed:

```sh
postfilterctl stats 24
postfilterctl query --article-type text --limit 100
postfilterctl query --article-type binary --reason PF-BODY-099
postfilterctl saved-list --article-type text --limit 50
postfilterctl saved-list --article-type binary --limit 10
```

The static HTML report contains separate cards and a text/binary activity table.
Rejection reasons include their article type, so the same shared rule can be
measured independently in each world.
