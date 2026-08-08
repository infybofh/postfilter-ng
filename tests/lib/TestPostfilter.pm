package TestPostfilter;

use strict;
use warnings;

use Exporter 'import';
use File::Temp qw(tempdir);

use Postfilter::Context;
use Postfilter::Crypto;

our @EXPORT_OK = qw(
    base_config
    build_context
    current_rfc_date
    temporary_environment
    test_logger
);

# Return a complete, deliberately conservative configuration hash suitable for
# pure unit tests.  Individual tests clone or modify only the section under
# examination.  This avoids loading TOML and keeps failures local to the module
# being tested.
sub base_config {
    my $temporary = tempdir(CLEANUP => 1);

    return {
        _meta => {
            generation => 'test-generation',
        },
        article_types => {
            mode => 'text-only',
            pattern_syntax => 'glob',
            mixed_crosspost_policy => 'reject',
            binary_group_patterns => [
                '*.bin*',
                'alt.b',
                'alt.bin*',
                'alt.binaries.*',
                'alt.dvdnordic.*',
                '*.bain*',
                '*.biana*',
                '*.biinaries*',
                '*bina*',
                '*.bineries*',
                '*.binia*',
                '*.binries*',
                '*.cd.image*',
                '*.files.images*',
                '*.mp3*',
                '*music.bin*',
                '*.pictures*',
                '*porno.images*',
                '*images*',
                '*.warez*',
            ],
            text => {
                limits => {
                    max_body_size => 32_768,
                    max_header_size => 8_192,
                    max_total_size => 40_960,
                    max_body_scan_bytes => 32_768,
                },
                content => {
                    allow_html => 0,
                    allow_uuencode => 0,
                    allow_yenc => 0,
                },
                mime => {
                    enabled => 1,
                    reject_multipart_mixed => 1,
                    reject_unlisted_multipart => 1,
                    reject_attachment_disposition => 1,
                    reject_filename_parameter => 1,
                    allow_attachment_disposition_for_allowed_media => 1,
                    on_malformed => 'reject',
                    max_mime_depth => 8,
                    max_mime_parts => 100,
                    allowed_media_max_decoded_bytes => 262_144,
                    armored_block_max_bytes => 262_144,
                    base64_heuristic_enabled => 1,
                    base64_min_contiguous_lines => 12,
                    base64_min_line_length => 60,
                    base64_max_line_length => 0,
                    base64_min_decoded_bytes => 4_096,
                    base64_single_line_min_decoded_bytes => 8_192,
                    base64_ignore_quoted_lines => 1,
                    base64_ignore_indented_lines => 0,
                    allowed_multipart_types => [
                        'multipart/alternative',
                        'multipart/signed',
                    ],
                    allowed_media_types => [
                        'application/pgp-signature',
                        'application/pgp-keys',
                        'application/pkcs7-signature',
                        'application/x-pkcs7-signature',
                        'application/pkix-cert',
                        'application/x-x509-ca-cert',
                        'application/pem-certificate-chain',
                    ],
                    forbidden_media_types => [
                        'application/*',
                        'audio/*',
                        'font/*',
                        'image/*',
                        'message/rfc822',
                        'model/*',
                        'video/*',
                    ],
                    allowed_armored_block_types => [
                        'PGP SIGNATURE',
                        'PGP PUBLIC KEY BLOCK',
                        'PGP PRIVATE KEY BLOCK',
                        'CERTIFICATE',
                        'X509 CERTIFICATE',
                    ],
                },
                checks => { skip => [] },
                save_rejected => {
                    mode => 'none',
                    reason_codes => [],
                    compatibility_codes => [],
                    rule_ids => [],
                    subdirectory => 'text',
                },
            },
            binary => {
                limits => {
                    max_body_size => 10_485_760,
                    max_header_size => 65_536,
                    max_total_size => 10_551_296,
                    max_body_scan_bytes => 1_048_576,
                },
                content => {
                    allow_html => 0,
                    allow_uuencode => 1,
                    allow_yenc => 1,
                },
                mime => {
                    enabled => 0,
                    reject_multipart_mixed => 0,
                    reject_unlisted_multipart => 0,
                    reject_attachment_disposition => 0,
                    reject_filename_parameter => 0,
                    allow_attachment_disposition_for_allowed_media => 1,
                    on_malformed => 'accept',
                    max_mime_depth => 8,
                    max_mime_parts => 500,
                    allowed_media_max_decoded_bytes => 10_485_760,
                    armored_block_max_bytes => 1_048_576,
                    base64_heuristic_enabled => 0,
                    base64_min_contiguous_lines => 12,
                    base64_min_line_length => 60,
                    base64_max_line_length => 0,
                    base64_min_decoded_bytes => 4_096,
                    base64_single_line_min_decoded_bytes => 8_192,
                    base64_ignore_quoted_lines => 1,
                    base64_ignore_indented_lines => 0,
                    allowed_multipart_types => [],
                    allowed_media_types => [],
                    forbidden_media_types => [],
                    allowed_armored_block_types => [],
                },
                checks => {
                    skip => [
                        'style.line_statistics',
                        'style.html',
                        'style.content_type',
                        'badwords',
                        'uribl',
                    ],
                },
                save_rejected => {
                    mode => 'none',
                    reason_codes => [],
                    compatibility_codes => [],
                    rule_ids => [],
                    subdirectory => 'binary',
                },
            },
        },
        policy => {
            mode             => 'enforce',
            server_status    => 'active',
            action_on_accept => 'accept',
            action_on_reject => 'reject',
            show_error_code  => 1,
        },
        logging => {
            verbosity => 1,
        },
        resilience => {
            emergency_action => 'accept',
        },
        database => {
            enabled    => 0,
            on_failure => 'accept',
            privacy    => {
                identity_mode => 'plain',
            },
        },
        modules => {
            access      => 0,
            attachments => 1,
            badwords    => 0,
            banlist  => 0,
            content  => 1,
            custom   => 0,
            dates    => 1,
            groups   => 1,
            headers  => 1,
            rbl      => 0,
            style    => 1,
            surbl    => 0,
            tor      => 0,
            uribl    => 0,
            userdb   => 0,
        },
        limits => {
            absolute_multipost_limit => 100,
            default_multipost_limit  => 2,
            dns_cache_max_entries    => 100,
            max_blank_ratio          => 1,
            max_body_scan_bytes      => 1_048_576,
            max_body_size            => 1_048_576,
            max_crosspost            => 20,
            max_empty_ratio          => 1,
            max_followup             => 20,
            max_fup_no_crosspost     => 20,
            max_groups_difference    => 20,
            max_header_length        => 65_536,
            max_header_size          => 65_536,
            max_hierarchies_followup => 20,
            max_hierarchies_post     => 20,
            max_line_length          => 0,
            max_quoted_ratio         => 1,
            max_rule_evaluations     => 2_000,
            max_total_size           => 2_097_152,
            max_unique_domains       => 20,
            max_urls_to_check        => 20,
        },
        timeouts => {
            dns_query_seconds     => 1,
            dns_total_seconds     => 1,
            future_grace_seconds  => 3_600,
            max_processing_ms     => 2_700,
            on_processing_timeout => 'reject',
            too_old_seconds       => 31_536_000,
        },
        headers => {
            allow_control_cancel     => 0,
            allow_html               => 0,
            allow_mail_headers       => 0,
            allow_supersedes         => 0,
            allow_uuencode           => 0,
            allow_yenc               => 0,
            check_distribution       => 0,
            check_groups_existence   => 0,
            delete_custom_headers    => 0,
            delete_mail_headers      => 0,
            delete_user_agent        => 0,
            delete_x_no_archive      => 0,
            delete_x_trace           => 0,
            force_default_organization => 0,
            include_new_headers      => 0,
            from => {
                mode => 'preserve',
            },
            sender => {
                mode => 'preserve',
            },
            path => {
                mode => 'preserve',
            },
            posting_account => {
                mode => 'preserve',
            },
            posting_host => {
                mode => 'preserve',
            },
        },
        access => {
            authenticated_limits => {},
            domain_limits        => {},
            enable_domain_check  => 1,
            period_seconds       => 86_400,
            public_limits        => {},
            public_user_ids      => ['', 'anonymous'],
            public_user_pattern  => '',
            server_type          => 'both',
            separate_counters_by_article_type => 1,
            short_period_seconds => 600,
        },
        badwords => {
            max_body_score    => 0,
            max_subject_score => 0,
        },
        banlist => {
            max_score          => 10,
            side_effect_failure => 'reject',
        },
        tor => {
            action             => 'allow',
            enabled            => 0,
            local_tor_networks => [],
            node_scope         => 'all',
            header => {
                mode => 'none',
            },
        },
        custom => {
            module_file => '',
            on_error    => 'accept',
        },
        paths => {
            active_file        => "$temporary/active",
            public_suffix_file => "$temporary/public_suffix_list.dat",
            saved_dir          => "$temporary/saved",
            state_dir          => "$temporary/state",
        },
        keys => {},
        retention => {
            config_generations => 32,
            events        => 'forever',
            rule_hits     => 'forever',
            saved_articles => 'forever',
            provider_health_seconds => 604_800,
        },
        saved_articles => {
            directory_layout => 'flat',
            on_failure       => 'continue',
        },
        html_report => {
            enabled => 0,
            privacy => {
                identity_mode => 'hmac',
            },
        },
        access_profile          => [],
        badword                => [],
        ban_rule               => [],
        content_type_rule      => [],
        distributions          => [],
        dnsbl                  => [],
        forbidden_crosspost    => [],
        forbidden_groups       => [],
        forbidden_header_rule => [],
        html_allowed_groups    => [],
        html_patterns          => ['<html', '<script', '<iframe'],
        moderated_exceptions   => [],
        new_headers             => {},
        saved_headers           => [],
        surbl                  => [],
        trusted_profile        => [],
        uribl                  => [],
    };
}

