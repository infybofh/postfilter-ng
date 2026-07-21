# Test purpose: Verifies the one-to-one mapping between historical numeric errors and symbolic codes.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use Postfilter::Codes;

my $all = Postfilter::Codes->all;
ok(ref($all) eq 'HASH', 'all codes returned as a hash');

for my $numeric (0 .. 94, 104 .. 108) {
    ok(exists $all->{$numeric}, "numeric code $numeric exists");
    like($all->{$numeric}{code}, qr/^PF-[A-Z]+-\d{3}$/, "code $numeric is symbolic");
    ok(length($all->{$numeric}{message}), "code $numeric has a message");
    is(Postfilter::Codes->code($numeric), $all->{$numeric}{code}, "code lookup $numeric");
    is(Postfilter::Codes->message($numeric), $all->{$numeric}{message}, "message lookup $numeric");
}

my ($unknown_code, $unknown_message) = Postfilter::Codes->lookup(999);
is($unknown_code, 'PF-INTERNAL-999', 'unknown code receives stable internal identifier');
like($unknown_message, qr/Unknown historical error 999/, 'unknown code is described');

done_testing;
