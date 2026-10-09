use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Spec;
use Test::More;

use Postfilter::CodeReference;
use Postfilter::Codes;

my $root = File::Spec->rel2abs("$FindBin::Bin/..");
my $all = Postfilter::Codes->all;
my $refs = Postfilter::CodeReference->all_references;

is(scalar(@$refs), scalar(keys %$all), 'reference covers every defined historical code');

for my $r (@$refs) {
    is($r->{code}, $all->{$r->{legacy}}{code}, "$r->{code} symbolic mapping agrees with Codes.pm");
    ok(length($r->{message}), "$r->{code} has a message");
    ok(length($r->{configuration}), "$r->{code} has a configuration/policy hint");
    ok(length($r->{trigger}), "$r->{code} has a trigger description");
    for my $site (@{$r->{call_sites}}) {
        my $path = File::Spec->catfile($root, split m{/}, $site->{file});
        ok(-f $path, "$r->{code} source file exists: $site->{file}");
        open my $fh, '<', $path or die $!;
        my @lines = <$fh>;
        close $fh;
        ok($site->{line} >= 1 && $site->{line} <= @lines, "$r->{code} source line is in range");
        my $line = $lines[$site->{line} - 1] // '';
        like($line, qr/(?:\Q$r->{code}\E|\b\Q$r->{legacy}\E\b)/, "$r->{code} source line still names code or legacy number");
    }
}

my $jesse = Postfilter::CodeReference->resolve('PF-RATE-084');
is($jesse->{legacy}, 84, 'PF-RATE-084 resolves to legacy 84');
like($jesse->{configuration}, qr/max_total_groups/, 'PF-RATE-084 points to max_total_groups configuration');
ok(grep($_->{file} eq 'lib/Postfilter/Checks/Access.pm', @{$jesse->{call_sites}}), 'PF-RATE-084 points to Access.pm');

my $numeric = Postfilter::CodeReference->resolve('84');
is($numeric->{code}, 'PF-RATE-084', 'numeric lookup resolves to the same symbolic code');

my $ctl = `$^X bin/postfilterctl explain-code PF-RATE-084 2>&1`;
is($? >> 8, 0, 'postfilterctl explain-code succeeds without loading site configuration');
like($ctl, qr/PF-RATE-084/, 'explain-code prints symbolic code');
like($ctl, qr/Access\.pm:\d+/, 'explain-code prints exact source line');
like($ctl, qr/max_total_groups/, 'explain-code prints configuration hint');

my $generated = `$^X bin/generate-error-codes`;
is($? >> 8, 0, 'error-code documentation generator succeeds');
open my $dfh, '<', 'docs/ERROR-CODES.md' or die $!;
local $/;
my $committed = <$dfh>;
close $dfh;
is($generated, $committed, 'ERROR-CODES.md is exactly reproducible from the generator');

# Reproducibility must not depend on Perl hash randomisation or filesystem
# traversal order.  Run fresh processes with several hash seeds and require
# byte-for-byte identical output every time.
for my $seed (0 .. 4) {
    local $ENV{PERL_HASH_SEED} = $seed;
    local $ENV{PERL_PERTURB_KEYS} = 2;
    my $repeat = `$^X bin/generate-error-codes`;
    is($? >> 8, 0, "error-code generator succeeds with PERL_HASH_SEED=$seed");
    is($repeat, $committed, "error-code reference is deterministic with PERL_HASH_SEED=$seed");
}

like($committed, qr/PF-RATE-084.*Access\.pm:\d+/s, 'generated documentation solves the PF-RATE-084 traceability case');

done_testing;
