# Test purpose: Checks dependency classification and module-specific degradation behaviour.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::Dependencies;
use TestPostfilter qw(base_config test_logger);

my $config = base_config();
$config->{modules}{dates} = 1;
$config->{modules}{rbl} = 1;
$config->{modules}{uribl} = 1;
$config->{modules}{surbl} = 1;
$config->{modules}{tor} = 1;
$config->{database}{enabled} = 1;
$config->{database}{on_failure} = 'accept';

my $logger = test_logger();
my $disabled = Postfilter::Dependencies->apply_runtime_capabilities($config, $logger);
ok(ref($disabled) eq 'ARRAY', 'dependency checker returns disabled feature list');

# Date::Parse is available in the build container and must remain enabled.
ok($config->{modules}{dates}, 'available date parser keeps date checks enabled');

# Other assertions adapt to the build environment while still checking that a
# missing dependency disables the feature rather than forging an article error.
my $net_dns = eval { require Net::DNS; 1 };
is($config->{modules}{rbl}, $net_dns ? 1 : 0,
   'DNS feature state matches runtime capability');
my $dbi = eval { require DBI; require DBD::SQLite; 1 };
is($config->{database}{enabled}, $dbi ? 1 : 0,
   'SQLite feature state matches runtime capability and fail-open policy');

if (!$net_dns || !$dbi) {
    ok(@{ $logger->{events} } > 0, 'missing modules produce explicit server errors');
}

done_testing;
