# Strict text-only reader

Every article uses the text policy.  The example enforces a 32 KiB body limit,
rejects yEnc and uuencode regardless of their size, and runs all text-oriented
checks.

A binary-looking group name does not enable binary permissions in this mode.
This is useful for text archives or readers that happen to carry a group whose
name contains `bin` but do not accept binary payloads.

The example saves only yEnc/uuencode rejects under the `text/` diagnostic tree.
SQLite still records every event indefinitely.
