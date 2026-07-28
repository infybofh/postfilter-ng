# Installation, activation, rollback and cleanup

## 1. Read before running

Install the release candidate on a staging reader or keep `policy.mode = "audit"`
until representative traffic has been reviewed. Back up the active INN hook,
Postfilter configuration and INN configuration before the first migration.

Postfilter-NG rc6 uses immutable release directories. Installing a candidate does
**not** replace the code used by the active `filter_nnrpd.pl`. Activation is a
separate explicit operation.

## 2. Source files uploaded through GitHub Web

GitHub's web upload interface does not preserve Git executable modes. The source
installer and administration scripts therefore do not depend on an executable
bit. Invoke them explicitly through Perl:

```sh
perl installer/install-postfilter --help
perl bin/postfilterctl help
sh tests/run-tests
```

The installer rewrites installed shebangs to the exact Perl interpreter that ran
it and sets the installed command copies to mode `0755`.

## 3. Dependencies

Debian/Ubuntu package names commonly include:

```sh
apt install perl libdbi-perl libdbd-sqlite3-perl libnet-dns-perl \
    libtimedate-perl libcryptx-perl libtoml-tiny-perl
```

On FreeBSD, install Perl and the equivalent `p5-*` packages from pkg or ports.
Package Perl normally resides at `/usr/local/bin/perl`. The complete CPAN list is
in `cpanfile`.

## 4. Dry run and path discovery

```sh
sudo perl installer/install-postfilter --dry-run
```

The installer applies explicit options first, then values returned by
`innconfval`, then portable fallback paths. The plan prints the selected Perl
interpreter, candidate release, configuration file, state directory, hook paths,
retention count and all other installation paths before changing anything.

Typical FreeBSD source-build example:

```sh
sudo perl installer/install-postfilter --dry-run \
  --filter-dir /usr/local/news/bin/filter \
  --config-dir /usr/local/news/etc/postfilter-ng \
  --state-dir /usr/local/news/db/postfilter-ng \
  --saved-dir /usr/local/news/spool/postfilter-ng/rejected \
  --active-file /usr/local/news/db/active \
  --sendmail /usr/local/news/bin/innmail \
  --html-dir /usr/local/www/apache24/data/postfilter \
  --user news --group news
```

## 5. Immutable release layout

Rc6 installs code below a versioned directory:

```text
<prefix>/
├── releases/
│   ├── legacy-2026.07.5-rc2/
│   └── 2026.07.5-rc7/
├── current  -> releases/2026.07.5-rc7
├── previous -> releases/legacy-2026.07.5-rc2
├── release-state.json
└── legacy-flat-manifest.json
```

`current` and `previous` are created only after successful activation. Release
directories are not overwritten while active.

The INN filter directory contains regular wrapper files:

```text
filter_nnrpd.pl       active wrapper
filter_nnrpd.pl.ng    candidate wrapper
filter_nnrpd.pl.previous  rollback wrapper
```

Each generated wrapper is pinned to one immutable release directory. It loads
that release through Perl `do`, verifies that `filter_post()` exists and does not
depend on the wrapper being executable or being a symbolic link.

## 6. Fresh installation

```sh
sudo perl installer/install-postfilter
```

The installer:

1. creates `<prefix>/releases/<version>` through a staging directory;
2. rewrites installed shebangs and compiles the staged Perl tree;
3. generates release-local `Postfilter::InstallPaths` values;
4. installs or preserves configuration, keys, SQLite state and saved-article
   directories;
5. creates a regular `filter_nnrpd.pl.ng` wrapper pinned to the candidate;
6. validates configuration and SQLite as the configured INN account;
7. loads the candidate as embedded nnrpd Perl does and constructs the engine;
8. leaves `filter_nnrpd.pl` unchanged;
9. performs no cleanup before activation.

A successful candidate installation ends with an explicit notice similar to:

```text
Candidate installed and validated: 2026.07.5-rc7
Active hook was not modified.
No cleanup was performed because the candidate is not active.
```

## 7. Upgrade from rc1 through rc5 or another flat installation

Run:

```sh
sudo perl installer/install-postfilter --upgrade
```

Any recognised pre-rc6 installation under the old flat prefix is treated as a
legacy installation, regardless of its release number. The installer does not
assume that the old release is rc5.

Before installing rc6 it:

1. lists the legacy top-level entries;
2. copies the exact installed tree, including local modifications and file
   modes, to a temporary sibling directory outside the prefix;
3. moves the completed snapshot into
   `<prefix>/releases/legacy-<detected-version>/`;
4. creates a temporary wrapper to that snapshot and loads it;
5. records whether the snapshot is a validated rollback target;
6. leaves the original flat tree and active `filter_nnrpd.pl` untouched.

The copy excludes `releases`, `current`, `previous` and installer state files,
preventing recursive snapshots.

If the old version cannot be identified, the snapshot receives a name such as:

```text
legacy-unknown-20260727T153000Z
```

If the snapshot cannot be loaded, it is still preserved, but automatic removal
of the old flat installation is disabled.

### Configuration path migration

During `--upgrade`, exact historical shipped paths in the preserved main TOML
and active `conf.d/*.toml` fragments are migrated, including:

```text
/etc/news/postfilter-ng
/var/lib/news/postfilter-ng
/var/spool/news/postfilter-ng/rejected
/var/www/html/postfilter
/var/lib/news/active
/usr/lib/news/bin/innmail
```

