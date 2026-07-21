package Postfilter::Local;

use strict;
use warnings;

use Postfilter::Codes;
use Postfilter::Result;

# custom_rules($context)
#
# Receives the same per-article Postfilter::Context used by the built-in checks.
# Return a Postfilter::Result object for an explicit decision, a historical
# numeric code for compatibility, a non-empty text reason for a custom reject,
# or zero/undef for success.
sub custom_rules {
    my ($context) = @_;

    my $subject = $context->{headers}{Subject} // '';
    return 0 unless $subject =~ /POSTFILTER-CUSTOM-REJECT/i;

    return Postfilter::Result->reject(
        code    => 'PF-RULE-250',
        legacy  => 63,
        message => 'Rejected by the documented custom-filter example',
    );
}

1;
