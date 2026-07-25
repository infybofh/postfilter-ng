# Installer

`install-postfilter` discovers INN paths with `innconfval` or accepts explicit
overrides. It stages and syntax-checks code, pins installed command shebangs to
the current Perl interpreter, generates persistent runtime path defaults,
creates independent keys, preserves operator configuration, installs the
review-only `filter_nnrpd.pl.ng` symlink and never changes the active
`filter_nnrpd.pl` hook.

Configuration validation, SQLite migration and embedded-hook engine construction
execute after dropping irreversibly to the configured INN user and group. These
checks run without temporary path environment variables. Runtime state and
saved-article trees are normalized to that account after initialization.
Configuration and keys remain owned by `root` with the INN group granted read
access.
