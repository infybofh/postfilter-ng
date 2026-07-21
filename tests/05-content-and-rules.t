# Test purpose: Exercises body encodings, badwords, ban rules, scoring and rule actions.
#
# This file is part of the release gate and is intended to be readable by an
# administrator reviewing why a behaviour is considered mandatory.

use strict;
use warnings;

use Test::More;
use lib 'lib';
use lib 'tests/lib';

use Postfilter::Checks::Content;
use Postfilter::Checks::Rules;
use TestPostfilter qw(base_config build_context);

my $binary_cfg = base_config();
my $yenc = build_context(config => $binary_cfg, body => "=ybegin line=128 size=5 name=x\nabc\n");
is(Postfilter::Checks::Content->run_binary($yenc)->legacy, 62, 'yEnc is detected');

my $uu = build_context(
    config => $binary_cfg,
    body   => "begin 644 test.bin\nM1234567890123456789012345678901234567890\nend\n",
);
is(Postfilter::Checks::Content->run_binary($uu)->legacy, 52, 'uuencode is detected');

my $bad_cfg = base_config();
$bad_cfg->{modules}{badwords} = 1;
$bad_cfg->{badwords}{max_subject_score} = 5;
$bad_cfg->{badword} = [{
    id               => 'internal-test-marker',
    enabled          => 1,
    pattern          => 'testivo',
    match_type       => 'contains',
    case_sensitive   => 0,
    targets          => ['subject'],
    subject_score    => 10,
    body_score       => 0,
    action           => 'score',
}];
my $bad = build_context(
    config => $bad_cfg,
    headers => {
        From         => 'Test <test@example.invalid>',
        Newsgroups   => 'local.test',
        Subject      => 'A TESTIVO subject',
        Date         => TestPostfilter::current_rfc_date(),
        'Message-ID' => '<badword@test.invalid>',
    },
);
is(Postfilter::Checks::Content->run_badwords($bad)->legacy, 28,
   'badword subject score rejects at threshold');

my $rule_cfg = base_config();
$rule_cfg->{modules}{banlist} = 1;
$rule_cfg->{ban_rule} = [{
    id             => 'from-steve-carroll-normalized-variants',
    enabled        => 1,
    priority       => 100,
    target         => 'from.address',
    match_type     => 'regex',
    pattern        => '^stev(?:e)?carrol{1,2}\@nospam\.none$',
    case_sensitive => 0,
    action         => 'reject',
    reason_code    => 'PF-RULE-201',
    legacy_code    => 34,
    response       => 'Posting rejected by local policy',
}];

for my $address (
    'Steve Carroll <SteveCarroll@noSPAM.none>',
    'Steve Carroll <StevCarroll@noSPAM.none>',
    'Steve Carroll <SteveCarrol@noSPAM.none>',
) {
    my $ctx = build_context(
        config => $rule_cfg,
        headers => {
            From         => $address,
            Newsgroups   => 'local.test',
            Subject      => 'Rule test',
            Date         => TestPostfilter::current_rfc_date(),
            'Message-ID' => '<steve@test.invalid>',
        },
    );
    my $result = Postfilter::Checks::Rules->run_banlist($ctx);
    ok($result->is_reject, "$address is rejected");
    is($result->code, 'PF-RULE-201', 'descriptive rule reason is retained');
}

my $innocent = build_context(
    config => $rule_cfg,
    headers => {
        From         => 'Different User <different@example.invalid>',
        Newsgroups   => 'local.test',
        Subject      => 'Rule test',
        Date         => TestPostfilter::current_rfc_date(),
        'Message-ID' => '<innocent@test.invalid>',
    },
);
ok(Postfilter::Checks::Rules->run_banlist($innocent)->is_pass,
   'unrelated sender is not rejected');

done_testing;
