# Security and privacy

## Threat boundaries

Postfilter-NG processes attacker-controlled headers and body text inside nnrpd.
Configuration and code must therefore remain writable only by trusted
administrators.  SQLite, keys and saved articles are private operational data,
not public report content.

## Keys

The installer creates every key on every fresh installation, irrespective of
whether the feature is enabled.  Each file contains 64 bytes read completely
from `/dev/urandom`, is created with exclusive semantics and mode 0640, and is
owned by the configured administrator/news group.  Upgrades never overwrite an
existing key.  Runtime code does not invent keys or fall back to a source-known
constant.

## Reversible encryption

The public mode name is `encrypted`.  Deprecated spellings `sha256` and `crypt`
are accepted only to help migration and emit a warning.  Reversible tokens are
not hashes: they use AES encryption with a random IV and HMAC-SHA-256
authentication with purpose-separated derived keys.

## Database privacy

The default `plain` mode intentionally stores IP, account ID, From address and
Message-ID in the private database because direct long-term legal/audit lookup
is an operational requirement.  Protect the database with filesystem access,
backups and host security.  `hmac` and `encrypted` modes are optional for sites
with different requirements.  Hidden deterministic lookup columns keep rate
limits queryable without exposing plaintext indexes.

## Retention

No article event or rule hit is automatically deleted.  Explicit purges are
administrative actions and are themselves recorded.  Operators remain
responsible for applicable law, policy, access control and backup retention.

## External services

DNS reputation failures are differentiated from positive listings.  Refused
codes, SERVFAIL/timeouts and provider cooldowns cannot silently become listings.
Both per-query and per-article DNS budgets prevent an external provider from
holding an nnrpd POST indefinitely.

## Local custom code

`custom.pm` is executable Perl by design and therefore must be administrator
owned.  It is the sole executable configuration extension; TOML files are data.
The configured `on_error` policy controls missing files and exceptions.

## Long-term identity storage and privacy-mode changes

The default SQLite policy is `plain` because the database replaces the private
`legal.log` and is intended for exact long-term administrative queries.  Operators
may choose `hmac` or `encrypted`; every row records its `identity_storage_mode`.
Stable secret-key lookup columns are independent from the display storage mode,
so equality searches and rate limits continue to work after a mode change.

`postfilterctl query --ip` and `--user` calculate the hidden lookup token.  Query
output decrypts authenticated `encrypted` values locally; HMAC values cannot be
reversed by design.  `postfilterctl export --reveal-identities` performs the same
local decryption and should be used only when the destination is protected.

## Text/binary isolation

The article type is derived only from the complete `Newsgroups` list.  Payload
markers cannot select the more permissive binary profile.  A crosspost spanning
both worlds is rejected before trusted profiles and remains enforced during
audit; otherwise one binary group could raise limits or enable yEnc for a text
group.

Binary diagnostic saving is disabled by default because a small number of
multi-megabyte rejects can exhaust a filesystem.  Type-specific `selected` mode
is preferred for investigations.  Text and binary files are stored in distinct
trees, and their metadata remains separately typed in SQLite even if an event is
later removed by an explicit administrative purge.

## File ownership

- installed code and documentation: `root:root`, read-only to the runtime;
- configuration and keys: `root:news`, directories `0750`, files `0640`;
- SQLite, configuration generations and saved articles: `news:news`,
  directories `0750`, files `0640`;
- generated public HTML: runtime account ownership with web-readable modes.

The installer performs configuration validation and database migration as the
configured INN account, then normalizes runtime ownership recursively.
