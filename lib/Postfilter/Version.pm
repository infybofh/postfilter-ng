package Postfilter::Version;

use strict;
use warnings;

=head1 NAME

Postfilter::Version - Single runtime version source for Postfilter-NG.

=head1 DESCRIPTION

The release version lives here so runtime-generated metadata such as the
C<X-Postfilter> header cannot become stale when an administrator preserves an
older configuration file across an upgrade.

=cut

our $VERSION = '2026.09.1-rc1';

# Function: version
# Purpose: Returns the release version used for runtime-generated metadata.
# Parameters: None.
# Operational notes: This is the single runtime source consumed by X-Postfilter generation.
sub version {
    return $VERSION;
}

1;
