use strict;
use warnings;

use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib", "$Bin/lib";

use Postfilter::HeaderTransform;
use Postfilter::NG;
use Postfilter::RFC5536 qw(
    parse_injection_info
    serialize_injection_info
    validate_article
    valid_injection_info
    valid_message_id
);
use TestPostfilter qw(base_config build_context current_rfc_date test_logger);

sub valid_article {
    my (%extra) = @_;
    my %headers = (
        From       => 'Example User <example@example.invalid>',
        Newsgroups => 'local.test,comp.lang.perl.misc',
        Subject    => 'RFC 5536 compliance fixture',
        Date       => current_rfc_date(),
        'Message-ID' => '<rfc5536-test@postfilter.invalid>',
        Path       => 'reader.example.invalid!not-for-mail',
        Organization => 'Example Organization',
        Summary      => 'A deliberately complex standards fixture',
        'Followup-To' => 'local.test',
        'Injection-Date' => current_rfc_date(),
        'Injection-Info' => 'reader.example.invalid; logging-data="abc;def"; posting-account="a=b"; mail-complaints-to="abuse@example.invalid"; x-local="one=two;three"',
        'User-Agent' => 'ExampleReader/1.2 PostfilterTest/2026.10',
        References => '<first@example.invalid> <second@example.invalid>',
        'MIME-Version' => '1.0',
        'Content-Type' => 'text/plain; charset=utf-8; x-note="semi;equals=ok"',
        'Content-Transfer-Encoding' => '8bit',
        'Content-Language' => 'en-US, it',
        Xref => 'reader.example.invalid local.test:123 comp.lang.perl.misc:456',
        %extra,
    );
    return \%headers;
}

my $neodome = 'neodome.net; logging-data="67994"; posting-account="abc"';
ok(valid_injection_info($neodome), 'Neodome valid Injection-Info is accepted');
my $parsed = parse_injection_info($neodome);
is(serialize_injection_info($parsed), $neodome, 'valid Injection-Info round-trips without trailing semicolon');
unlike(serialize_injection_info($parsed), qr/;\z/, 'serializer never appends an empty trailing parameter');
ok(!valid_injection_info($neodome . ';'), 'Neodome regression: trailing semicolon is rejected');

my $quoted = 'news.example; logging-data="abc;def"; posting-account="a=b"; x-note="plain"';
my $qp = parse_injection_info($quoted);
ok($qp, 'quoted semicolon/equal/escape Injection-Info parses');
is($qp->{parameters}[0]{value}, 'abc;def', 'semicolon inside quoted value is preserved');
is($qp->{parameters}[1]{value}, 'a=b', 'equals inside quoted value is preserved');
ok(valid_injection_info(serialize_injection_info($qp)), 'quoted values survive parse/serialize round trip');
ok(!valid_injection_info('news.example; logging-data="a"; logging-data="b"'), 'duplicate standard Injection-Info parameter is rejected');
ok(!valid_injection_info('news.example; local-private="x"'), 'non-standard Injection-Info attribute requires x- prefix');
ok(valid_injection_info('news.example; x-local-private="x"'), 'x- Injection-Info extension is accepted');

my $folded_injection = qq{paganini.bofh.team; posting-host="194.116.8.238";\n\tlogging-data="1213788"; mail-complaints-to="usenet\@bofh.team"};
ok(valid_injection_info($folded_injection), 'RFC 5536 folded Injection-Info is accepted');
my $folded_parsed = parse_injection_info($folded_injection);
is(
    serialize_injection_info($folded_parsed),
    'paganini.bofh.team; posting-host="194.116.8.238"; logging-data="1213788"; mail-complaints-to="usenet@bofh.team"',
    'folded Injection-Info unfolds and serializes without changing parameter semantics',
);

ok(valid_message_id('<simple@example.invalid>'), 'valid Message-ID passes');
ok(!valid_message_id('<bad id@example.invalid>'), 'Message-ID containing whitespace is rejected');
ok(!valid_message_id(('<' . ('a' x 245) . '@x.invalid>')), 'Message-ID over 250 octets is rejected');

my $complex = valid_article();
my ($ok, $errors) = validate_article($complex, "First body line.\nSecond body line.\n", phase => 'pre-transform');
ok($ok, 'complex article with broad RFC/MIME header coverage validates') or diag explain $errors;

