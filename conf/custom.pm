package Postfilter::Local;
use strict;
use warnings;
use Postfilter::Result;

sub custom_rules {
    my ($ctx)=@_;
    # Return undef/0 to accept, a legacy numeric code, a text reason, or a
    # Postfilter::Result object.  Exceptions are contained by Postfilter-NG.
    return 0;
}
1;