sub current_rfc_date {
    my @weekday = qw(Sun Mon Tue Wed Thu Fri Sat);
    my @month = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime();

    return sprintf(
        '%s, %02d %s %04d %02d:%02d:%02d +0000',
        $weekday[$wday],
        $mday,
        $month[$mon],
        $year + 1900,
        $hour,
        $min,
        $sec,
    );
}

sub test_logger {
    return bless {
        events => [],
    }, 'TestPostfilter::Logger';
}

sub build_context {
    my (%arguments) = @_;

    my $config = $arguments{config} // base_config();
    my $logger = $arguments{logger} // test_logger();
    my $headers = $arguments{headers} // {
        From       => 'Example User <example@example.invalid>',
        Newsgroups => 'local.test',
        Subject    => 'Test article',
        Date       => current_rfc_date(),
        'Message-ID' => '<test-article@postfilter.invalid>',
    };

    return Postfilter::Context->new(
        attributes => $arguments{attributes} // {
            hostname  => 'client.example.invalid',
            ipaddress => '192.0.2.25',
            interface => 'reader.example.invalid',
        },
        body       => $arguments{body} // "A small test article.\n",
        config     => $config,
        crypto     => Postfilter::Crypto->new(logger => $logger),
        db         => $arguments{db},
        headers    => $headers,
        logger     => $logger,
        suffixes   => {},
        user       => defined $arguments{user} ? $arguments{user} : '',
    );
}

sub temporary_environment {
    return tempdir(CLEANUP => 1);
}

package TestPostfilter::Logger;

sub _store {
    my ($self, $level, $message, %fields) = @_;
    push @{ $self->{events} }, {
        level   => $level,
        message => $message,
        fields  => \%fields,
    };
    return;
}

for my $method (qw(
    database error fatal headers identity pipeline reputation result rules
    structural trace warning
)) {
    no strict 'refs';
    *{$method} = sub {
        my ($self, $message, %fields) = @_;
        return $self->_store($method, $message, %fields);
    };
}

sub set_verbosity { return; }
sub set_options   { return; }

1;
