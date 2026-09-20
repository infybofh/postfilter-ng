# Regression tests for PF-GROUP-054 forbidden-group enforcement.
#
# Anchored forbidden_groups expressions must match individual group names, not
# a comma-joined serialization of Newsgroups and Followup-To.  This covers the
# production bug where a forbidden followup target was accepted whenever it was
# not the only group in the combined list.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::NG;
use TestPostfilter qw(base_config build_context current_rfc_date test_logger);

sub pipeline_result {
    my (%args) = @_;

    my $config = base_config();
    $config->{modules}{attachments} = 0;
    $config->{modules}{content} = 0;
    $config->{modules}{dates} = 0;
    $config->{headers}{check_groups_existence} = 0;
    $config->{forbidden_groups} = [
        '^alt\\.fan\\.rush-limbaugh$',
        '\\.teen',
    ];

    my %headers = (
        From       => 'Example User <example@example.invalid>',
        Newsgroups => $args{newsgroups} // 'rec.arts.tv',
        Subject    => 'Forbidden-group regression',
        Date       => current_rfc_date(),
        'Message-ID' => '<forbidden-followup@test.invalid>',
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
    newsgroups => 'alt.fan.rush-limbaugh',
);
is($result->{code}, 'PF-GROUP-054', 'single forbidden Newsgroups target is rejected');

$result = pipeline_result(
    newsgroups => 'rec.arts.tv,alt.fan.rush-limbaugh',
);
is($result->{code}, 'PF-GROUP-054', 'anchored forbidden group is rejected as second Newsgroups target');
is($result->{group}, 'alt.fan.rush-limbaugh', 'rejection records the matching Newsgroups target');

$result = pipeline_result(
    newsgroups => 'alt.fan.rush-limbaugh,rec.arts.tv',
);
is($result->{code}, 'PF-GROUP-054', 'anchored forbidden group is rejected as first Newsgroups target');

$result = pipeline_result(
    newsgroups  => 'rec.arts.tv',
    followup_to => 'alt.fan.rush-limbaugh',
);
is($result->{code}, 'PF-GROUP-054', 'single forbidden Followup-To target is rejected');
is($result->{group}, 'alt.fan.rush-limbaugh', 'rejection records the matching Followup-To target');

$result = pipeline_result(
    newsgroups  => 'rec.arts.tv',
    followup_to => 'alt.atheism,alt.fan.rush-limbaugh',
);
is($result->{code}, 'PF-GROUP-054', 'anchored forbidden group is rejected as later Followup-To target');

$result = pipeline_result(
    newsgroups  => 'rec.arts.tv,alt.atheism',
    followup_to => 'alt.fan.rush-limbaugh,alt.buddha.short.fat.guy',
);
is($result->{code}, 'PF-GROUP-054', 'forbidden group is rejected across independent Newsgroups and Followup-To lists');

$result = pipeline_result(
    newsgroups => 'alt.example.teen.chat,rec.arts.tv',
);
is($result->{code}, 'PF-GROUP-054', 'unanchored forbidden pattern still matches an individual Newsgroups target');

$result = pipeline_result(
    newsgroups  => 'rec.arts.tv',
    followup_to => 'alt.example.teen.chat,alt.atheism',
);
is($result->{code}, 'PF-GROUP-054', 'unanchored forbidden pattern still matches an individual Followup-To target');

$result = pipeline_result(
    newsgroups  => 'rec.arts.tv,alt.atheism',
    followup_to => 'alt.buddha.short.fat.guy',
);
ok($result->is_pass, 'allowed Newsgroups and Followup-To targets continue through the pipeline');

done_testing;
