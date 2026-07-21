# Test purpose: Exercises raw client articles and INN-hook articles, including an absent client Path header.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::Checks::Style;
use TestPostfilter qw(base_config build_context current_rfc_date);

my $config = base_config();

my $raw = build_context(
    config => $config,
    headers => {
        From         => 'Example User <example@example.invalid>',
        Newsgroups   => 'local.test',
        Subject      => 'Raw client article without Path',
        Date         => current_rfc_date(),
        'Message-ID' => '<raw-client@test.invalid>',
    },
);
my $raw_result = Postfilter::Checks::Style->run($raw);
ok($raw_result->is_pass, 'raw client article without Path is accepted');

my $hook = build_context(
    config => $config,
    headers => {
        Path         => 'not-for-mail',
        From         => 'Example User <example@example.invalid>',
        Newsgroups   => 'local.test',
        Subject      => 'INN hook-stage article',
        Date         => current_rfc_date(),
        'Message-ID' => '<hook-stage@test.invalid>',
    },
);
ok(Postfilter::Checks::Style->run($hook)->is_pass, 'normal INN Path is accepted');

for my $bad_path ("bad\npath", "bad\rpath", "bad\0path", '   ') {
    my $ctx = build_context(
        config => $config,
        headers => {
            Path         => $bad_path,
            From         => 'Example <example@example.invalid>',
            Newsgroups   => 'local.test',
            Subject      => 'Bad Path fixture',
            Date         => current_rfc_date(),
            'Message-ID' => '<bad-path@test.invalid>',
        },
    );
    my $result = Postfilter::Checks::Style->run($ctx);
    ok($result->is_reject, 'malformed supplied Path is rejected');
    is($result->legacy, 20, 'malformed Path uses numeric code 20');
}

my $blank_heavy = build_context(
    config => $config,
    body   => " \n \ntext\n",
);
$blank_heavy->{config}{limits}{max_blank_ratio} = 0.25;
is(Postfilter::Checks::Style->run($blank_heavy)->legacy, 14,
   'blank-line ratio is active');

my $empty_heavy = build_context(
    config => base_config(),
    body   => "\n\ntext\n",
);
$empty_heavy->{config}{limits}{max_empty_ratio} = 0.25;
is(Postfilter::Checks::Style->run($empty_heavy)->legacy, 15,
   'empty-line ratio is active');

done_testing;
