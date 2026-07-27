# Installation

## 1. Read before running

Install the release candidate on a staging reader or keep `policy.mode = "audit"`
until representative traffic has been reviewed. Back up the active
`filter_nnrpd.pl`, the Postfilter configuration and the INN configuration before
activation.

## 2. Dependencies

Debian/Ubuntu package names commonly include:

```sh
apt install perl libdbi-perl libdbd-sqlite3-perl libnet-dns-perl \
    libtimedate-perl libcryptx-perl libtoml-tiny-perl
```

On FreeBSD, install Perl and the equivalent `p5-*` packages from pkg or ports
before running the installer. Perl installed from packages normally resides in
`/usr/local/bin/perl`. The source entry points use `#!/usr/bin/env perl`; the
installer replaces every installed command shebang with the absolute interpreter
that is running the installer.

The complete CPAN distribution list is in `cpanfile`.

## 3. Dry run and path discovery

```sh
sudo ./installer/install-postfilter --dry-run
```

The installer applies explicit options first, then values returned by
`innconfval`, then portable fallback paths. The plan prints the selected Perl
interpreter, configuration file, state directory, hook candidate and all other
installation paths before changing anything.

The selected configuration file and state directory are written into:

```text
<prefix>/lib/Postfilter/InstallPaths.pm
```

The nnrpd hook and `postfilterctl` use those installed defaults on every future
invocation. `POSTFILTER_CONFIG` and `POSTFILTER_STATE_DIR` remain available only
as explicit one-shot overrides.

## 4. Install

Normal discovery:

```sh
sudo ./installer/install-postfilter --use-innconfval
```

Linux-style explicit layout:

```sh
sudo ./installer/install-postfilter \
  --filter-dir /etc/news/filter \
  --config-dir /etc/news/postfilter-ng \
  --state-dir /var/lib/news/postfilter-ng \
  --saved-dir /var/spool/news/postfilter-ng/rejected \
  --active-file /var/lib/news/active \
  --sendmail /usr/lib/news/bin/innmail \
  --html-dir /var/www/html/postfilter \
  --user news --group news
```

Typical custom FreeBSD source-build layout:

```sh
sudo ./installer/install-postfilter \
  --filter-dir /usr/local/news/bin/filter \
  --config-dir /usr/local/news/etc/postfilter-ng \
  --state-dir /usr/local/news/db/postfilter-ng \
  --saved-dir /usr/local/news/spool/postfilter-ng/rejected \
  --active-file /usr/local/news/db/active \
  --sendmail /usr/local/news/bin/innmail \
  --html-dir /usr/local/www/apache24/data/postfilter \
  --user news --group news
```

`innconfval` normally supplies these values automatically. Explicit options are
useful for non-standard builds, jails and package staging.

During installation the code tree is copied to a temporary prefix, installed
shebangs are pinned to the current Perl interpreter, all Perl files are compiled,
and the prefix is activated transactionally. Existing operator configuration is
preserved during upgrade unless `--force-config` is supplied.

### Upgrade path migration

With `--upgrade`, rc5 scans the preserved main TOML file and active `conf.d/*.toml`
fragments for exact historical shipped defaults such as:

```text
/etc/news/postfilter-ng
/var/lib/news/postfilter-ng
/var/spool/news/postfilter-ng/rejected
/var/www/html/postfilter
/var/lib/news/active
/usr/lib/news/bin/innmail
```

Only complete path values are replaced. Paths that merely share a prefix, such
as `/etc/news/postfilter-ng-custom`, remain unchanged.

Before modifying any operator file, the installer creates a timestamped backup
under:

```text
<config_dir>/upgrade-backups/YYYYMMDDTHHMMSSZ-<pid>/
```

It also writes the current release configuration beside the preserved files as:

```text
postfilter.toml.dist
conf.d/<fragment>.toml.dist
```

The `.dist` files contain the detected site-local paths and are not loaded by
Postfilter-NG.

## 5. Ownership and keys

Setup creates four independent 512-bit keys from `/dev/urandom`:

```text
tor-header-encryption.key
header-pseudonym.key
html-report-privacy.key
database-privacy.key
```

Existing keys are verified and preserved during upgrade.

Expected ownership is intentionally split:

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

The runtime account reads policy and keys but cannot rewrite them. It owns the
state that nnrpd must create and update.

The installer runs configuration validation and database migration after an
irreversible `setgid`/`setuid` privilege drop to the configured INN account. It
then normalizes mutable runtime ownership as a final upgrade safeguard.

Installations created by an early release candidate can be repaired once with:

```sh
chown -R news:news /var/lib/news/postfilter-ng
find /var/lib/news/postfilter-ng -type d -exec chmod 0750 {} +
find /var/lib/news/postfilter-ng -type f -exec chmod 0640 {} +
```

Adjust the state path for the local INN layout. Do not apply this recursive
ownership change to the configuration or key directory.

