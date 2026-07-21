# Public reader

A public reader identifies anonymous posts by an empty nnrpd user value and
applies IP/domain limits.  Do not use `public_user_pattern = ".+"`: it reverses
the meaning of public and authenticated identities.  List only synthetic IDs
actually assigned by readers.conf.

## Example fragment

Copy and adapt `example.toml`; do not replace the main configuration blindly.
