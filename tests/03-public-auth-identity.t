# Test purpose: Locks down public, synthetic-public and authenticated identity classification and rate-limit selection.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::Checks::Access;
use TestPostfilter qw(base_config build_context);

{
    package TestRateDatabase;
    sub new { bless { calls => [] }, shift }
    sub available { 1 }
    sub multipost_count { 0 }
    sub rate_snapshot {
        my ($self, $context, $type, $value) = @_;
        push @{ $self->{calls} }, [$type, $value];
        return {};
    }
    sub handle_failure { 'accept' }
}

for my $case (
    [undef,       1, 'undefined user is public'],
    ['',          1, 'empty user is public'],
    ['anonymous', 1, 'configured synthetic public id is public'],
    ['ivo',       0, 'named account is authenticated'],
) {
    my ($user, $expected, $name) = @{$case};
    my $ctx = build_context(user => defined($user) ? $user : '');
    is($ctx->is_public_user, $expected, $name);
}

my $public_db = TestRateDatabase->new;
my $public_cfg = base_config();
$public_cfg->{modules}{access} = 1;
my $public_ctx = build_context(config => $public_cfg, user => '', db => $public_db);
ok(Postfilter::Checks::Access->run($public_ctx)->is_pass, 'public access run passes');
is_deeply(
    $public_db->{calls},
    [
        ['IP', '192.0.2.25'],
        ['DN', 'example.invalid'],
    ],
    'public user is measured by IP and registered domain',
);

my $auth_db = TestRateDatabase->new;
my $auth_cfg = base_config();
$auth_cfg->{modules}{access} = 1;
my $auth_ctx = build_context(config => $auth_cfg, user => 'ivo', db => $auth_db);
ok(Postfilter::Checks::Access->run($auth_ctx)->is_pass, 'authenticated access run passes');
is_deeply($auth_db->{calls}, [['ID', 'ivo']], 'authenticated user is measured by ID');

my $synthetic_db = TestRateDatabase->new;
my $synthetic_cfg = base_config();
$synthetic_cfg->{modules}{access} = 1;
my $synthetic_ctx = build_context(
    config => $synthetic_cfg,
    user   => 'anonymous',
    db     => $synthetic_db,
);
Postfilter::Checks::Access->run($synthetic_ctx);
is($synthetic_db->{calls}[0][0], 'IP', 'synthetic public id uses IP limits');

done_testing;
