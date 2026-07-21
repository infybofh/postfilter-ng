use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib", "$Bin/lib";

use File::Spec;
use Test::More;

use Postfilter::Checks::Content;
use Postfilter::Checks::Style;
use Postfilter::NG;
use Postfilter::Result;
use Postfilter::SavedArticle;
use TestPostfilter qw(base_config build_context test_logger);

sub mixed_config {
    my $config = base_config();
    $config->{article_types}{mode} = 'mixed';
    $config->{modules}{dates} = 0;
    $config->{modules}{groups} = 0;
    return $config;
}

{
    my $config = base_config();
    my $context = build_context(
        config => $config,
        headers => {
            Newsgroups => 'alt.binaries.example',
            Subject => 'Text-only mode remains text',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<text-only-mode@example.invalid>',
        },
    );
    is($context->{article_type}, 'text', 'text-only mode never enables binary policy');
}

{
    my $config = mixed_config();
    my $text = build_context(
        config => $config,
        headers => {
            Newsgroups => 'it.test',
            Subject => 'Text',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<text@example.invalid>',
        },
    );
    is($text->{article_type}, 'text', 'ordinary group selects text policy');

    my $binary = build_context(
        config => $config,
        headers => {
            Newsgroups => 'alt.binaries.example',
            Subject => 'Binary',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<binary@example.invalid>',
        },
    );
    is($binary->{article_type}, 'binary', 'binary glob selects binary policy');

    my $misspelt_binary = build_context(
        config => $config,
        headers => {
            Newsgroups => 'free.biinaries.example',
            Subject => 'Historical misspelling',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<misspelling@example.invalid>',
        },
    );
    is(
        $misspelt_binary->{article_type},
        'binary',
        'configured historical misspelling glob is honoured',
    );
}


{
    my @glob_cases = (
        ['*.bin*',              'free.binary.test'],
        ['alt.b',                'alt.b'],
        ['alt.bin*',             'alt.binary.test'],
        ['alt.binaries.*',       'alt.binaries.example'],
        ['alt.dvdnordic.*',      'alt.dvdnordic.movies'],
        ['*.bain*',              'free.bain.test'],
        ['*.biana*',             'free.biana.test'],
        ['*.biinaries*',         'free.biinaries.test'],
        ['*bina*',               'free.bina.test'],
        ['*.bineries*',          'free.bineries.test'],
        ['*.binia*',             'free.binia.test'],
        ['*.binries*',           'free.binries.test'],
        ['*.cd.image*',          'free.cd.images'],
        ['*.files.images*',      'free.files.images.test'],
        ['*.mp3*',               'free.mp3.test'],
        ['*music.bin*',          'free.music.binary'],
        ['*.pictures*',          'free.pictures.test'],
        ['*porno.images*',       'free.porno.images'],
        ['*images*',             'free.images.test'],
        ['*.warez*',             'free.warez.test'],
    );

    for my $case (@glob_cases) {
        my ($glob, $group) = @{$case};
        my $config = mixed_config();
        $config->{article_types}{binary_group_patterns} = [$glob];

        my $context = build_context(
            config => $config,
            headers => {
                Newsgroups => $group,
                Subject => "Glob test for $glob",
                From => 'Tester <tester@example.invalid>',
                'Message-ID' => "<glob-$group\@example.invalid>",
            },
        );

        is(
            $context->{article_type},
            'binary',
            "configured binary glob $glob matches $group",
        );
    }
}

{
    my $config = mixed_config();
    $config->{article_types}{pattern_syntax} = 'unsupported';

    my $context = build_context(
        config => $config,
        headers => {
            Newsgroups => 'alt.binaries.example',
            Subject => 'Defensive unknown syntax test',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<unknown-pattern-syntax@example.invalid>',
        },
    );

    is(
        $context->{article_type},
        'text',
        'unknown pattern syntax fails safely to the text policy',
    );
}

