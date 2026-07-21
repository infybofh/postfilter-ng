# Test purpose: Enforces nearby function explanations and guards against compressed unreadable source style.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use File::Find;

my @modules;
find(sub { push @modules, $File::Find::name if -f $_ && /\.pm$/ }, 'lib/Postfilter');

for my $file (sort @modules) {
    open my $fh, '<', $file or die $!;
    local $/;
    my $text = <$fh>;
    close $fh;
    like($text, qr/=head1\s+NAME/, "$file has module documentation");
    my @subs = ($text =~ /^sub\s+([A-Za-z0-9_]+)/mg);
    for my $sub (@subs) {
        my $position = index($text, "sub $sub");
        my $prefix_start = $position > 700
            ? $position - 700
            : 0;
        my $prefix_length = $position > 700
            ? 700
            : $position;
        my $prefix = substr($text, $prefix_start, $prefix_length);
        my $documentation_marker = qr{
            (?:
                =head2
                |
                \#\s*(?:
                    Purpose|Function|Helper|Return|Load|Apply|Build|Create|
                    Check|Convert|Record|Generate|Resolve|Run|Write|Read
                )
            )
        }ix;
        like(
            $prefix,
            $documentation_marker,
            "${file}::${sub} has nearby explanatory documentation",
        );
    }
}

done_testing;
