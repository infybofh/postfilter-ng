# Test purpose: Parses the full commented TOML configuration and every example with the standard parser.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use File::Find;
use lib 'lib';

BEGIN {
    eval { require TOML::Tiny; 1 }
        or plan skip_all => 'TOML::Tiny is not installed in this build environment';
}

use Postfilter::Config;
use Postfilter::Logger;
use File::Temp qw(tempdir);

my @toml;
find(sub { push @toml, $File::Find::name if -f $_ && /\.toml$/ }, qw(conf examples));

for my $file (sort @toml) {
    open my $fh, '<:encoding(UTF-8)', $file or die $!;
    local $/;
    my $text = <$fh>;
    close $fh;
    my $parsed = eval { TOML::Tiny::from_toml($text) };
    ok(!$@ && defined $parsed, "$file parses with TOML::Tiny") or diag($@);
}

my $loader = Postfilter::Config->new(
    source    => 'conf/postfilter.toml',
    state_dir => tempdir(CLEANUP => 1),
    logger    => Postfilter::Logger->new(stderr => 0, verbosity => 1),
);
my ($config, $warnings, $origin) = $loader->load;
is($origin, 'source', 'full configuration loaded from TOML source');
is($config->{policy}{mode}, 'audit', 'release ships in audit mode');
is($config->{retention}{events}, 'forever', 'event retention is indefinite');
is($config->{retention}{config_generations}, 32, 'configuration generation retention is bounded');
is($config->{timeouts}{dns_query_seconds}, 1, 'DNS query timeout defaults to one second');
is($config->{timeouts}{dns_total_seconds}, 1, 'complete DNS work defaults to one second');
is($config->{timeouts}{max_processing_ms}, 2_700, 'processing budget defaults to 2700 ms');
is($config->{timeouts}{on_processing_timeout}, 'reject', 'processing timeout fails closed');
is($config->{headers}{sender}{mode}, 'preserve', 'Sender is preserved by default');
is($config->{article_types}{mode}, 'text-only', 'release defaults to text-only mode');
is(
    scalar @{ $config->{article_types}{binary_group_patterns} },
    20,
    'release carries all twenty configurable binary-group globs',
);
is(
    $config->{article_types}{text}{limits}{max_body_size},
    32_768,
    'text body limit is independently configured',
);
is(
    $config->{article_types}{binary}{limits}{max_body_size},
    10_485_760,
    'binary body limit is independently configured',
);
is(
    $config->{article_types}{binary}{save_rejected}{mode},
    'none',
    'binary reject saving is independently configurable',
);
ok(@{ $config->{ban_rule} } > 5, 'ban rules appended from conf.d');
ok(@{ $config->{badword} } > 5, 'badwords appended from conf.d');

done_testing;
