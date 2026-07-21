# Test purpose: Prevents empty or unexplained source directories and missing operator documentation.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use File::Find;

my @empty;
find(
    {
        no_chdir => 1,
        wanted   => sub {
            return unless -d $File::Find::name;
            opendir my $directory_handle, $File::Find::name or die $!;
            my @entries = grep { $_ ne '.' && $_ ne '..' } readdir $directory_handle;
            closedir $directory_handle;
            push @empty, $File::Find::name unless @entries;
        },
    },
    '.',
);
is_deeply(\@empty, [], 'source archive contains no empty directories');

for my $directory (qw(
    bin conf examples installer lib lib/Postfilter lib/Postfilter/Checks
    migrations packaging packaging/systemd share share/static tests
)) {
    ok(-f "$directory/README.md" || $directory eq 'conf' && -f 'conf/README.md',
       "$directory has purpose documentation");
}

my @example_directories = grep { -d $_ } glob('examples/*');
for my $directory (@example_directories) {
    ok(-f "$directory/README.md", "$directory has a README");
    my @content = grep { -f $_ && $_ !~ /README\.md$/ } glob("$directory/*");
    ok(@content > 0, "$directory contains a usable example");
}

done_testing;
