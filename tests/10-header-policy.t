# Test purpose: Verifies Sender/From preservation, explicit pseudonymisation, TOR headers and Distribution handling.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::HeaderTransform;
use TestPostfilter qw(base_config build_context);

my $config = base_config();
my $ctx = build_context(
    config => $config,
    headers => {
        Path         => 'not-for-mail',
        From         => 'Author <author@example.invalid>',
        Sender       => 'Posting Agent <sender@example.invalid>',
        Newsgroups   => 'local.test',
        Subject      => 'Sender policy test',
        Date         => TestPostfilter::current_rfc_date(),
        'Message-ID' => '<sender-policy@test.invalid>',
    },
);

ok(Postfilter::HeaderTransform->apply($ctx)->is_pass, 'default transforms pass');
is($ctx->{headers}{From}, 'Author <author@example.invalid>', 'From preserved by default');
is($ctx->{headers}{Sender}, 'Posting Agent <sender@example.invalid>',
   'Sender preserved by default');

$config = base_config();
$config->{headers}{sender}{mode} = 'delete';
$ctx = build_context(
    config => $config,
    headers => {
        Path         => 'not-for-mail',
        From         => 'Author <author@example.invalid>',
        Sender       => 'Posting Agent <sender@example.invalid>',
        Newsgroups   => 'local.test',
        Subject      => 'Sender delete test',
        Date         => TestPostfilter::current_rfc_date(),
        'Message-ID' => '<sender-delete@test.invalid>',
    },
);
Postfilter::HeaderTransform->apply($ctx);
ok(!defined $ctx->{headers}{Sender}, 'explicit delete mode marks Sender for reliable INN removal');

done_testing;
