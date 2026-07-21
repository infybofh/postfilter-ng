# SQLite migrations

These SQL files document the persistent schema. The Perl migration code mirrors
them and records applied versions in `schema_migrations`.

Apply migrations in numerical order.

## 001-initial.sql

Creates the event, rule-hit, saved-article, local-distribution,
provider-health, configuration-generation and administrative-action tables.

## 002-alpha2-identity-lookups.sql

Adds deterministic lookup columns for indexed administrative queries and
rate-limit accounting when display values use HMAC protection or encryption.

## 003-identity-storage-mode.sql

Adds `identity_storage_mode` to every event. Each row records the privacy mode
used when the event was written.

## 004-article-types.sql

Adds `article_type` (`text` or `binary`) to events and saved diagnostic articles.
It creates composite article-type/time indexes. Rows created before article-type
classification receive `text` during migration.
