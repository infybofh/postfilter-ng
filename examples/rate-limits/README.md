# Rate-limit profiles

Profiles override the default limit for matching identities but cannot exceed the
absolute multipost ceiling.  Use exact matching for account IDs and CIDR for
networks; reserve regex for domain families.

## Example fragment

Copy and adapt `example.toml`; do not replace the main configuration blindly.
