package Postfilter::InstallPaths;

use strict;
use warnings;

=head1 NAME

Postfilter::InstallPaths - Installer-generated runtime path defaults.

=head1 DESCRIPTION

The release archive ships portable Linux-style defaults so the source tree can
be tested before installation.  C<install-postfilter> rewrites this module in
the activated prefix with the paths discovered from C<innconfval> or supplied
on its command line.  Explicit environment variables remain available for
one-shot diagnostics and packaging overrides.

=cut

our $VERSION = '2026.07.5-rc6';

use constant CONFIG_FILE => '/etc/news/postfilter-ng/postfilter.toml';
use constant STATE_DIR   => '/var/lib/news/postfilter-ng';

# Function: config_file
# Purpose: Returns the runtime configuration file, with an explicit environment override.
# Parameters: None.
# Operational notes: The installer rewrites CONFIG_FILE in the installed module.
sub config_file {
    return $ENV{POSTFILTER_CONFIG} // CONFIG_FILE;
}

# Function: state_dir
# Purpose: Returns the runtime state directory, with an explicit environment override.
# Parameters: None.
# Operational notes: The installer rewrites STATE_DIR in the installed module.
sub state_dir {
    return $ENV{POSTFILTER_STATE_DIR} // STATE_DIR;
}

1;
