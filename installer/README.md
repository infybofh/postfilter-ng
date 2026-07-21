# Installer

`install-postfilter` discovers INN paths with `innconfval` or accepts explicit
overrides. It stages and syntax-checks code, creates independent keys, preserves
operator configuration, installs the review-only `filter_nnrpd.pl.ng` symlink
and never changes the active `filter_nnrpd.pl` hook.

Configuration validation and SQLite migration execute after dropping to the
configured INN user and group. Runtime state and saved-article trees are
normalized to that account after initialization. Configuration and keys remain
owned by `root` with the INN group granted read access.
