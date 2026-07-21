# Encrypted TOR marker

All TOR nodes (not only exits) are detected.  `encrypted` produces a random-IV,
authenticated reversible token.  Only the administrator holding the generated
TOR key can decode it with `postfilterctl tor-decode`.

## Example fragment

Copy and adapt `example.toml`; do not replace the main configuration blindly.