## 6. Staged hook

The installer never replaces the active INN posting filter. It creates:

```text
<pathfilter>/filter_nnrpd.pl.ng -> <prefix>/postfilter
```

The source archive does not contain `filter_nnrpd.pl`.

A manual installation creates the same candidate explicitly, for example:

```sh
ln -s /usr/local/lib/postfilter-ng/postfilter \
  /usr/local/news/bin/filter/filter_nnrpd.pl.ng
```

The configured text and binary diagnostic subdirectories are created below
`saved_dir`. Date directories are created only when an article is saved.

## 7. Automatic installation checks

Before reporting success, the installer performs all of these checks:

1. compiles the staged code with the selected Perl interpreter;
2. generates and compiles `Postfilter::InstallPaths`;
3. clears inherited Perl library and option variables during validation;
4. runs `postfilterctl check-config` and `db-migrate` with the detected paths
   supplied explicitly;
5. starts a clean Perl process, loads `Postfilter::InstallPaths` from the active
   prefix and compares the loaded module, configuration file and state directory
   with the installation plan;
6. repeats `postfilterctl check-config` and runs `db-check` without environment
   variables or command-line path overrides;
7. loads `filter_nnrpd.pl.ng` through Perl `do` with an nnrpd-like `$0`;
8. constructs and shuts down the Postfilter-NG engine through that embedded-hook
   path.

A mismatch between detected paths and runtime paths stops installation before
the candidate is activated. If an activated upgrade fails, the previous prefix
is restored and the failed tree is retained as:

```text
<prefix>.failed.<UTC timestamp>.<pid>
```

## 8. Verify before activation

The installed defaults make explicit path arguments unnecessary:

```sh
sudo -u news postfilterctl check-config
sudo -u news postfilterctl db-check
```

Expected output includes the source configuration origin and a successful SQLite
integrity check. The generated defaults can be inspected with:

```sh
perl -I/usr/local/lib/postfilter-ng/lib \
  -MPostfilter::InstallPaths \
  -e 'print Postfilter::InstallPaths::config_file(), "\n", Postfilter::InstallPaths::state_dir(), "\n"'
```

Adjust the prefix when it was overridden.

A standalone embedded-load verification remains useful after manual changes:

```sh
PF="$(innconfval pathfilter)"
sudo -u news perl -e '
    my $file = shift;
    local $0 = "/usr/local/news/bin/nnrpd";
    my $loaded = do $file;
    die "Perl load error: $@" if $@;
    die "Operating-system error: $!" unless defined $loaded;
    die "Filter returned false\n" unless $loaded;
    die "Postfilter-NG engine entry point is unavailable\n"
        unless defined &main::_engine;
    my $engine = main::_engine();
    die "Engine construction failed\n" unless $engine;
    $engine->shutdown;
    print "Postfilter-NG embedded hook load OK\n";
' "$PF/filter_nnrpd.pl.ng"
```

Test representative articles offline:

```sh
postfilterctl explain --hook-stage raw examples/minimal-reader/raw-client-article.post
postfilterctl explain --hook-stage inn examples/minimal-reader/inn-hook-article.post
```

Keep audit mode while observing INN's `news.notice`, `news.info`, `news.debug`
and `news.err` outputs, SQLite statistics and the generated HTML report.

## 9. Activate explicitly

When no active hook exists:

```sh
mv /etc/news/filter/filter_nnrpd.pl.ng \
   /etc/news/filter/filter_nnrpd.pl
```

When an active hook already exists:

```sh
mv /etc/news/filter/filter_nnrpd.pl \
   /etc/news/filter/filter_nnrpd.pl.pre-postfilter-ng
mv /etc/news/filter/filter_nnrpd.pl.ng \
   /etc/news/filter/filter_nnrpd.pl
```

Adjust `pathfilter` for the local INN installation.

The active hook is loaded when an `nnrpd` process starts. Existing reader
sessions retain the code and configuration already loaded for that process.
Reconnect test clients or restart the local nnrpd/INN service according to the
site procedure.

`ctlinnd reload filter.perl` reloads `filter_innd.pl`; it does not reload
Postfilter-NG.

Rollback restores `filter_nnrpd.pl.pre-postfilter-ng` and starts new nnrpd
processes.

## 10. Enabling mixed operation

The installed default is `article_types.mode = "text-only"`. To enable a mixed
reader, review every binary group glob, set the mode to `mixed`, then run:

```sh
postfilterctl check-config
postfilterctl explain --hook-stage inn examples/mixed-reader/text-yenc-reject.post
postfilterctl explain --hook-stage inn examples/mixed-reader/binary-yenc-accept.post
postfilterctl explain --hook-stage inn examples/mixed-reader/mixed-crosspost-reject.post
```

A failed configuration reload never replaces the previous valid generation.
Keep global audit mode while evaluating type-separated SQLite statistics and the
HTML report.
