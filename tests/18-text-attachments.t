# Test purpose: Verifies strict text-world MIME attachment handling without
# rejecting ordinary PGP/GnuPG signatures, public keys, certificates or short
# technical Base64 examples.

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib", "$Bin/lib";

use Test::More;

use Postfilter::Checks::Attachments;
use Postfilter::Checks::Style;
use TestPostfilter qw(base_config build_context current_rfc_date);

sub text_context {
    my (%arguments) = @_;

    my $config = $arguments{config} // base_config();
    $config->{modules}{dates} = 0;
    $config->{modules}{groups} = 0;

    my $headers = {
        From         => 'Example User <example@example.invalid>',
        Newsgroups   => 'it.test',
        Subject      => 'Attachment policy test',
        Date         => current_rfc_date(),
        'Message-ID' => '<attachment-test@postfilter.invalid>',
        %{ $arguments{headers} // {} },
    };

    return build_context(
        body    => $arguments{body} // "Ordinary text body.\n",
        config  => $config,
        headers => $headers,
    );
}

sub run_structural_and_attachment_checks {
    my ($context) = @_;

    my $style = Postfilter::Checks::Style->run($context);
    return $style unless $style->is_pass;

    return Postfilter::Checks::Attachments->run($context);
}

sub repeated_base64 {
    my ($lines, $width) = @_;
    $lines //= 90;
    $width //= 64;
    return join('', map { ('A' x $width) . "\n" } 1 .. $lines);
}

{
    my $result = run_structural_and_attachment_checks(text_context());
    ok($result->is_pass, 'ordinary text/plain article passes attachment checks');
}

{
    my $context = text_context(
        headers => {
            'Content-Type' => 'multipart/mixed; boundary="mixed-boundary"',
        },
        body => <<'BODY',
--mixed-boundary
Content-Type: text/plain

Text part.
--mixed-boundary
Content-Type: application/octet-stream
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="payload.zip"

QUJDRA==
--mixed-boundary--
BODY
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 109, 'multipart/mixed is rejected in text groups');
    is($result->code, 'PF-MIME-109', 'multipart/mixed has a dedicated symbolic code');
}

{
    my $context = text_context(
        headers => {
            'Content-Type' => 'application/octet-stream',
        },
        body => repeated_base64(20),
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 110, 'top-level application/octet-stream is rejected');
}

{
    my $context = text_context(
        headers => {
            'Content-Type' => 'text/plain',
            'Content-Disposition' => 'attachment; filename="notes.txt"',
        },
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 111, 'Content-Disposition attachment is rejected');
}

{
    my $context = text_context(
        headers => {
            'Content-Type' => 'text/plain; name="hidden.bin"',
            'Content-Disposition' => 'inline; filename="hidden.bin"',
        },
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 111, 'inline filename metadata is treated as an attachment');
}

{
    my $context = text_context(body => repeated_base64(90));
    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 112, 'large unlabelled Base64 block is rejected');
    cmp_ok(
        $result->{estimated_decoded_bytes},
        '>=',
        4_096,
        'Base64 rejection reports the estimated decoded size',
    );
}

