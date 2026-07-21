# Minimal audit reader

This is the smallest useful deployment.  It runs structural checks in audit,
disables external DNS reputation checks and preserves every identity header.
Use it to verify hook integration before enabling policy modules.

## Example fragment

Copy and adapt `example.toml`; do not replace the main configuration blindly.
