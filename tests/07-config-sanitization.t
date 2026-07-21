# Test purpose: Verifies invalid optional rules are isolated while critical configuration remains fail-safe.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::Config;
use TestPostfilter qw(base_config test_logger temporary_environment);

my $loader = Postfilter::Config->new(
    source    => '/does/not/matter.toml',
    state_dir => temporary_environment(),
    logger    => test_logger(),
);
my $config = base_config();
$config->{policy}{mode} = 'nonsense';
$config->{logging}{verbosity} = 99;
$config->{headers}{from} = { mode => 'pseudonymize' };
$config->{policy}{modde} = 'audit';
$config->{tor}{header}{mode} = 'sha256';
$config->{html_report}{privacy}{identity_mode} = 'crypt';
$config->{ban_rule} = [
    { id => 'duplicate', pattern => 'ok', enabled => 1 },
    { id => 'duplicate', pattern => 'also-ok', enabled => 1 },
    { id => 'bad-regex', pattern => '(', enabled => 1 },
];

my $warnings = $loader->validate_and_sanitize($config);
ok(@{$warnings} >= 4, 'invalid values produce warnings');
is($config->{policy}{mode}, 'enforce', 'invalid policy mode receives safe default');
is($config->{logging}{verbosity}, 3, 'invalid verbosity receives default');
is($config->{tor}{header}{mode}, 'encrypted', 'deprecated sha256 alias becomes encrypted');
is($config->{html_report}{privacy}{identity_mode}, 'encrypted',
   'deprecated crypt alias becomes encrypted');
ok(!$config->{ban_rule}[1]{enabled}, 'duplicate rule id is disabled');
ok(!$config->{ban_rule}[2]{enabled}, 'invalid regex rule is disabled');
ok(!exists $config->{headers}{from},
   'unknown nested headers.from table is removed instead of becoming a placebo');
ok(!exists $config->{policy}{modde},
   'misspelled fixed-table option is warned about and removed');

my $minimal = $loader->embedded_minimal;
is($minimal->{database}{enabled}, 0, 'emergency config does not require SQLite');
is($minimal->{retention}{events}, 'forever', 'emergency retention is not destructive');

done_testing;
