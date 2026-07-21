package Postfilter::Article;

use strict;
use warnings;

=head1 NAME

Postfilter::Article - Serialisation helpers for saved or exported articles.

=head1 DESCRIPTION

INN supplies headers in a hash, so original header ordering is not available to
the Perl hook.  This module produces a deterministic case-insensitive ordering,
normalises folded values and appends the unchanged body.  Internal keys beginning
with two underscores are never written.

=cut

# Function: serialize
# Purpose: Serialises the current article headers and body for exact administrative
#          storage/output.
# Parameters: $class, $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub serialize {
    my ($class, $context) = @_;

    my $output = '';
    for my $name (sort { lc($a) cmp lc($b) } keys %{ $context->{headers} }) {
        next if $name =~ /^__/;

        my $value = $context->{headers}{$name};
        next unless defined $value && length $value;
        $value =~ s/\r?\n[ \t]*/\n\t/g;
        $output .= "$name: $value\n";
    }

    return $output . "\n" . ($context->{body} // '');
}

1;
