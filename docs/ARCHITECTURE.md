# Architecture

## INN process model

INN loads `filter_nnrpd.pl` inside each nnrpd process. The hook defines
`filter_post()` and lazily constructs one reusable `Postfilter::NG` engine for
the lifetime of that reader process. Existing sessions retain the release already
loaded in memory; newly created nnrpd processes load the current active wrapper.

`ctlinnd reload filter.perl` applies to the innd transit filter and does not
reload this nnrpd posting hook.

## Immutable release model

Rc6 stores code below:

```text
<prefix>/releases/<version>/
```

The active, candidate and rollback INN hooks are small regular wrapper files:

```text
filter_nnrpd.pl
filter_nnrpd.pl.ng
filter_nnrpd.pl.previous
```

A wrapper adds one immutable release's `lib` directory to `@INC`, loads that
release's `postfilter` entry point through Perl `do`, and verifies that
`filter_post()` was defined. The wrapper does not need to be executable because
INN loads it as Perl source.

Candidate installation never changes the active wrapper. Activation is an
explicit atomic rename followed by an embedded-load check. Failure restores the
old active hook before returning an error.

## Pre-rc6 migration

Rc1 through rc5 used a flat mutable prefix. Rc6 copies the exact existing flat
tree to a managed `legacy-*` release snapshot while the original files remain in
place and continue serving the active hook. This preserves local modifications
and avoids a broken interval during migration.

The legacy flat tree is removed only after:

- rc6 is the verified active and latest installed release;
- the exact `Postfilter::NG` and `InstallPaths` modules loaded come from rc6;
- the runtime version matches the wrapper metadata;
- a validated rollback wrapper loads the legacy snapshot or previous managed
  release.

## Runtime paths

Each release contains a generated `lib/Postfilter/InstallPaths.pm`. The installer
writes the detected configuration file and state directory into that module
before compiling and activating the release directory. Environment variables
remain explicit one-shot overrides only.

## Engine pipeline

For each submitted article the engine:

1. loads the current validated configuration generation;
2. builds a bounded article context and stable identity representation;
3. resolves trusted and access profiles;
4. classifies text or binary content;
5. applies structural, content, reputation, rate, banlist and custom checks;
6. applies permitted header transformations;
7. records the final result and rule hits in SQLite;
8. returns an empty string for acceptance or a client-visible rejection string.

The whole pipeline is constrained by the configured processing budget. DNS work
has separate per-query and aggregate deadlines bounded by the remaining article
budget.

## Ownership boundaries

Configuration and keys are root-owned and readable by the INN group. SQLite,
last-known-good generations and saved rejected articles are owned by the runtime
INN account. Code releases and hook wrappers are root-controlled.

## Release state and cleanup

`release-state.json` records the latest installed, active, candidate and previous
release. `legacy-flat-manifest.json` records the exact top-level files captured
from the old layout and whether the snapshot was a validated rollback target.

Cleanup accepts only release directories below the managed `releases` root with
a valid `.postfilter-ng-release.json` marker. It retains at least active plus one
rollback release and never removes anything when the active hook is older,
unrecognised, external or unable to load.
