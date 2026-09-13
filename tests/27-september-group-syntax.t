# Regression tests for RFC 5536 Newsgroups and Followup-To syntax validation.
#
# These cases cover the malformed alt..home.repair article reported from a
# live 2026.08.1-rc2 deployment and adjacent grammar failures that must not be
# normalized into valid group lists.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::Context;
use Postfilter::NG;
use Postfilter::Util qw(
    split_groups
    valid_followup_to
    valid_newsgroup_list
    valid_newsgroup_name
);
use TestPostfilter qw(base_config build_context current_rfc_date test_logger);

for my $name (
    'alt.home.repair',
    'comp.lang.c++',
    'legacy.UPPERCASE',
    '123.example',
    '_reserved.example',
    '+private.example',
    '-private.example',
) {
    ok(valid_newsgroup_name($name), "valid RFC 5536 newsgroup-name: $name");
}

for my $name (
    '',
    '.alt.home',
    'alt.home.',
    'alt..home.repair',
    'alt/home',
    'alt:home',
    'alt home',
) {
    ok(!valid_newsgroup_name($name), "invalid RFC 5536 newsgroup-name: $name");
}

for my $list (
    'alt.home.repair',
    'alt.home.repair,rec.arts.tv',
    ' alt.home.repair , rec.arts.tv ',
    "alt.home.repair,\r\n rec.arts.tv",
) {
    ok(valid_newsgroup_list($list), "valid RFC 5536 newsgroup-list: $list");
}

for my $list (
    'alt..home.repair',
    'alt.home.repair rec.arts.tv',
    'alt.home.repair,,rec.arts.tv',
    ',alt.home.repair',
    'alt.home.repair,',
    'alt.home.repair, ,rec.arts.tv',
    'alt.home/reapir,rec.arts.tv',
) {
    ok(!valid_newsgroup_list($list), "invalid RFC 5536 newsgroup-list: $list");
}

ok(valid_followup_to('poster'), 'Followup-To poster is valid');
ok(valid_followup_to('Poster'), 'case-insensitive Poster is accepted as permitted by RFC 5536');
ok(valid_followup_to('alt.followup, rec.followup'), 'Followup-To group list is valid');
ok(!valid_followup_to('poster,alt.followup'), 'poster cannot be mixed with newsgroups');
ok(!valid_followup_to('alt..followup'), 'malformed Followup-To group is rejected');
ok(!valid_followup_to(''), 'empty Followup-To is rejected when the header exists');

is_deeply(
    split_groups('alt.one rec.two'),
    ['alt.one rec.two'],
    'split_groups no longer treats bare whitespace as a group separator',
);
is_deeply(
    split_groups('alt.one, rec.two'),
    ['alt.one', 'rec.two'],
    'split_groups still trims a proper comma-separated list',
);

sub pipeline_result {
    my (%args) = @_;
    my $config = base_config();
    $config->{modules}{attachments} = 0;
    $config->{modules}{content} = 0;
    $config->{modules}{dates} = 0;
    $config->{headers}{check_groups_existence} = 0;

    # Prove syntax validation is an injection invariant rather than a group
    # policy toggle: even disabling the groups module must not accept bad ABNF.
    $config->{modules}{groups} = $args{groups_enabled} // 1;

    my %headers = (
        From       => 'Example User <example@example.invalid>',
        Newsgroups => $args{newsgroups},
        Subject    => 'RFC 5536 syntax regression',
        Date       => current_rfc_date(),
        'Message-ID' => '<group-syntax@test.invalid>',
    );
    $headers{'Followup-To'} = $args{followup_to}
        if exists $args{followup_to};

    my $context = build_context(
        config  => $config,
        headers => \%headers,
    );
    my $engine = bless { logger => test_logger() }, 'Postfilter::NG';
    return $engine->_run_pipeline($context);
}

my $result = pipeline_result(
    newsgroups => 'alt.rush-limbaugh,rec.arts.tv,alt..home.repair',
);
is($result->{legacy}, 115, 'live alt..home.repair regression gets numeric code 115');
is($result->{code}, 'PF-GROUP-115', 'live alt..home.repair regression gets symbolic code');
is($result->message, 'Invalid Newsgroups syntax', 'Newsgroups syntax rejection is readable');

$result = pipeline_result(
    newsgroups => 'alt.one rec.two',
);
is($result->{code}, 'PF-GROUP-115', 'bare whitespace between groups is rejected rather than normalized');

$result = pipeline_result(
    newsgroups => 'alt.one,,rec.two',
);
is($result->{code}, 'PF-GROUP-115', 'empty Newsgroups list element is rejected');

$result = pipeline_result(
    newsgroups   => 'alt.one',
    followup_to  => 'alt..followup',
);
is($result->{legacy}, 116, 'malformed Followup-To gets numeric code 116');
is($result->{code}, 'PF-GROUP-116', 'malformed Followup-To gets symbolic code');
is($result->message, 'Invalid Followup-To syntax', 'Followup-To syntax rejection is readable');

$result = pipeline_result(
    newsgroups     => 'alt..home.repair',
    groups_enabled => 0,
);
is($result->{code}, 'PF-GROUP-115', 'syntax validation remains active when group policy module is disabled');

$result = pipeline_result(
    newsgroups  => 'alt.one, rec.two',
    followup_to => 'poster',
);
ok($result->is_pass, 'valid list and poster Followup-To continue through the pipeline');

done_testing;
