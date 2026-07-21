# Test purpose: Compiles every Perl entry point and module so packaging cannot hide a syntax error.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use File::Find;
use File::Spec;

my @files;
find(
    sub {
        return unless -f $_;
        return unless /\.pm$/ || $_ eq 'postfilter' || $_ eq 'postfilterctl'
            || $_ eq 'install-postfilter';
        push @files, $File::Find::name;
    },
    qw(lib postfilter bin installer),
);

for my $file (sort @files) {
    my $command = "perl -Ilib -c '$file' 2>&1";
    my $output = `$command`;
    is($?, 0, "$file compiles") or diag $output;
}

ok(
    !-e 'filter_nnrpd.pl' && !-l 'filter_nnrpd.pl',
    'the source package does not contain an active INN hook',
);

done_testing;
