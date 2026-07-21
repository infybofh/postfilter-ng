# Configuration fragments

Files ending in `.toml` are loaded in lexical order after `postfilter.toml`.
Tables are merged recursively and documented rule arrays are appended. Numeric
prefixes expose the load order. Local policy files may use names such as
`90-local-policy.toml`.

An invalid optional rule is disabled and logged. A source generation containing
a critical error is rejected atomically and the last-known-good generation
continues to run.

Rule-like entries may set `article_types = ["text"]` or
`article_types = ["binary"]`. Omit the field to apply a rule to both article
types. Article classification and byte limits belong in the main
`[article_types]` tables.
