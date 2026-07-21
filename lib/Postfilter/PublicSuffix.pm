package Postfilter::PublicSuffix;

use strict;
use warnings;

=head1 NAME

Postfilter::PublicSuffix - Cached loader for public-suffix data.

=head1 DESCRIPTION

The loader keeps one parsed hash per path and modification time for the lifetime
of the nnrpd process.  Wildcard entries are normalised to their suffix and
exception entries are currently ignored; this is sufficient for Postfilter's
registrable-domain rate limiting, while the limitations are documented rather
than hidden in a custom parser.

=cut

my %CACHE;

# Function: load
# Purpose: Loads, normalises, and mtime-caches public-suffix entries from the configured file.
# Parameters: $class, $path, $logger
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub load {
    my ($class, $path, $logger) = @_;
    return {} unless $path && -r $path;

    my $modification_time = (stat($path))[9] // 0;
    if (
        $CACHE{$path}
        && $CACHE{$path}{mtime} == $modification_time
    ) {
        return $CACHE{$path}{data};
    }

    open my $handle, '<:encoding(UTF-8)', $path or do {
        $logger->warning(
            'public_suffix_load_failed',
            path  => $path,
            error => $!,
        ) if $logger;
        return {};
    };

    my %suffixes;
    while (my $line = <$handle>) {
        chomp $line;
        $line =~ s/\r$//;
        $line =~ s{//.*$}{};
        $line =~ s/#.*$//;
        $line =~ s/^\s+|\s+$//g;
        next unless length $line;
        next if $line =~ /^!/;

        $line =~ s/^\*\.//;
        $suffixes{ lc $line } = 1;
    }

    close $handle;

    $CACHE{$path} = {
        data  => \%suffixes,
        mtime => $modification_time,
    };

    return \%suffixes;
}

1;