my $folded_complex = valid_article(
    From => qq{Example User\n\t<example\@example.invalid>},
    Distribution => qq{local,\n\tworld},
    'Injection-Info' => $folded_injection,
    'User-Agent' => qq{ExampleReader/1.2\n\tPostfilterTest/2026.10},
    'Content-Type' => qq{text/plain;\n\tcharset=utf-8; format=flowed},
    'Content-Language' => qq{en-US,\n\tit},
    Xref => qq{reader.example.invalid local.test:123\n\tcomp.lang.perl.misc:456},
);
my ($folded_ok, $folded_errors) = validate_article($folded_complex, "body\n", phase => 'pre-transform');
ok($folded_ok, 'legal RFC folding is unfolded before structured-field validation') or diag explain $folded_errors;

# INN nnrpd does not expose the final propagated Path to filter_post.  During
# ProcessHeaders it first creates .POSTED[.source]!<tail/path>, then calls the
# Perl filter; innd prepends the server path-identity only afterwards.  The
# staging form is intentionally accepted only when the caller explicitly says
# it is running inside that hook stage.
my $paganini_final_path = 'paganini.bofh.team!.POSTED.194.116.8.238!not-for-mail';
my $paganini_staging_path = '.POSTED.194.116.8.238!not-for-mail';
my ($paganini_final_ok, $paganini_final_errors) = validate_article(
    valid_article(Path => $paganini_final_path),
    "body\n",
);
ok($paganini_final_ok, 'exact propagated paganini Path is valid RFC 5536') or diag explain $paganini_final_errors;
my ($staging_final_mode_ok) = validate_article(
    valid_article(Path => $paganini_staging_path),
    "body\n",
);
ok(!$staging_final_mode_ok, 'nnrpd staging Path is not mistaken for a final RFC 5536 Path');
my ($staging_hook_ok, $staging_hook_errors) = validate_article(
    valid_article(Path => $paganini_staging_path),
    "body\n",
    allow_inn_nnrpd_staging_path => 1,
);
ok($staging_hook_ok, 'exact INN nnrpd .POSTED staging Path is accepted in hook mode') or diag explain $staging_hook_errors;
for my $bad_staging (
    '.SEEN.194.116.8.238!not-for-mail',
    '.POSTED.194.116.8.238!bad path!not-for-mail',
    '.POSTED.!not-for-mail',
) {
    my ($bad_ok) = validate_article(
        valid_article(Path => $bad_staging),
        "body\n",
        allow_inn_nnrpd_staging_path => 1,
    );
    ok(!$bad_ok, "invalid/non-INN staging Path remains rejected: $bad_staging");
}

my $rfc5537_path_example =
    'foo.isp.example!.SEEN.isp.example!foo-news ' .
    '!.MISMATCH.2001:DB8:0:0:8:800:200C:417A!bar.isp.example ' .
    '!!old.site.example!barbaz!!baz.isp.example ' .
    '!.POSTED.dialup123.baz.isp.example!not-for-mail';
my ($rfc5537_path_ok, $rfc5537_path_errors) = validate_article(
    valid_article(Path => $rfc5537_path_example),
    "body\n",
);
ok($rfc5537_path_ok, 'RFC 5537 section 3.2.2 complex Path example is accepted') or diag explain $rfc5537_path_errors;

