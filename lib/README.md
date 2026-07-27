# Perl library root

This directory is added to Perl `@INC` by the INN hook and administration
command. Application modules live below `Postfilter/`; no runtime state is stored
here.

`Postfilter::InstallPaths` contains portable source-tree defaults. The installer
regenerates that module in the activated prefix with the configuration file and
state directory discovered from `innconfval` or explicit options.

`Postfilter::InstallUpgrade` provides non-destructive exact-path migration and `.dist` snapshot helpers used by the installer.
