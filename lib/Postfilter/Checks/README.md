# Filtering check modules

Each module in this directory owns one bounded portion of the article pipeline:
structural/style validation, content scanning, rules, access/rate history,
reputation services and per-group sender databases.  A check receives one
`Postfilter::Context` and returns one `Postfilter::Result`; it must not retain
article-specific state in package globals.


- `Attachments.pm` — recursive MIME/attachment policy and bounded Base64
  heuristic.  It is strict for text articles and disabled for binary articles
  by default, with explicit bounded exceptions for PGP/GnuPG and certificates.