Only complete historical values are replaced. Similar custom prefixes remain
unchanged. Before changing operator files the installer creates:

```text
<config_dir>/upgrade-backups/YYYYMMDDTHHMMSSZ-<pid>/
```

It also writes path-adjusted reference files that are not loaded automatically:

```text
postfilter.toml.dist
conf.d/<fragment>.toml.dist
```

## 8. Ownership and keys

Expected ownership is split intentionally:

```text
Configuration and keys:
  directories  root:news 0750
  files        root:news 0640

Mutable state, SQLite and generations:
  directories  news:news 0750
  files        news:news 0640

Saved rejected articles:
  directories  news:news 0750
  files        news:news 0640
```

Setup creates or preserves four independent 512-bit keys:

```text
tor-header-encryption.key
header-pseudonym.key
html-report-privacy.key
database-privacy.key
```

The `news` account can read policy and keys but cannot alter its own filtering
rules.

## 9. Validate the candidate

The installer already performs the runtime checks, but the candidate can be
loaded manually without executing it directly:

```sh
PF="$(innconfval pathfilter)"
sudo -u news perl -e '
    my $file = shift;
    local $0 = "/usr/local/news/bin/nnrpd";
    my $loaded = do $file;
    die "Perl load error: $@" if $@;
    die "Operating-system error: $!" unless defined $loaded;
    die "Filter returned false\n" unless $loaded;
    die "filter_post() is not defined\n" unless defined &filter_post;
    print "Postfilter-NG hook load OK\n";
' "$PF/filter_nnrpd.pl.ng"
```

`ctlinnd reload filter.perl` reloads `filter_innd.pl`; it does not reload the
nnrpd posting hook. Each existing nnrpd process keeps the code already loaded
for that session.

## 10. Activate the candidate

After configuration and audit review:

```sh
sudo perl installer/install-postfilter --activate-candidate
```

Repeat the same explicit path options used during installation when
`innconfval` cannot discover the local layout.

Activation performs the following guarded transaction:

1. validates `filter_nnrpd.pl.ng` again;
2. confirms that its release is the latest installed candidate;
3. creates and validates `filter_nnrpd.pl.previous` for the currently active
   managed release or validated legacy snapshot;
4. preserves the current active hook temporarily;
5. atomically renames the candidate wrapper to `filter_nnrpd.pl`;
6. loads the new active hook and verifies the exact `Postfilter::NG` and
   `InstallPaths` module locations plus runtime version;
7. restores the old hook automatically if validation fails;
8. updates `current`, `previous` and the `postfilterctl` command link;
9. runs guarded cleanup.

Existing nnrpd sessions may continue with the previous version already loaded in
memory. New nnrpd processes load the newly activated wrapper.

## 11. Guarded cleanup and retention

The default retention is two releases:

```text
active release + one validated rollback release
```

A lower value is rejected. A larger value can be selected during install or
activation:

```sh
sudo perl installer/install-postfilter --activate-candidate --keep-releases 3
```

Cleanup is permitted only when all required checks succeed:

- the active hook is a generated regular wrapper;
- the wrapper points below `<prefix>/releases`;
- its marker matches the wrapper version;
- it is the latest installed release recorded in `release-state.json`;
- loading the hook resolves `Postfilter::NG` and `InstallPaths` from that exact
  release directory;
- the runtime version matches the wrapper version;
- `filter_post()` and the engine load successfully;
- a validated rollback wrapper exists.

Only then may the installer remove:

- obsolete managed release directories beyond retention;
- the old flat `postfilter`, `lib`, `bin`, `installer` and other captured prefix
  entries;
- stale installer staging, failed-upgrade and generated hook backup artifacts.

No arbitrary directory is removed. Every release must be below the managed
`releases` root and contain a valid `.postfilter-ng-release.json` marker. Legacy
flat removal uses only the exact top-level entries recorded before migration.

When the candidate is merely installed, cleanup is deliberately skipped. It can
be retried after manual inspection with:

```sh
sudo perl installer/install-postfilter --cleanup
```

If the active hook does not use the latest installed release, cleanup refuses to
remove anything.

## 12. Rollback

```sh
sudo perl installer/install-postfilter --rollback
```

Rollback validates `filter_nnrpd.pl.previous`, swaps the active and previous
wrappers, loads the rolled-back hook and updates `current`, `previous` and
`postfilterctl`. It performs no cleanup, so the replaced release remains
available for a roll-forward.

## 13. Failure diagnostics

Failed candidate trees are preserved with names such as:

```text
<prefix>/releases/.failed-2026.07.5-rc7-YYYYMMDDTHHMMSSZ-<pid>
```

Legacy snapshot metadata is stored in:

```text
<prefix>/legacy-flat-manifest.json
```

Release and activation state is stored in:

```text
<prefix>/release-state.json
```

After a later successful activation and verified rollback, guarded cleanup
removes stale installer artifacts.

## 14. Uninstall safety

Uninstall refuses to remove the code prefix while the active hook still points
to a managed Postfilter-NG release under that prefix. This prevents a working
filter from becoming `SERVER perl filter not defined` after code removal.

SQLite state and saved rejected articles are preserved by default. Configuration
is preserved with `--keep-config`.