{
    my $config = mixed_config();
    $config->{policy}{mode} = 'audit';
    my $context = build_context(
        config => $config,
        headers => {
            Newsgroups => 'it.test,alt.binaries.example',
            Subject => 'Forbidden mixed crosspost',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<mixed@example.invalid>',
        },
    );
    is($context->{article_type}, 'mixed', 'mixed groups are classified before filtering');

    my $engine = bless { logger => test_logger() }, 'Postfilter::NG';
    my $result = $engine->_run_pipeline($context);
    is($result->{legacy}, 95, 'mixed crosspost uses compatibility code 95');
    is($result->{code}, 'PF-GROUP-095', 'mixed crosspost has symbolic code');

    my $final = $engine->_resolve_policy($context, $result);
    is(
        $final->{nntp_result},
        'rejected',
        'mixed crosspost is rejected even while global mode is audit',
    );
}

{
    my $config = mixed_config();
    $config->{trusted_profile} = [
        {
            id => 'test-full-bypass',
            enabled => 1,
            priority => 9_999,
            match_all => 1,
            full_bypass => 1,
            skip_checks => [],
        },
    ];

    my $context = build_context(
        config => $config,
        headers => {
            Newsgroups => 'it.test,alt.binaries.example',
            Subject => 'Mixed crosspost cannot be trusted away',
            From => 'Administrator <admin@example.invalid>',
            'Message-ID' => '<mixed-full-bypass@example.invalid>',
        },
    );

    my $engine = bless { logger => test_logger() }, 'Postfilter::NG';
    my $result = $engine->_run_pipeline($context);
    is(
        $result->{legacy},
        95,
        'mixed-crosspost invariant runs before trusted full bypass',
    );
}

{
    my $config = mixed_config();
    $config->{article_types}{text}{limits}{max_body_size} = 8;
    $config->{article_types}{text}{limits}{max_total_size} = 1_000_000;
    $config->{article_types}{text}{limits}{max_header_size} = 1_000_000;
    my $context = build_context(
        config => $config,
        body => '123456789',
        headers => {
            Newsgroups => 'it.test',
            Subject => 'Oversized text',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<oversized-text@example.invalid>',
        },
    );
    my $result = Postfilter::Checks::Style->run($context);
    is($result->{legacy}, 96, 'text body limit uses text-specific code 96');
}

{
    my $config = mixed_config();
    $config->{article_types}{binary}{limits}{max_body_size} = 8;
    $config->{article_types}{binary}{limits}{max_total_size} = 1_000_000;
    $config->{article_types}{binary}{limits}{max_header_size} = 1_000_000;
    my $context = build_context(
        config => $config,
        body => '123456789',
        headers => {
            Newsgroups => 'alt.binaries.example',
            Subject => 'Oversized binary',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<oversized-binary@example.invalid>',
        },
    );
    my $result = Postfilter::Checks::Style->run($context);
    is($result->{legacy}, 99, 'binary body limit uses binary-specific code 99');
}

{
    my @cases = (
        {
            type => 'text',
            group => 'it.test',
            component => 'header',
            expected => 97,
        },
        {
            type => 'text',
            group => 'it.test',
            component => 'total',
            expected => 98,
        },
        {
            type => 'binary',
            group => 'alt.binaries.example',
            component => 'header',
            expected => 100,
        },
        {
            type => 'binary',
            group => 'alt.binaries.example',
            component => 'total',
            expected => 101,
        },
    );

    for my $case (@cases) {
        my $config = mixed_config();
        my $limits = $config->{article_types}{ $case->{type} }{limits};
        $limits->{max_body_size} = 1_000_000;
        $limits->{max_header_size} = 1_000_000;
        $limits->{max_total_size} = 1_000_000;

        if ($case->{component} eq 'header') {
            $limits->{max_header_size} = 16;
        }
        else {
            $limits->{max_total_size} = 32;
        }

        my $context = build_context(
            config => $config,
            body => 'payload',
            headers => {
                Newsgroups => $case->{group},
                Subject => 'Size component test with deliberately long subject',
                From => 'Tester <tester@example.invalid>',
                'Message-ID' => '<size-component-' . $case->{expected}
                    . '@example.invalid>',
            },
        );

        my $result = Postfilter::Checks::Style->run($context);
        is(
            $result->{legacy},
            $case->{expected},
            "$case->{type} $case->{component} limit uses code $case->{expected}",
        );
    }
}

