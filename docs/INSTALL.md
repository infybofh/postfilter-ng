# Installation

## 1. Read before running

The release candidate should first be installed on a staging reader or used in audit mode.
Back up the existing `filter_nnrpd.pl`, Postfilter configuration and INN
configuration before activation.

## 2. Dependencies

Debian/Ubuntu package names commonly include:

```sh
apt install perl libdbi-perl libdbd-sqlite3-perl libnet-dns-perl \
    libtimedate-perl libcryptx-perl libtoml-tiny-perl
```

Package names on BSD vary.  CPAN distributions are listed in `cpanfile`.

## 3. Dry run

```sh
sudo ./installer/install-postfilter --dry-run
```

The installer uses explicit options first, then `innconfval`, then documented
platform defaults.  It prints all selected paths before changing anything.

## 4. Install

```sh
sudo ./installer/install-postfilter --use-innconfval
```

Custom paths are supported:

```sh
sudo ./installer/install-postfilter \
  --filter-dir /etc/news/filter \
  --config-dir /etc/news/postfilter-ng \
  --state-dir /var/lib/news/postfilter-ng \
  --saved-dir /var/spool/news/postfilter-ng/rejected \
  --html-dir /var/www/html/postfilter \
  --user news --group news
```

## 5. Keys

Setup always creates:

```text
tor-header-encryption.key
header-pseudonym.key
html-report-privacy.key
database-privacy.key
```

Each is independently generated from `/dev/urandom`.  Existing files are
verified and preserved during upgrade.

## 6. Staged hook

The installer does not replace the active INN posting filter.  It creates a
review-only candidate:

```text
<pathfilter>/filter_nnrpd.pl.ng -> <prefix>/postfilter
```

A manual installation creates the same candidate explicitly:

```sh
ln -s /usr/local/lib/postfilter-ng/postfilter \
  /etc/news/filter/filter_nnrpd.pl.ng
```

Adjust both paths for the local INN installation.  The source archive does not
contain `filter_nnrpd.pl`.

The code directory contains no runtime secrets.  Configuration and keys live in
the configured INN etc directory; SQLite and generations live in `state_dir`.

The installer also creates the configured top-level text and binary diagnostic
subdirectories below `saved_dir`.  Deeper year/month/day directories are created
lazily only when an article of that type is actually saved.

## 7. Verify before activation

Run configuration and database checks as the same account used by `nnrpd`:

```sh
sudo -u news postfilterctl \
  --config /etc/news/postfilter-ng/postfilter.toml \
  --state-dir /var/lib/news/postfilter-ng \
  check-config

sudo -u news postfilterctl \
  --config /etc/news/postfilter-ng/postfilter.toml \
  --state-dir /var/lib/news/postfilter-ng \
  db-check
```

Expected runtime ownership is:

```text
/var/lib/news/postfilter-ng/                    news:news 0750
/var/lib/news/postfilter-ng/config-generations/ news:news 0750
/var/lib/news/postfilter-ng/*.json               news:news 0640
/var/lib/news/postfilter-ng/*.sqlite3*           news:news 0640
```

Installations created by an earlier release candidate can be normalized once:

```sh
chown -R news:news /var/lib/news/postfilter-ng
find /var/lib/news/postfilter-ng -type d -exec chmod 0750 {} +
find /var/lib/news/postfilter-ng -type f -exec chmod 0640 {} +
```

Verify that the review candidate loads under embedded-Perl conditions:

```sh
PF="$(innconfval pathfilter)"
sudo -u news perl -e '
    my $file = shift;
    my $loaded = do $file;
    die "Perl load error: $@" if $@;
    die "Operating-system error: $!" unless defined $loaded;
    die "Filter returned false\n" unless $loaded;
    die "filter_post() is not defined\n" unless defined &filter_post;
    print "Postfilter-NG hook load OK\n";
' "$PF/filter_nnrpd.pl.ng"
```

Then test representative articles offline:

```sh
postfilterctl explain --hook-stage raw examples/minimal-reader/raw-client-article.post
postfilterctl explain --hook-stage inn examples/minimal-reader/inn-hook-article.post
```

Keep audit mode while observing `news.notice`, `news.info`, `news.debug`,
`news.err`, SQLite statistics and the generated HTML report.

## 8. Activate explicitly

Keep the existing active hook untouched until configuration validation, article
fixtures and audit output have been reviewed.

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

The active hook is loaded when an `nnrpd` process starts. Existing reader
sessions retain the code already loaded for that process. Close test client
sessions and reconnect, or restart the local nnrpd/INN service using the site
procedure. `ctlinnd reload filter.perl` reloads `filter_innd.pl` and does not
reload Postfilter-NG.

To roll back, restore the saved `filter_nnrpd.pl.pre-postfilter-ng` hook and
start new nnrpd processes.

## 9. Enabling mixed operation

The installed default is `article_types.mode = "text-only"`.  To enable a mixed
reader, edit the source configuration, review every binary group glob, set the
mode to `mixed`, then run:

```sh
postfilterctl check-config
postfilterctl explain --hook-stage inn examples/mixed-reader/text-yenc-reject.post
postfilterctl explain --hook-stage inn examples/mixed-reader/binary-yenc-accept.post
postfilterctl explain --hook-stage inn examples/mixed-reader/mixed-crosspost-reject.post
```

A failed reload never replaces the previous valid generation.  Keep global audit
mode while evaluating type-separated SQLite statistics and the HTML report.
