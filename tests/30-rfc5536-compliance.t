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

ok(valid_message_id('<simple@example.invalid>'), 'valid Message-ID passes');
ok(!valid_message_id('<bad id@example.invalid>'), 'Message-ID containing whitespace is rejected');
ok(!valid_message_id(('<' . ('a' x 245) . '@x.invalid>')), 'Message-ID over 250 octets is rejected');

my $complex = valid_article();
my ($ok, $errors) = validate_article($complex, "First body line.\nSecond body line.\n", phase => 'pre-transform');
ok($ok, 'complex article with broad RFC/MIME header coverage validates') or diag explain $errors;

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