{
    my $context = text_context(
        body => "A short technical example follows:\n"
            . repeated_base64(3)
            . "End of example.\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    ok($result->is_pass, 'short Base64 technical example stays below thresholds');
}

{
    my $quoted = repeated_base64(90);
    $quoted =~ s/^/> /mg;
    my $context = text_context(
        body => "Quoted example from a previous article:\n$quoted",
    );

    my $result = run_structural_and_attachment_checks($context);
    ok($result->is_pass, 'quoted long Base64 example is ignored by default');
}

{
    my $signature = repeated_base64(90);
    my $context = text_context(
        body => "A signed message.\n\n"
            . "-----BEGIN PGP SIGNATURE-----\n"
            . "Version: GnuPG v2\n\n"
            . $signature
            . "-----END PGP SIGNATURE-----\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    ok($result->is_pass, 'ASCII-armoured GnuPG signature is not mistaken for attachment');
}

{
    my $certificate = repeated_base64(70);
    my $context = text_context(
        body => "Certificate example:\n"
            . "-----BEGIN CERTIFICATE-----\n"
            . $certificate
            . "-----END CERTIFICATE-----\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    ok($result->is_pass, 'bounded PEM certificate block is excluded from heuristic');
}

{
    my $boundary = 'signed-boundary';
    my $context = text_context(
        headers => {
            'Content-Type' =>
                'multipart/signed; protocol="application/pgp-signature"; '
                . "boundary=\"$boundary\"",
        },
        body => "--$boundary\n"
            . "Content-Type: text/plain; charset=UTF-8\n\n"
            . "This is the signed text.\n"
            . "--$boundary\n"
            . "Content-Type: application/pgp-signature; name=signature.asc\n"
            . "Content-Transfer-Encoding: base64\n"
            . "Content-Disposition: attachment; filename=signature.asc\n\n"
            . repeated_base64(30)
            . "--$boundary--\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    ok($result->is_pass, 'multipart/signed PGP/MIME message is accepted');
}

{
    my $boundary = 'bad-signed-boundary';
    my $context = text_context(
        headers => {
            'Content-Type' =>
                "multipart/signed; boundary=\"$boundary\"",
        },
        body => "--$boundary\n"
            . "Content-Type: text/plain\n\nText.\n"
            . "--$boundary\n"
            . "Content-Type: application/octet-stream\n\n"
            . "payload\n"
            . "--$boundary--\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 110, 'forbidden application part is rejected inside multipart/signed');
}

{
    my $context = text_context(
        headers => {
            'Content-Type' => 'multipart/signed; protocol="application/pgp-signature"',
        },
        body => "No boundary is present.\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 113, 'malformed allowed multipart is rejected by strict default');
}

{
    my $context = text_context(
        headers => {
            'Content-Type' => 'multipart/encrypted; boundary="encrypted"',
        },
        body => "--encrypted\nContent-Type: text/plain\n\nVersion: 1\n"
            . "--encrypted--\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 114, 'unapproved multipart container is rejected');
}

{
    my $config = base_config();
    $config->{article_types}{text}{mime}{on_malformed} = 'accept';
    my $context = text_context(
        config => $config,
        headers => {
            'Content-Type' => 'multipart/signed',
        },
    );

    my $result = run_structural_and_attachment_checks($context);
    ok($result->is_pass, 'on_malformed=accept fails open for MIME parsing only');
}

{
    my $config = base_config();
    $config->{article_types}{text}{mime}{base64_min_decoded_bytes} = 20_000;
    my $context = text_context(
        config => $config,
        body => repeated_base64(90),
    );

    my $result = run_structural_and_attachment_checks($context);
    ok($result->is_pass, 'Base64 decoded-byte threshold is operator configurable');
}

{
    my $config = base_config();
    $config->{article_types}{text}{mime}{allowed_media_max_decoded_bytes} = 64;
    my $context = text_context(
        config => $config,
        headers => {
            'Content-Type' => 'application/pgp-signature',
            'Content-Transfer-Encoding' => 'base64',
        },
        body => repeated_base64(3),
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 110, 'oversized permitted signature media is still rejected');
}

{
    my $config = base_config();
    $config->{modules}{attachments} = 0;
    my $context = text_context(
        config => $config,
        headers => {
            'Content-Type' => 'application/octet-stream',
        },
        body => repeated_base64(20),
    );

    my $result = run_structural_and_attachment_checks($context);
    is(
        $result->legacy,
        5,
        'disabling attachment defense restores historical Content-Type rejection',
    );
}


{
    my $config = base_config();
    $config->{article_types}{mode} = 'mixed';
    my $context = build_context(
        config => $config,
        headers => {
            From         => 'Binary Poster <binary@example.invalid>',
            Newsgroups   => 'alt.binaries.example',
            Subject      => 'MIME binary attachment',
            Date         => current_rfc_date(),
            'Message-ID' => '<binary-mime@postfilter.invalid>',
            'Content-Type' => 'multipart/mixed; boundary="binary"',
        },
        body => "--binary\n"
            . "Content-Type: application/octet-stream\n"
            . "Content-Disposition: attachment; filename=file.bin\n\n"
            . repeated_base64(20)
            . "--binary--\n",
    );

    is($context->{article_type}, 'binary', 'binary group selects binary profile');
    my $result = Postfilter::Checks::Attachments->run($context);
    ok($result->is_pass, 'binary profile does not apply strict text attachment policy');
}


{
    my $context = text_context(
        headers => {
            'Content-Type' => 'text/plain',
            'Content-Disposition' =>
                "inline; filename*=UTF-8''hidden%20payload.bin",
        },
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 111, 'RFC 2231 filename metadata is treated as attachment evidence');
}

{
    my $config = base_config();
    $config->{article_types}{text}{mime}{base64_single_line_min_decoded_bytes} = 1_024;
    my $context = text_context(
        config => $config,
        body => ('A' x 2_000) . "\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    is($result->legacy, 112, 'single very long Base64 line cannot evade line-count policy');
    is($result->{base64_lines}, 1, 'single-line rejection records one encoded line');
}

{
    my $config = base_config();
    $config->{article_types}{text}{limits}{max_body_size} = 100_000;
    $config->{article_types}{text}{limits}{max_total_size} = 120_000;
    $config->{article_types}{text}{limits}{max_body_scan_bytes} = 128;
    my $boundary = 'long-signed';
    my $context = text_context(
        config => $config,
        headers => {
            'Content-Type' => "multipart/signed; boundary=\"$boundary\"",
        },
        body => "--$boundary\n"
            . "Content-Type: text/plain\n\n"
            . ('ordinary signed text ' x 400)
            . "\n--$boundary\n"
            . "Content-Type: application/pgp-signature\n"
            . "Content-Transfer-Encoding: base64\n\n"
            . "aGVsbG8=\n"
            . "--$boundary--\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    ok(
        $result->is_pass,
        'MIME parser sees complete body even when Base64 scan budget is small',
    );
}


{
    my $boundary = 'empty-header-boundary';
    my $context = text_context(
        headers => {
            'Content-Type' => "multipart/signed; boundary=\"$boundary\"",
        },
        body => "--$boundary\r\n"
            . "Content-Type: text/plain\r\n"
            . "X-Optional-Field:\r\n\r\n"
            . "Signed text with an empty extension header.\r\n"
            . "--$boundary\r\n"
            . "Content-Type: application/pgp-signature\r\n\r\n"
            . "aGVsbG8=\r\n"
            . "--$boundary--\r\n",
    );

    my $result = run_structural_and_attachment_checks($context);
    ok($result->is_pass, 'an empty MIME part header value is accepted');
}

{
    my $boundary = 'byte-identity-boundary';
    my $original_body = "--$boundary\r\n"
        . "Content-Type: text/plain; charset=UTF-8\r\n\r\n"
        . "Signed bytes must remain exactly unchanged.  \r\n"
        . "--$boundary\r\n"
        . "Content-Type: application/pgp-signature\r\n"
        . "Content-Transfer-Encoding: base64\r\n\r\n"
        . "aGVsbG8=\r\n"
        . "--$boundary--\r\n";
    my $context = text_context(
        headers => {
            'Content-Type' => "multipart/signed; boundary=\"$boundary\"",
        },
        body => $original_body,
    );

    my $result = run_structural_and_attachment_checks($context);
    ok($result->is_pass, 'multipart/signed fixture passes attachment policy');
    is(
        $context->{body},
        $original_body,
        'multipart/signed body remains byte-for-byte identical',
    );
}

{
    my $policy = base_config()->{article_types}{text}{mime};
    my $bounded = "-----BEGIN PGP SIGNATURE-----\n"
        . repeated_base64(10)
        . "-----END PGP SIGNATURE-----\n";
    my $cleaned = Postfilter::Checks::Attachments::_remove_allowed_armoured_blocks(
        $bounded,
        $policy,
    );
    is($cleaned, "\n", 'a complete bounded armoured block is removed from the scan copy');

    my $oversized_policy = { %{$policy}, armored_block_max_bytes => 64 };
    my $preserved = Postfilter::Checks::Attachments::_remove_allowed_armoured_blocks(
        $bounded,
        $oversized_policy,
    );
    is($preserved, $bounded, 'an oversized armoured block remains visible to the heuristic');
}

{
    my $policy = base_config()->{article_types}{text}{mime};
    my $adversarial = "-----BEGIN PGP MESSAGE-----\n" x 40_000;
    my ($completed, $result);

    local $SIG{ALRM} = sub { die "armour scan timeout\n" };
    eval {
        alarm 5;
        $result = Postfilter::Checks::Attachments::_remove_allowed_armoured_blocks(
            $adversarial,
            $policy,
        );
        alarm 0;
        $completed = 1;
        1;
    } or do {
        alarm 0;
        diag($@ || 'unknown armour scan failure');
    };

    ok($completed, 'unterminated armour scan completes within the bounded test time');
    is($result, $adversarial, 'unterminated armour remains visible to Base64 analysis');
}

done_testing;
