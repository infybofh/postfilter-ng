# Installer

Run the source installer explicitly through Perl:

```sh
perl installer/install-postfilter --help
```

This is intentional: repositories populated through GitHub's web interface may
lose executable file modes. Installed command copies receive an absolute Perl
shebang and mode `0755`.

Rc6 installs immutable trees below `<prefix>/releases/<version>`. It creates a
regular, version-pinned `filter_nnrpd.pl.ng` wrapper and never changes the active
`filter_nnrpd.pl` during candidate installation.

On upgrade from any pre-rc6 flat installation, the exact installed tree is copied
to a managed legacy snapshot without moving or deleting the active files. The
snapshot is loaded and classified as a valid or unavailable rollback target.

Activation is explicit:

```sh
perl installer/install-postfilter --activate-candidate
```

It validates the candidate, creates a rollback wrapper, atomically replaces the
active hook, verifies the exact modules and runtime version loaded, updates
`current`/`previous`, and only then runs guarded cleanup.

Cleanup retains at least the active and previous releases. It removes the legacy
flat prefix, obsolete managed releases and stale installer artifacts only when
the active hook is verified as the latest installed release and a working
rollback wrapper exists. Otherwise no files are removed.

```sh
perl installer/install-postfilter --cleanup
perl installer/install-postfilter --rollback
```

Configuration path migration, ownership, key preservation and clean-Perl runtime
validation remain as documented in `docs/INSTALL.md`.