{
    my $config = mixed_config();
    my $yenc_body = "=ybegin line=128 size=4 name=test.bin\nABCD\n=yend size=4\n";

    my $text = build_context(
        config => $config,
        body => $yenc_body,
        headers => {
            Newsgroups => 'it.test',
            Subject => 'Forbidden yEnc',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<text-yenc@example.invalid>',
        },
    );
    my $text_result = Postfilter::Checks::Content->run_binary($text);
    is($text_result->{legacy}, 62, 'small yEnc payload is rejected in text groups');

    my $binary = build_context(
        config => $config,
        body => $yenc_body,
        headers => {
            Newsgroups => 'alt.binaries.example',
            Subject => 'Allowed yEnc',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<binary-yenc@example.invalid>',
        },
    );
    ok(
        Postfilter::Checks::Content->run_binary($binary)->is_pass,
        'same yEnc payload is allowed by binary content policy',
    );
    ok($binary->skip('badwords'), 'binary policy skips badwords by default');
    ok($binary->skip('style.line_statistics'), 'binary policy skips text line ratios');
    ok($binary->skip('style.content_type'), 'binary policy can skip text MIME policy');
    ok(!$text->skip('badwords'), 'text policy still runs badwords');

    $config->{article_types}{binary}{content}{allow_yenc} = 0;
    my $restricted_binary = build_context(
        config => $config,
        body => $yenc_body,
        headers => {
            Newsgroups => 'alt.binaries.example',
            Subject => 'Binary world with yEnc disabled by local policy',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<binary-yenc-disabled@example.invalid>',
        },
    );
    is(
        Postfilter::Checks::Content->run_binary($restricted_binary)->{legacy},
        102,
        'binary payload disabled by binary policy uses code 102',
    );
}

{
    my $config = mixed_config();
    $config->{article_types}{text}{save_rejected} = {
        mode => 'selected',
        reason_codes => ['PF-BODY-062'],
        compatibility_codes => [],
        rule_ids => [],
        subdirectory => 'text-debug',
    };
    $config->{article_types}{binary}{save_rejected} = {
        mode => 'selected',
        reason_codes => [],
        compatibility_codes => [99],
        rule_ids => [],
        subdirectory => 'binary-debug',
    };

    my $text = build_context(
        config => $config,
        headers => {
            Newsgroups => 'it.test',
            Subject => 'Save selector',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<save-text@example.invalid>',
        },
    );
    ok(
        $text->should_save_rejection(
            Postfilter::Result->reject(
                code => 'PF-BODY-062',
                legacy => 62,
                message => 'yEnc forbidden',
            ),
        ),
        'text save selector matches symbolic code',
    );
    ok(
        !$text->should_save_rejection(
            Postfilter::Result->reject(
                code => 'PF-RULE-034',
                legacy => 34,
                message => 'other reject',
            ),
        ),
        'text save selector does not save unrelated rejects',
    );

    my $binary = build_context(
        config => $config,
        headers => {
            Newsgroups => 'alt.binaries.example',
            Subject => 'Save binary selector',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<save-binary@example.invalid>',
        },
    );
    ok(
        $binary->should_save_rejection(
            Postfilter::Result->reject(
                code => 'PF-BODY-099',
                legacy => 99,
                message => 'binary too large',
            ),
        ),
        'binary save selector matches compatibility code',
    );
    is($text->saved_article_subdirectory, 'text-debug', 'text save tree is configurable');
    is($binary->saved_article_subdirectory, 'binary-debug', 'binary save tree is configurable');

    $config->{article_types}{text}{save_rejected} = {
        mode => 'selected',
        reason_codes => [],
        compatibility_codes => [],
        rule_ids => ['debug-one-text-rule'],
        subdirectory => 'text-debug',
    };
    my $rule_selected_text = build_context(
        config => $config,
        headers => {
            Newsgroups => 'it.test',
            Subject => 'Rule selector',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<save-rule-selector@example.invalid>',
        },
    );
    ok(
        $rule_selected_text->should_save_rejection(
            Postfilter::Result->reject(
                code => 'PF-RULE-201',
                legacy => 34,
                message => 'selected rule',
                rule_id => 'debug-one-text-rule',
            ),
        ),
        'selected save policy matches one exact rule ID',
    );

    $config->{article_types}{text}{save_rejected}{mode} = 'all';
    my $save_all_text = build_context(
        config => $config,
        headers => {
            Newsgroups => 'it.test',
            Subject => 'Save all',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<save-all-text@example.invalid>',
        },
    );
    ok(
        $save_all_text->should_save_rejection(
            Postfilter::Result->reject(
                code => 'PF-RULE-999',
                legacy => 34,
                message => 'any rejection',
            ),
        ),
        'all mode saves every technical text rejection',
    );

    $config->{article_types}{text}{save_rejected}{mode} = 'none';
    my $save_none_text = build_context(
        config => $config,
        headers => {
            Newsgroups => 'it.test',
            Subject => 'Save none',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<save-none-text@example.invalid>',
        },
    );
    ok(
        !$save_none_text->should_save_rejection(
            Postfilter::Result->reject(
                code => 'PF-BODY-062',
                legacy => 62,
                message => 'not saved',
            ),
        ),
        'none mode saves no automatic text rejection',
    );
}