my $mixed_case = valid_article();
delete $mixed_case->{'MIME-Version'};
$mixed_case->{'Mime-Version'} = '2.0';
my ($mixed_case_ok, $mixed_case_errors) = validate_article($mixed_case, "body\n");
ok(!$mixed_case_ok, 'structured header names are matched case-insensitively');
ok(grep({ ($_->{header}//'') eq 'MIME-Version' && ($_->{reason}//'') eq 'invalid-mime-version' } @{$mixed_case_errors}), 'mixed-case MIME-Version still receives MIME syntax validation');

for my $case (
    ['Newsgroups', 'local..test', 'malformed Newsgroups is rejected'],
    ['Followup-To', 'local.test,,comp.test', 'malformed Followup-To is rejected'],
    ['Distribution', 'All', 'reserved Distribution All is rejected'],
    ['Date', '2026-10-08', 'ISO-only Date accepted by Date::Parse is rejected by RFC grammar'],
    ['References', '<ok@example.invalid> garbage', 'garbage in References is rejected'],
    ['Supersedes', '<bad id@example.invalid>', 'malformed Supersedes is rejected'],
    ['MIME-Version', '2.0', 'invalid MIME-Version is rejected'],
    ['Content-Transfer-Encoding', 'rot13', 'invalid Content-Transfer-Encoding is rejected'],
    ['Content-Type', 'text/plain; charset="unterminated', 'unterminated Content-Type parameter is rejected'],
    ['Content-Disposition', 'inline; filename="unterminated', 'unterminated Content-Disposition parameter is rejected'],
    ['User-Agent', 'Reader/1.0 bad/product/extra', 'invalid User-Agent product grammar is rejected'],
    ['Content-Language', 'en_US', 'invalid Content-Language syntax is rejected'],
    ['Path', 'bad path!not-for-mail', 'invalid Path identity is rejected'],
    ['Xref', 'server.example local..test:1', 'invalid Xref newsgroup is rejected'],
) {
    my ($field, $value, $name) = @{$case};
    my $h = valid_article($field => $value);
    my ($v) = validate_article($h, "body\n");
    ok(!$v, $name);
}

my $both = valid_article(Control => 'cancel <first@example.invalid>', Supersedes => '<first@example.invalid>');
my ($both_ok, $both_errors) = validate_article($both, "body\n");
ok(!$both_ok, 'Control and Supersedes cannot coexist');
ok(grep({ ($_->{reason}//'') eq 'control-and-supersedes-mutually-exclusive' } @{$both_errors}), 'mutual exclusion reason is explicit');

my $nonascii = valid_article(Subject => "raw \x{e9} subject");
my ($nonascii_ok) = validate_article($nonascii, "body\n");
ok(!$nonascii_ok, 'raw non-ASCII header octet is rejected');

my $injected_newline = valid_article(Subject => "safe\nInjected: value");
my ($newline_ok) = validate_article($injected_newline, "body\n");
ok(!$newline_ok, 'bare newline/header injection is rejected');

my $control_octet = valid_article(Subject => "bad\x01control");
my ($control_octet_ok) = validate_article($control_octet, "body\n");
ok(!$control_octet_ok, 'forbidden ASCII control octet in a header is rejected');

my ($long_body_ok, $long_body_errors) = validate_article(valid_article(), ('x' x 999) . "\n");
ok(!$long_body_ok, 'RFC 5322 hard body line limit is enforced independently of local policy');
ok(grep({ ($_->{reason}//'') eq 'body-line-too-long' } @{$long_body_errors}), 'body line limit reason is explicit');

# Exercise the real header transformer on the exact class of field that caused
# the public report.  Preserve mode must still parse and serialize safely.
{
    my $config = base_config();
    $config->{headers}{path}{mode} = 'preserve';
    my $headers = valid_article('Injection-Info' => $neodome);
    my $context = build_context(config => $config, headers => $headers);
    my $result = Postfilter::HeaderTransform->apply($context);
    ok($result->is_pass, 'HeaderTransform accepts valid Neodome Injection-Info');
    is($context->{headers}{'Injection-Info'}, $neodome, 'HeaderTransform does not append trailing semicolon');
    my ($after_ok, $after_errors) = validate_article($context->{headers}, $context->{body}, phase => 'post-transform');
    ok($after_ok, 'article remains RFC-valid after all header transformations') or diag explain $after_errors;
}

# INN commonly folds Injection-Info at a semicolon boundary.  This is explicitly
# valid RFC 5536 syntax and the transformer must accept it before serializing.
{
    my $config = base_config();
    $config->{headers}{path}{mode} = 'preserve';
    my $headers = valid_article('Injection-Info' => $folded_injection);
    my $context = build_context(config => $config, headers => $headers);
    my $result = Postfilter::HeaderTransform->apply($context);
    ok($result->is_pass, 'HeaderTransform accepts INN-style folded Injection-Info');
    unlike($context->{headers}{'Injection-Info'}, qr/[\r\n]/, 'HeaderTransform emits logical unfolded Injection-Info');
    my ($after_ok, $after_errors) = validate_article($context->{headers}, $context->{body}, phase => 'post-transform');
    ok($after_ok, 'folded Injection-Info remains RFC-valid after transformation') or diag explain $after_errors;
}

# RFC 5537 says a pre-existing Injection-Date MUST NOT be modified or replaced.
# The legacy delete_posting_date option may remove only NNTP-Posting-Date.
{
    my $config = base_config();
    $config->{headers}{delete_posting_date} = 1;
    $config->{headers}{path}{mode} = 'preserve';
    my $date = current_rfc_date();
    my $headers = valid_article(
        'Injection-Date' => $date,
        'NNTP-Posting-Date' => $date,
    );
    my $context = build_context(config => $config, headers => $headers);
    my $result = Postfilter::HeaderTransform->apply($context);
    ok($result->is_pass, 'legacy posting-date cleanup completes');
    is($context->{headers}{'Injection-Date'}, $date, 'pre-existing Injection-Date is preserved exactly');
    ok(!defined($context->{headers}{'NNTP-Posting-Date'}), 'deprecated NNTP-Posting-Date is removed');
}

# End-to-end pipeline fixture: many real Netnews/MIME headers enter the same
# path used by nnrpd.  The final invariant checks the transformed article, not
# merely individual helper functions.
{
    my $config = base_config();
    $config->{headers}{path}{mode} = 'preserve';
    $config->{headers}{allow_supersedes} = 1;
    $config->{distributions} = [qw(world local)];
    my $logger = test_logger();
    my $headers = valid_article(Distribution => 'world');
    my $context = build_context(config => $config, headers => $headers, logger => $logger, body => "A plain text article.\nAnother line.\n");
    my $engine = bless { logger => $logger }, 'Postfilter::NG';
    my $result = $engine->_run_pipeline($context);
    ok($result->is_pass, 'complex RFC-compliant article passes the actual Postfilter pipeline') or diag explain $result;
    my ($final_ok, $final_errors) = validate_article($context->{headers}, $context->{body}, phase => 'post-transform');
    ok($final_ok, 'actual pipeline output is RFC-compliant') or diag explain $final_errors;
}

# Regression for the exact lifecycle used by INN: ProcessHeaders has already
# added the leading POSTED diagnostic when filter_post runs, but innd has not
# yet prepended the server path-identity.  This is the form that produced the
# real paganini PF-RFC-117 false positive.
{
    my $config = base_config();
    $config->{headers}{path}{mode} = 'preserve';
    my $logger = test_logger();
    my $headers = valid_article(Path => $paganini_staging_path);
    my $context = build_context(config => $config, headers => $headers, logger => $logger, body => "test body\n");
    my $engine = bless { logger => $logger }, 'Postfilter::NG';
    my $result = $engine->_run_pipeline($context);
    ok($result->is_pass, 'paganini INN staging Path passes the actual Postfilter pipeline') or diag explain $result;
    is($context->{headers}{Path}, $paganini_staging_path, 'preserve mode leaves INN staging Path unchanged for innd finalization');
}

# Combined regression based on the real paganini post that exposed the Path
# lifecycle mistake.  Xref and the server path-identity are intentionally not
# present yet because innd adds those after the nnrpd Perl hook returns.
{
    my $config = base_config();
    $config->{headers}{path}{mode} = 'preserve';
    my $logger = test_logger();
    my $headers = {
        From => 'Ivo Gandolfo <usenet@bofh.team>',
        Newsgroups => 'aioe.test',
        Subject => 'Re: test ignore',
        Date => 'Fri, 9 Oct 2026 21:57:38 +0200',
        Organization => 'To protect and to server',
        'Message-ID' => '<11abgvi$154pb$1@paganini.bofh.team>',
        References => '<11abf9g$1515r$1@paganini.bofh.team>' . "\n " . '<11abfb6$151as$1@paganini.bofh.team>',
        'MIME-Version' => '1.0',
        'Content-Type' => 'text/plain; charset=UTF-8; format=flowed',
        'Content-Transfer-Encoding' => '7bit',
        'Injection-Date' => 'Fri, 9 Oct 2026 19:57:38 -0000 (UTC)',
        'Injection-Info' => qq{paganini.bofh.team; posting-host="194.116.8.238";
	logging-data="1217323"; mail-complaints-to="usenet\@bofh.team"},
        'User-Agent' => 'Mozilla Thunderbird',
        'In-Reply-To' => '<11abfb6$151as$1@paganini.bofh.team>',
        'Content-Language' => 'it',
        Path => $paganini_staging_path,
    };
    my ($hook_ok, $hook_errors) = validate_article(
        $headers,
        "test body\n",
        allow_inn_nnrpd_staging_path => 1,
    );
    ok($hook_ok, 'real paganini hook-stage headers validate together') or diag explain $hook_errors;
    my $context = build_context(config => $config, headers => $headers, logger => $logger, body => "test body\n");
    my $engine = bless { logger => $logger }, 'Postfilter::NG';
    my $result = $engine->_run_pipeline($context);
    ok($result->is_pass, 'real paganini hook-stage article passes the actual pipeline') or diag explain $result;
}

# A bad local transformation must never turn valid input into invalid output.
for my $mutation (
    [
        'invalid configured Path replacement is stopped by post-transform invariant',
        sub { my ($c) = @_; $c->{headers}{path}{mode} = 'replace'; $c->{headers}{path}{replacement} = 'bad path'; },
    ],
    [
        'invalid configured Sender replacement is stopped by post-transform invariant',
        sub { my ($c) = @_; $c->{headers}{sender}{mode} = 'replace'; $c->{headers}{sender}{replacement} = 'not a mailbox'; },
    ],
    [
        'invalid configured custom header name is stopped by post-transform invariant',
        sub { my ($c) = @_; $c->{headers}{include_new_headers} = 1; $c->{new_headers}{'Bad Header'} = 'value'; },
    ],
    [
        'invalid configured custom header value is stopped by post-transform invariant',
        sub { my ($c) = @_; $c->{headers}{include_new_headers} = 1; $c->{new_headers}{'X-Test'} = "safe\nInjected: yes"; },
    ],
) {
    my ($name, $change) = @{$mutation};
    my $config = base_config();
    $config->{headers}{path}{mode} = 'preserve';
    $change->($config);
    my $logger = test_logger();
    my $context = build_context(config => $config, headers => valid_article(), logger => $logger);
    my $engine = bless { logger => $logger }, 'Postfilter::NG';
    my $result = $engine->_run_pipeline($context);
    is($result->code, 'PF-RFC-118', $name);
}

# RFC failures should identify the exact field and validator subreason in the
# operational article_result log, not merely the umbrella PF-RFC code.
{
    package TestPostfilter::RFCLogLoader;
    sub new { bless { config => $_[1] }, $_[0] }
    sub maybe_reload { return $_[0]{config} }
}
{
    my $config = base_config();
    $config->{policy}{mode} = 'audit';
    $config->{logging}{log_accepted} = 1;
    my $logger = test_logger();
    my $engine = bless {
        config   => $config,
        crypto   => Postfilter::Crypto->new(logger => $logger),
        database => undef,
        loader   => TestPostfilter::RFCLogLoader->new($config),
        logger   => $logger,
        suffixes => {},
    }, 'Postfilter::NG';
    $engine->process_article(
        attributes => { hostname => 'localhost', ipaddress => '127.0.0.1', interface => 'localhost' },
        headers => valid_article('Injection-Info' => $neodome . ';'),
        body => "body\n",
        user => 'tester',
    );
    my ($event) = grep { $_->{message} eq 'article_result' } @{ $logger->{events} };
    ok($event, 'RFC failure emits article_result');
    is($event->{fields}{detail_header}, 'Injection-Info', 'article_result identifies failing RFC header');
    is($event->{fields}{detail_reason}, 'invalid-injection-info', 'article_result identifies RFC validator subreason');
}

# The preflight is deliberately ahead of trusted full-bypass and audit mode.
{
    my $config = base_config();
    $config->{policy}{mode} = 'audit';
    $config->{trusted_profile} = [{
        id => 'all-trusted', enabled => 1, priority => 9999, match_all => 1,
        full_bypass => 1,
    }];
    my $logger = test_logger();
    my $headers = valid_article('Injection-Info' => $neodome . ';');
    my $context = build_context(config => $config, headers => $headers, logger => $logger);
    my $engine = bless { logger => $logger }, 'Postfilter::NG';
    my $result = $engine->_run_pipeline($context);
    is($result->code, 'PF-RFC-117', 'RFC-invalid input cannot be bypassed by audit or full trusted profile');
}

done_testing();