{
    my $config = mixed_config();
    $config->{modules}{badwords} = 1;
    $config->{article_types}{binary}{checks}{skip} = [];
    $config->{badwords}{max_subject_score} = 0;
    $config->{badwords}{max_body_score} = 0;
    $config->{badword} = [
        {
            id => 'text-only-executable-rule',
            enabled => 1,
            article_types => ['text'],
            pattern => 'TYPE-SCOPED-TRIGGER',
            match_type => 'regex',
            case_sensitive => 1,
            targets => ['subject'],
            subject_score => 10,
            body_score => 0,
            action => 'reject',
        },
    ];

    my $text = build_context(
        config => $config,
        headers => {
            Newsgroups => 'it.test',
            Subject => 'TYPE-SCOPED-TRIGGER',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<text-rule-execution@example.invalid>',
        },
    );
    my $binary = build_context(
        config => $config,
        headers => {
            Newsgroups => 'alt.binaries.example',
            Subject => 'TYPE-SCOPED-TRIGGER',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<binary-rule-execution@example.invalid>',
        },
    );

    ok(
        Postfilter::Checks::Content->run_badwords($text)->is_reject,
        'text-scoped badword executes in the text world',
    );
    ok(
        Postfilter::Checks::Content->run_badwords($binary)->is_pass,
        'text-scoped badword is not evaluated in the binary world',
    );
}

{
    my $config = mixed_config();
    my $text = build_context(
        config => $config,
        headers => {
            Newsgroups => 'it.test',
            Subject => 'Scope',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<scope-text@example.invalid>',
        },
    );
    my $binary = build_context(
        config => $config,
        headers => {
            Newsgroups => 'alt.binaries.example',
            Subject => 'Scope',
            From => 'Tester <tester@example.invalid>',
            'Message-ID' => '<scope-binary@example.invalid>',
        },
    );
    my $binary_only_rule = { article_types => ['binary'] };
    ok(!$text->rule_applies_to_article_type($binary_only_rule), 'binary rule does not run on text');
    ok($binary->rule_applies_to_article_type($binary_only_rule), 'binary rule runs on binary');
    ok($text->rule_applies_to_article_type({}), 'unscoped rule is shared');
}

done_testing();
