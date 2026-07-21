package Postfilter::Config;

use strict;
use warnings;

=head1 NAME

Postfilter::Config - Standards-based TOML loading with last-known-good fallback.

=head1 RESPONSIBILITIES

=over 4

=item * Parse the main TOML file and sorted C<conf.d/*.toml> fragments.

=item * Apply defaults and validate values before an article can see them.

=item * Disable an individual malformed optional rule instead of disabling the
whole filter.

=item * Save every accepted configuration as a canonical JSON generation.

=item * Recover from a bad edit by using the previous in-memory configuration,
a persistent last-known-good snapshot, or an embedded minimal configuration.

=back

Postfilter-NG uses C<TOML::Tiny> for configuration parsing. The installer treats
it as a required runtime dependency. A new nnrpd process can load the JSON
last-known-good snapshot when TOML parsing is temporarily unavailable.

=cut

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use JSON::PP;
use Scalar::Util qw(blessed looks_like_number);

use Postfilter::Util qw(atomic_write now_iso slurp);

my %APPEND_ARRAY = map { $_ => 1 } qw(
    access_profile
    badword
    ban_rule
    content_type_rule
    dnsbl
    forbidden_crosspost
    forbidden_header_rule
    surbl
    trusted_profile
    uribl
);

my %KNOWN_TOP_LEVEL = map { $_ => 1 } qw(
    _meta
    access
    access_profile
    article_types
    badword
    badwords
    ban_rule
    banlist
    compatibility
    content_type_rule
    custom
    database
    distributions
    dnsbl
    forbidden_crosspost
    forbidden_groups
    forbidden_header_rule
    headers
    html_allowed_groups
    html_patterns
    html_report
    keys
    limits
    logging
    mail_headers
    moderated_exceptions
    modules
    new_headers
    paths
    policy
    resilience
    retention
    saved_articles
    saved_headers
    surbl
    timeouts
    tor
    trusted_profile
    uribl
    userdb
);

# Fixed configuration tables reject unknown member names.  Dynamic tables such
# as new_headers and arrays of rules are validated by their specialised parsers.
# Keeping this schema next to the loader prevents a misspelled option from
# becoming a silent, non-functional placebo.
my %KNOWN_SECTION_KEY = (
    article_types => { map { $_ => 1 } qw(
        binary_group_patterns mixed_crosspost_policy mode pattern_syntax
        binary text
    ) },
    'article_types.text' => { map { $_ => 1 } qw(
        checks content limits mime save_rejected
    ) },
    'article_types.binary' => { map { $_ => 1 } qw(
        checks content limits mime save_rejected
    ) },
    'article_types.text.checks' => { map { $_ => 1 } qw(skip) },
    'article_types.binary.checks' => { map { $_ => 1 } qw(skip) },
    'article_types.text.content' => { map { $_ => 1 } qw(
        allow_html allow_uuencode allow_yenc
    ) },
    'article_types.binary.content' => { map { $_ => 1 } qw(
        allow_html allow_uuencode allow_yenc
    ) },
    'article_types.text.mime' => { map { $_ => 1 } qw(
        allow_attachment_disposition_for_allowed_media
        allowed_armored_block_types allowed_media_max_decoded_bytes
        allowed_media_types allowed_multipart_types armored_block_max_bytes
        base64_heuristic_enabled base64_ignore_indented_lines
        base64_ignore_quoted_lines base64_max_line_length
        base64_min_contiguous_lines base64_min_decoded_bytes
        base64_min_line_length base64_single_line_min_decoded_bytes
        enabled forbidden_media_types max_mime_depth
        max_mime_parts on_malformed reject_attachment_disposition
        reject_filename_parameter reject_multipart_mixed
        reject_unlisted_multipart
    ) },
    'article_types.binary.mime' => { map { $_ => 1 } qw(
        allow_attachment_disposition_for_allowed_media
        allowed_armored_block_types allowed_media_max_decoded_bytes
        allowed_media_types allowed_multipart_types armored_block_max_bytes
        base64_heuristic_enabled base64_ignore_indented_lines
        base64_ignore_quoted_lines base64_max_line_length
        base64_min_contiguous_lines base64_min_decoded_bytes
        base64_min_line_length base64_single_line_min_decoded_bytes
        enabled forbidden_media_types max_mime_depth
        max_mime_parts on_malformed reject_attachment_disposition
        reject_filename_parameter reject_multipart_mixed
        reject_unlisted_multipart
    ) },
    'article_types.text.save_rejected' => { map { $_ => 1 } qw(
        compatibility_codes mode reason_codes rule_ids subdirectory
    ) },
    'article_types.binary.save_rejected' => { map { $_ => 1 } qw(
        compatibility_codes mode reason_codes rule_ids subdirectory
    ) },
    'article_types.text.limits' => { map { $_ => 1 } qw(
        absolute_multipost_limit default_multipost_limit dns_cache_max_entries
        max_blank_ratio max_body_scan_bytes max_body_size max_crosspost
        max_empty_ratio max_followup max_fup_no_crosspost max_groups_difference
        max_header_length max_header_size max_hierarchies_followup
        max_hierarchies_post max_line_length max_quoted_ratio
        max_rule_evaluations max_total_size max_unique_domains max_urls_to_check
    ) },
    'article_types.binary.limits' => { map { $_ => 1 } qw(
        absolute_multipost_limit default_multipost_limit dns_cache_max_entries
        max_blank_ratio max_body_scan_bytes max_body_size max_crosspost
        max_empty_ratio max_followup max_fup_no_crosspost max_groups_difference
        max_header_length max_header_size max_hierarchies_followup
        max_hierarchies_post max_line_length max_quoted_ratio
        max_rule_evaluations max_total_size max_unique_domains max_urls_to_check
    ) },
    policy => { map { $_ => 1 } qw(
        action_on_accept action_on_reject mode server_status show_error_code
    ) },
    logging => { map { $_ => 1 } qw(
        include_rule_ids include_timing log_accepted log_rejected verbosity
    ) },
    resilience => { map { $_ => 1 } qw(
        emergency_action reload_interval_seconds
    ) },
    paths => { map { $_ => 1 } qw(
        active_file html_output public_suffix_file saved_dir sendmail state_dir
    ) },
    keys => { map { $_ => 1 } qw(
        database_privacy header_pseudonym html_report tor_header
    ) },
    database => { map { $_ => 1 } qw(
        busy_timeout_ms enabled on_failure path privacy synchronous
    ) },
    'database.privacy' => { map { $_ => 1 } qw(identity_mode key_file) },
    retention => { map { $_ => 1 } qw(
        events provider_health_seconds rule_hits saved_articles
    ) },
    modules => { map { $_ => 1 } qw(
        access attachments badwords banlist content custom dates groups headers rbl style
        surbl tor uribl userdb
    ) },
    limits => { map { $_ => 1 } qw(
        absolute_multipost_limit default_multipost_limit dns_cache_max_entries
        max_blank_ratio max_body_scan_bytes max_body_size max_crosspost
        max_empty_ratio max_followup max_fup_no_crosspost max_groups_difference
        max_header_length max_header_size max_hierarchies_followup
        max_hierarchies_post max_line_length max_quoted_ratio
        max_rule_evaluations max_total_size max_unique_domains
        max_urls_to_check
    ) },
    timeouts => { map { $_ => 1 } qw(
        dns_query_seconds dns_total_seconds future_grace_seconds
        max_processing_ms on_processing_timeout too_old_seconds
    ) },
    headers => { map { $_ => 1 } qw(
        allow_control_cancel allow_html allow_mail_headers allow_supersedes
        allow_uuencode allow_yenc check_distribution check_groups_existence
        delete_custom_headers delete_mail_headers delete_posting_date
        delete_user_agent delete_x_no_archive delete_x_trace
        force_default_organization include_new_headers organization path
        posting_account posting_host sender
    ) },
    'headers.sender' => { map { $_ => 1 } qw(
        mode pseudonym_domain replacement
    ) },
    'headers.posting_host' => { map { $_ => 1 } qw(mode replacement) },
    'headers.posting_account' => { map { $_ => 1 } qw(mode replacement) },
    'headers.path' => { map { $_ => 1 } qw(mode replacement) },
    access => { map { $_ => 1 } qw(
        article_digest_mode authenticated_limits domain_limits
        enable_domain_check period_seconds public_limits public_user_ids
        public_user_pattern separate_counters_by_article_type server_type
        short_period_seconds
    ) },
    'access.public_limits' => { map { $_ => 1 } qw(
        max_articles max_short_articles max_short_errors max_short_followups
        max_short_groups max_short_size max_total_errors max_total_followups
        max_total_groups max_total_size multipost
    ) },
    'access.domain_limits' => { map { $_ => 1 } qw(
        max_articles max_short_articles max_short_errors max_short_followups
        max_short_groups max_short_size max_total_errors max_total_followups
        max_total_groups max_total_size multipost
    ) },
    'access.authenticated_limits' => { map { $_ => 1 } qw(
        max_articles max_short_articles max_short_errors max_short_followups
        max_short_groups max_short_size max_total_errors max_total_followups
        max_total_groups max_total_size multipost
    ) },
    badwords => { map { $_ => 1 } qw(max_body_score max_subject_score) },
    banlist => { map { $_ => 1 } qw(max_score side_effect_failure) },
    custom => { map { $_ => 1 } qw(module_file on_error) },
    userdb => { map { $_ => 1 } qw(directory) },
    saved_articles => { map { $_ => 1 } qw(directory_layout on_failure) },
    tor => { map { $_ => 1 } qw(
        action cooldown_seconds dns_zone_all dns_zone_exit enabled
        failure_threshold header local_tor_networks negative_cache_seconds
        node_scope on_error positive_cache_seconds positive_codes refused_codes
    ) },
    'tor.header' => { map { $_ => 1 } qw(key_file mode name) },
    html_report => { map { $_ => 1 } qw(
        enabled hours output_file privacy stylesheet_file title
    ) },
    'html_report.privacy' => { map { $_ => 1 } qw(identity_mode key_file) },
    compatibility => { map { $_ => 1 } qw(map_ipv6_loopback_to_ipv4) },
);

# Function: new
# Purpose: Constructs a configuration loader bound to source, state directory, and logger.
# Parameters: $class, %arguments
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub new {
    my ($class, %arguments) = @_;

    return bless {
        current      => undef,
        loaded_at    => 0,
        logger       => $arguments{logger},
        source       => $arguments{source},
        source_mtime => 0,
        state_dir    => $arguments{state_dir},
    }, $class;
}

# Function: current
# Purpose: Returns the currently active validated configuration reference.
# Parameters: $_[0] (the current object or value)
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub current {
    return $_[0]->{current};
}

=head2 load()

Attempts the three-level startup sequence:

  source TOML -> persistent last-known-good JSON -> embedded emergency config

A syntactically valid source with non-critical rule errors still wins: invalid
individual rules are disabled and reported as warnings.  A TOML parse failure,
duplicate key or structurally unusable root is considered critical for that
configuration generation and triggers fallback.

Returns C<($config, $warnings, $origin)>.

=cut

# Function: load
# Purpose: Loads source TOML, validates it, persists a last-known-good generation, or selects a safe fallback.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub load {
    my ($self) = @_;

    my ($config, $warnings, $origin);

    my $source_ok = eval {
        $config = $self->_load_source;
        $warnings = $self->validate_and_sanitize($config);
        $self->_save_generation($config, $warnings);
        $origin = 'source';
        1;
    };

    if (!$source_ok) {
        my $source_error = $@ || 'unknown configuration error';
        $self->{logger}->error(
            'configuration_source_rejected',
            error  => $source_error,
            source => $self->{source},
        ) if $self->{logger};

        my $last_known_good_ok = eval {
            $config = $self->_load_last_known_good;
            $warnings = [];
            $origin = 'last-known-good';
            1;
        };

        if (!$last_known_good_ok) {
            my $snapshot_error = $@ || 'no last-known-good configuration';
            $self->{logger}->error(
                'configuration_lkg_unavailable',
                error => $snapshot_error,
            ) if $self->{logger};

            $config = $self->embedded_minimal;
            $warnings = ['Using embedded emergency configuration'];
            $origin = 'embedded-emergency';
        }
    }

    $self->{current} = $config;
    $self->{loaded_at} = time;
    $self->{source_mtime} = $self->_source_mtime;

    if ($self->{logger}) {
        $self->{logger}->set_verbosity($config->{logging}{verbosity});
        $self->{logger}->set_options($config->{logging});
        $self->{logger}->result(
            'configuration_loaded',
            generation => $config->{_meta}{generation} // 'embedded',
            origin     => $origin,
            warnings   => scalar(@{$warnings}),
        );
    }

    return ($config, $warnings, $origin);
}

=head2 maybe_reload()

Checks source modification times no more often than
C<resilience.reload_interval_seconds>.  A valid generation is returned to the
caller.  A bad reload never replaces the current in-memory object, even if the
loader itself could fall back to an older disk snapshot.

=cut

# Function: maybe_reload
# Purpose: Checks source mtimes at the configured interval and atomically adopts only a valid
#          generation.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub maybe_reload {
    my ($self) = @_;

    my $current = $self->{current};
    return $self->load unless $current;

    my $interval =
        $current->{resilience}{reload_interval_seconds}
        // 30;

    return ($current, [], 'cached')
        if time - $self->{loaded_at} < $interval;

    $self->{loaded_at} = time;
    my $newest_mtime = $self->_source_mtime;

    return ($current, [], 'cached')
        if $newest_mtime <= $self->{source_mtime};

    my ($candidate, $warnings, $origin) = $self->load;
    if ($origin eq 'source') {
        $self->{logger}->result(
            'configuration_reloaded',
            generation => $candidate->{_meta}{generation},
        ) if $self->{logger};
        return ($candidate, $warnings, $origin);
    }

    $self->{current} = $current;
    $self->{logger}->error(
        'configuration_reload_failed_using_previous',
        generation => $current->{_meta}{generation} // 'unknown',
    ) if $self->{logger};

    return ($current, $warnings, 'previous-in-memory');
}

# Function: _load_source
# Purpose: Parses the main TOML and sorted fragments, merges them, and assigns a generation
#          identifier.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _load_source {
    my ($self) = @_;

    my $source = $self->{source}
        or die "No configuration source was specified\n";

    my $config = _parse_toml_file($source);
    die "$source did not contain a TOML table at the root\n"
        unless ref($config) eq 'HASH';

    my $fragment_directory = File::Spec->catdir(dirname($source), 'conf.d');
    if (-d $fragment_directory) {
        for my $fragment (
            sort glob(File::Spec->catfile($fragment_directory, '*.toml'))
        ) {
            my $fragment_config = _parse_toml_file($fragment);
            _deep_merge($config, $fragment_config);
        }
    }

    $config->{_meta} = {
        generation => _generation_id(),
        loaded_at  => now_iso(),
        source     => $source,
    };

    return $config;
}

# Function: _parse_toml_file
# Purpose: Parses one standards-based TOML file with TOML::Tiny and normalises parser-specific
#          scalars.
# Parameters: $path
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _parse_toml_file {
    my ($path) = @_;

    eval { require TOML::Tiny; 1 }
        or die "TOML::Tiny is required to parse $path: $@";

    my $text = slurp($path);
    my $parsed = eval { TOML::Tiny::from_toml($text) };
    die "Unable to parse TOML file $path: $@"
        if $@;
    die "Unable to parse TOML file $path: parser returned no value\n"
        unless defined $parsed;

    # TOML::Tiny intentionally preserves decimal values as Math::BigFloat
    # objects so that a TOML document can round-trip without losing precision.
    # Postfilter does not need arbitrary-precision objects in the runtime
    # configuration, and JSON::PP cannot serialize them without special hooks.
    # Convert parser-specific scalar objects to ordinary Perl numbers here, at
    # the parser boundary, while leaving arrays and tables structurally intact.
    return _normalise_parser_scalars($parsed);
}

# Function: _normalise_parser_scalars
# Purpose: Converts TOML parser numeric/boolean wrapper objects into ordinary Perl scalars
#          recursively.
# Parameters: $value
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _normalise_parser_scalars {
    my ($value) = @_;

    if (ref($value) eq 'HASH') {
        for my $key (keys %{$value}) {
            $value->{$key} = _normalise_parser_scalars($value->{$key});
        }
        return $value;
    }

    if (ref($value) eq 'ARRAY') {
        for my $index (0 .. $#{$value}) {
            $value->[$index] = _normalise_parser_scalars($value->[$index]);
        }
        return $value;
    }

    if (blessed($value)) {
        # TOML::Tiny currently represents fractional numbers with
        # Math::BigFloat.  Using numify keeps 0.9 numeric instead of storing
        # the object itself in the last-known-good JSON snapshot.
        if ($value->isa('Math::BigFloat') || $value->isa('Math::BigInt')) {
            return 0 + $value->numify;
        }

        # JSON booleans can appear when a previously generated snapshot is
        # merged by administrative tooling.  Preserve their boolean meaning.
        if ($value->isa('JSON::PP::Boolean')) {
            return $value ? 1 : 0;
        }

        die 'Unsupported object returned by the TOML parser: ' . blessed($value) . "\n";
    }

    return $value;
}

# Function: _source_mtime
# Purpose: Returns the newest mtime among the main configuration and all TOML fragments.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _source_mtime {
    my ($self) = @_;

    my $maximum = (stat($self->{source} // ''))[9] // 0;
    my $fragment_directory = File::Spec->catdir(
        dirname($self->{source} // '.'),
        'conf.d',
    );

    if (-d $fragment_directory) {
        for my $fragment (glob(File::Spec->catfile($fragment_directory, '*.toml'))) {
            my $mtime = (stat($fragment))[9] // 0;
            $maximum = $mtime if $mtime > $maximum;
        }
    }

    return $maximum;
}

# Function: _save_generation
# Purpose: Persists canonical generation JSON and replaces last-known-good.json atomically.
# Parameters: $self, $config, $warnings
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _save_generation {
    my ($self, $config, $warnings) = @_;

    my $state_directory =
        $self->{state_dir}
        // $config->{paths}{state_dir}
        // '/var/lib/news/postfilter-ng';

    my $generation_directory = File::Spec->catdir(
        $state_directory,
        'config-generations',
    );
    make_path($generation_directory, { mode => 0750 })
        unless -d $generation_directory;

    my $generation = $config->{_meta}{generation};
    my $json = JSON::PP->new->canonical->pretty->encode({
        config   => $config,
        warnings => $warnings,
    });

    atomic_write(
        File::Spec->catfile($generation_directory, "$generation.json"),
        $json,
        0640,
    );
    atomic_write(
        File::Spec->catfile($state_directory, 'last-known-good.json'),
        $json,
        0640,
    );

    return;
}

# Function: _load_last_known_good
# Purpose: Loads the most recent valid JSON snapshot for a new nnrpd process after source failure.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _load_last_known_good {
    my ($self) = @_;

    my $state_directory =
        $self->{state_dir}
        // '/var/lib/news/postfilter-ng';
    my $path = File::Spec->catfile(
        $state_directory,
        'last-known-good.json',
    );

    my $object = JSON::PP->new->decode(slurp($path));
    die "Invalid last-known-good snapshot in $path\n"
        unless ref($object->{config}) eq 'HASH';

    return $object->{config};
}

=head2 validate_and_sanitize($config)

Applies defaults and returns an array reference of non-critical warnings.  Invalid
rule regexes disable only the affected entry.  Invalid policy enums are replaced
with safe documented defaults.  The method intentionally does not require key
files to exist: the installer creates them, while startup code can keep running
with the previous generation if an operator temporarily moves a key.

=cut

# Function: validate_and_sanitize
# Purpose: Applies defaults, validates enums and regexes, and disables only malformed optional
#          entries.
# Parameters: $self, $config
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub validate_and_sanitize {
    my ($self, $config) = @_;

    my @warnings;
    _apply_defaults($config);

    _remove_unknown_configuration_keys($config, \@warnings);

    _enum(
        $config->{article_types},
        'mode',
        [qw(text-only mixed)],
        \@warnings,
        'text-only',
    );
    _enum(
        $config->{article_types},
        'pattern_syntax',
        [qw(glob)],
        \@warnings,
        'glob',
    );
    _enum(
        $config->{article_types},
        'mixed_crosspost_policy',
        [qw(reject)],
        \@warnings,
        'reject',
    );
    for my $article_type (qw(text binary)) {
        _enum(
            $config->{article_types}{$article_type}{save_rejected},
            'mode',
            [qw(none all selected)],
            \@warnings,
            'none',
        );
    }

    for my $article_type (qw(text binary)) {
        my $mime = $config->{article_types}{$article_type}{mime};
        _enum(
            $mime,
            'on_malformed',
            [qw(accept reject)],
            \@warnings,
            $article_type eq 'text' ? 'reject' : 'accept',
        );

        for my $list_name (qw(
            allowed_armored_block_types allowed_media_types
            allowed_multipart_types forbidden_media_types
        )) {
            if (ref($mime->{$list_name}) ne 'ARRAY') {
                push @warnings,
                    "article_types.$article_type.mime.$list_name is not an array; cleared";
                $mime->{$list_name} = [];
            }
        }
    }

    _enum($config->{policy}, 'mode', [qw(enforce audit)], \@warnings, 'enforce');
    _enum(
        $config->{policy},
        'server_status',
        [qw(active closed disabled)],
        \@warnings,
        'active',
    );
    _enum(
        $config->{policy},
        'action_on_accept',
        [qw(accept discard save reject)],
        \@warnings,
        'accept',
    );
    _enum(
        $config->{policy},
        'action_on_reject',
        [qw(accept discard save reject)],
        \@warnings,
        'reject',
    );

    _integer($config->{logging}, 'verbosity', 1, 9, \@warnings, 3);

    _enum(
        $config->{database},
        'on_failure',
        [qw(accept reject disable)],
        \@warnings,
        'accept',
    );
    _enum(
        $config->{database}{privacy},
        'identity_mode',
        [qw(plain hmac encrypted)],
        \@warnings,
        'plain',
    );

    _enum(
        $config->{tor},
        'action',
        [qw(allow mark reject)],
        \@warnings,
        'mark',
    );
    _enum(
        $config->{tor},
        'node_scope',
        [qw(all exit)],
        \@warnings,
        'all',
    );
    _normalise_encryption_mode(
        $config->{tor}{header},
        'mode',
        \@warnings,
        'none',
    );
    _normalise_encryption_mode(
        $config->{html_report}{privacy},
        'identity_mode',
        \@warnings,
        'hmac',
        [qw(plain redacted hmac encrypted)],
    );

    for my $header_component (qw(sender posting_host posting_account path)) {
        _enum(
            $config->{headers}{$header_component},
            'mode',
            [qw(preserve delete replace pseudonymize)],
            \@warnings,
            $header_component eq 'path' ? 'replace' : 'preserve',
        );
    }

    _validate_numeric_sections($config, \@warnings);
    _validate_article_type_configuration($config, \@warnings);
    _validate_rule_lists($config, \@warnings);
    _validate_provider_failure_policies($config, \@warnings);
    _validate_retention_policy($config, \@warnings);
    _validate_regex_arrays($config, \@warnings);

    my $public_pattern = $config->{access}{public_user_pattern} // '';
    if (length($public_pattern) && !_valid_regex($public_pattern)) {
        push @warnings,
            'Invalid access.public_user_pattern; synthetic public-user regex disabled';
        $config->{access}{public_user_pattern} = '';
    }

    for my $warning (@warnings) {
        $self->{logger}->warning(
            'configuration_warning',
            warning => $warning,
        ) if $self->{logger};
    }

    return \@warnings;
}

# Function: embedded_minimal
# Purpose: Builds the small fail-open configuration used only when source and snapshots are
#          unavailable.
# Parameters: No positional parameters, or arguments are read directly by the command wrapper.
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub embedded_minimal {
    return {
        _meta => {
            generation => 'embedded-emergency',
            loaded_at  => now_iso(),
        },
        access => {
            public_user_ids     => [],
            public_user_pattern => '',
        },
        article_types => {
            mode => 'text-only',
            pattern_syntax => 'glob',
            mixed_crosspost_policy => 'reject',
            binary_group_patterns => [],
            text => {
                checks => { skip => [] },
                content => {
                    allow_html => 1,
                    allow_uuencode => 1,
                    allow_yenc => 1,
                },
                mime => { enabled => 0 },
                limits => {},
                save_rejected => {
                    mode => 'none',
                    compatibility_codes => [],
                    reason_codes => [],
                    rule_ids => [],
                    subdirectory => 'text',
                },
            },
            binary => {
                checks => { skip => [] },
                content => {
                    allow_html => 1,
                    allow_uuencode => 1,
                    allow_yenc => 1,
                },
                mime => { enabled => 0 },
                limits => {},
                save_rejected => {
                    mode => 'none',
                    compatibility_codes => [],
                    reason_codes => [],
                    rule_ids => [],
                    subdirectory => 'binary',
                },
            },
        },
        badword        => [],
        ban_rule       => [],
        database       => {
            enabled    => 0,
            on_failure => 'accept',
            privacy    => { identity_mode => 'plain' },
        },
        distributions => [],
        headers       => {
            allow_control_cancel    => 1,
            allow_html              => 1,
            allow_mail_headers      => 1,
            allow_supersedes        => 1,
            allow_uuencode          => 1,
            allow_yenc              => 1,
            check_distribution      => 0,
            check_groups_existence  => 0,
            include_new_headers     => 0,
            path                    => {
                mode        => 'replace',
                replacement => 'not-for-mail',
            },
            posting_account => { mode => 'preserve' },
            posting_host    => { mode => 'preserve' },
            sender          => { mode => 'preserve' },
        },
        html_report => {
            enabled => 0,
            privacy => { identity_mode => 'hmac' },
        },
        limits => {
            max_blank_ratio          => 1,
            max_body_size            => 1_048_576,
            max_crosspost            => 100,
            max_empty_ratio          => 1,
            max_followup             => 100,
            max_header_length        => 16_384,
            max_header_size          => 65_536,
            max_hierarchies_followup => 20,
            max_hierarchies_post     => 20,
            max_line_length          => 0,
            max_quoted_ratio         => 1,
            max_total_size           => 1_114_112,
        },
        logging => {
            log_accepted => 1,
            log_rejected => 1,
            verbosity    => 1,
        },
        modules => {
            access      => 0,
            attachments => 0,
            badwords    => 0,
            banlist  => 0,
            content  => 1,
            custom   => 0,
            dates    => 0,
            groups   => 0,
            headers  => 1,
            rbl      => 0,
            style    => 1,
            surbl    => 0,
            tor      => 0,
            uribl    => 0,
            userdb   => 0,
        },
        policy => {
            action_on_accept => 'accept',
            action_on_reject => 'reject',
            mode             => 'enforce',
            server_status    => 'active',
            show_error_code  => 1,
        },
        resilience => {
            emergency_action                 => 'accept',
            reload_interval_seconds          => 30,
        },
        retention => {
            events                  => 'forever',
            rule_hits               => 'forever',
            saved_articles          => 'forever',
            provider_health_seconds => 604_800,
        },
        timeouts => {
            max_processing_ms => 1_500,
        },
        tor => {
            action     => 'allow',
            enabled    => 0,
            header     => { mode => 'none' },
            node_scope => 'all',
        },
        trusted_profile => [],
    };
}

# Function: _apply_defaults
# Purpose: Populates omitted sections and keys without overwriting explicit operator values.
# Parameters: $config
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _apply_defaults {
    my ($config) = @_;

    for my $section (qw(
        access article_types badwords banlist compatibility custom database headers
        html_report keys limits logging modules paths policy resilience
        retention saved_articles timeouts tor userdb
    )) {
        $config->{$section} = {}
            unless ref($config->{$section}) eq 'HASH';
    }

    for my $nested (
        [$config->{database},    'privacy'],
        [$config->{headers},     'path'],
        [$config->{headers},     'posting_account'],
        [$config->{headers},     'posting_host'],
        [$config->{headers},     'sender'],
        [$config->{html_report}, 'privacy'],
        [$config->{tor},         'header'],
    ) {
        $nested->[0]{ $nested->[1] } = {}
            unless ref($nested->[0]{ $nested->[1] }) eq 'HASH';
    }

    for my $article_type (qw(text binary)) {
        $config->{article_types}{$article_type} = {}
            unless ref($config->{article_types}{$article_type}) eq 'HASH';
        for my $section (qw(checks content limits mime save_rejected)) {
            $config->{article_types}{$article_type}{$section} = {}
                unless ref($config->{article_types}{$article_type}{$section}) eq 'HASH';
        }
    }

    my %defaults = (
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
        },
        policy => {
            action_on_accept => 'accept',
            action_on_reject => 'reject',
            mode             => 'enforce',
            server_status    => 'active',
            show_error_code  => 1,
        },
        logging => {
            include_rule_ids => 1,
            include_timing   => 1,
            log_accepted     => 1,
            log_rejected     => 1,
            verbosity        => 3,
        },
        resilience => {
            emergency_action                 => 'accept',
            reload_interval_seconds          => 30,
        },
        database => {
            busy_timeout_ms => 5_000,
            enabled         => 1,
            on_failure      => 'accept',
            path            => '/var/lib/news/postfilter-ng/postfilter.sqlite3',
            synchronous     => 'FULL',
        },
        modules => {
            access      => 1,
            attachments => 1,
            badwords    => 1,
            banlist  => 1,
            content  => 1,
            custom   => 0,
            dates    => 1,
            groups   => 1,
            headers  => 1,
            rbl      => 0,
            style    => 1,
            surbl    => 0,
            tor      => 1,
            uribl    => 0,
            userdb   => 0,
        },
        limits => {
            absolute_multipost_limit => 100,
            default_multipost_limit  => 2,
            dns_cache_max_entries    => 2_000,
            max_blank_ratio          => 0.9,
            max_body_scan_bytes      => 1_048_576,
            max_body_size            => 52_000,
            max_crosspost            => 5,
            max_empty_ratio          => 0.9,
            max_followup             => 3,
            max_fup_no_crosspost     => 3,
            max_groups_difference    => 5,
            max_header_length        => 4_096,
            max_header_size          => 8_192,
            max_hierarchies_followup => 1,
            max_hierarchies_post     => 2,
            max_line_length          => 0,
            max_quoted_ratio         => 0.999,
            max_rule_evaluations     => 2_000,
            max_total_size           => 64_000,
            max_unique_domains       => 10,
            max_urls_to_check        => 20,
        },
        timeouts => {
            dns_query_seconds  => 2,
            dns_total_seconds  => 10,
            future_grace_seconds => 3_600,
            max_processing_ms  => 1_500,
            too_old_seconds    => 259_200,
        },
        retention => {
            # Event and rule history replaces legal.log and therefore defaults
            # to permanent retention.  Deletion is available only through an
            # explicit postfilterctl purge command.
            events            => 'forever',
            provider_health_seconds => 604_800,
            rule_hits         => 'forever',
            saved_articles    => 'forever',
        },
        headers => {
            allow_control_cancel   => 0,
            allow_html             => 0,
            allow_mail_headers     => 0,
            allow_supersedes       => 0,
            allow_uuencode         => 0,
            allow_yenc             => 0,
            check_distribution     => 1,
            check_groups_existence => 1,
            delete_custom_headers  => 0,
            delete_mail_headers    => 1,
            delete_posting_date    => 0,
            delete_user_agent      => 0,
            delete_x_no_archive    => 1,
            delete_x_trace         => 1,
            force_default_organization => 0,
            include_new_headers    => 1,
            organization           => '',
        },
        access => {
            article_digest_mode => 'simple',
            enable_domain_check => 1,
            period_seconds      => 86_400,
            public_user_ids     => [],
            public_user_pattern => '',
            separate_counters_by_article_type => 1,
            server_type         => 'both',
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
            action          => 'mark',
            cooldown_seconds => 300,
            dns_zone_all    => 'tor.dan.me.uk',
            dns_zone_exit   => 'torexit.dan.me.uk',
            enabled         => 1,
            failure_threshold => 5,
            local_tor_networks => [],
            node_scope      => 'all',
            positive_codes  => ['127.0.0.100'],
        },
        html_report => {
            enabled         => 0,
            hours           => 168,
            stylesheet_file => '',
            title           => 'Postfilter-NG statistics',
        },
        saved_articles => {
            directory_layout => 'year/month/day',
        },
    );

    for my $section (keys %defaults) {
        for my $key (keys %{ $defaults{$section} }) {
            $config->{$section}{$key} = $defaults{$section}{$key}
                unless exists $config->{$section}{$key};
        }
    }

    my %nested_defaults = (
        text_content => {
            hash => $config->{article_types}{text}{content},
            defaults => {
                allow_html => 0,
                allow_uuencode => 0,
                allow_yenc => 0,
            },
        },
        binary_content => {
            hash => $config->{article_types}{binary}{content},
            defaults => {
                allow_html => 0,
                allow_uuencode => 1,
                allow_yenc => 1,
            },
        },
        text_mime => {
            hash => $config->{article_types}{text}{mime},
            defaults => {
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
        },
        binary_mime => {
            hash => $config->{article_types}{binary}{mime},
            defaults => {
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
        },
        text_checks => {
            hash => $config->{article_types}{text}{checks},
            defaults => { skip => [] },
        },
        binary_checks => {
            hash => $config->{article_types}{binary}{checks},
            defaults => {
                skip => [
                    'style.line_statistics',
                    'style.html',
                    'badwords',
                    'uribl',
                ],
            },
        },
        text_save => {
            hash => $config->{article_types}{text}{save_rejected},
            defaults => {
                mode => 'selected',
                compatibility_codes => [],
                reason_codes => [
                    'PF-BODY-052',
                    'PF-BODY-062',
                    'PF-MIME-109',
                    'PF-MIME-110',
                    'PF-MIME-111',
                    'PF-BODY-112',
                    'PF-MIME-113',
                    'PF-MIME-114',
                ],
                rule_ids => [],
                subdirectory => 'text',
            },
        },
        binary_save => {
            hash => $config->{article_types}{binary}{save_rejected},
            defaults => {
                mode => 'none',
                compatibility_codes => [],
                reason_codes => [],
                rule_ids => [],
                subdirectory => 'binary',
            },
        },
        database_privacy => {
            hash => $config->{database}{privacy},
            defaults => { identity_mode => 'plain' },
        },
        sender => {
            hash => $config->{headers}{sender},
            defaults => {
                mode              => 'preserve',
                pseudonym_domain  => 'postfilter.invalid',
                replacement       => '',
            },
        },
        posting_host => {
            hash => $config->{headers}{posting_host},
            defaults => {
                mode        => 'preserve',
                replacement => '',
            },
        },
        posting_account => {
            hash => $config->{headers}{posting_account},
            defaults => {
                mode        => 'preserve',
                replacement => '',
            },
        },
        path => {
            hash => $config->{headers}{path},
            defaults => {
                mode        => 'replace',
                replacement => 'not-for-mail',
            },
        },
        tor_header => {
            hash => $config->{tor}{header},
            defaults => {
                mode => 'none',
                name => 'X-Postfilter-TOR',
            },
        },
        report_privacy => {
            hash => $config->{html_report}{privacy},
            defaults => { identity_mode => 'hmac' },
        },
    );

    for my $definition (values %nested_defaults) {
        for my $key (keys %{ $definition->{defaults} }) {
            $definition->{hash}{$key} = $definition->{defaults}{$key}
                unless exists $definition->{hash}{$key};
        }
    }

    my %text_limit_defaults = (
        max_body_size => 32_768,
        max_header_size => 8_192,
        max_total_size => 40_960,
        max_body_scan_bytes => 32_768,
    );
    my %binary_limit_defaults = (
        max_body_size => 10_485_760,
        max_header_size => 65_536,
        max_total_size => 10_551_296,
        max_body_scan_bytes => 1_048_576,
    );
    for my $key (keys %text_limit_defaults) {
        $config->{article_types}{text}{limits}{$key} = $text_limit_defaults{$key}
            unless exists $config->{article_types}{text}{limits}{$key};
    }
    for my $key (keys %binary_limit_defaults) {
        $config->{article_types}{binary}{limits}{$key} = $binary_limit_defaults{$key}
            unless exists $config->{article_types}{binary}{limits}{$key};
    }

    for my $list (qw(
        access_profile badword ban_rule content_type_rule distributions dnsbl
        forbidden_crosspost forbidden_groups forbidden_header_rule
        html_allowed_groups html_patterns mail_headers moderated_exceptions
        saved_headers surbl trusted_profile uribl
    )) {
        $config->{$list} = [] unless ref($config->{$list}) eq 'ARRAY';
    }

    return;
}

# Function: _remove_unknown_configuration_keys
# Purpose: Warns about and removes misspelled top-level and fixed-table options.
# Parameters: $config, $warnings
# Operational notes: Rule-specific/dynamic tables are handled elsewhere; removal prevents an
#                    ignored typo from appearing to be an active security policy.
sub _remove_unknown_configuration_keys {
    my ($config, $warnings) = @_;

    for my $top_level (sort keys %{$config}) {
        next if $KNOWN_TOP_LEVEL{$top_level};
        push @{$warnings},
            "Unknown top-level configuration key '$top_level'; ignored";
        delete $config->{$top_level};
    }

    for my $path (sort keys %KNOWN_SECTION_KEY) {
        my @component = split /\./, $path;
        my $table = $config;
        for my $name (@component) {
            last unless ref($table) eq 'HASH';
            $table = $table->{$name};
        }
        next unless ref($table) eq 'HASH';

        for my $key (sort keys %{$table}) {
            next if $KNOWN_SECTION_KEY{$path}{$key};
            push @{$warnings},
                "Unknown configuration key '$path.$key'; ignored";
            delete $table->{$key};
        }
    }

    return;
}

# Function: _validate_numeric_sections
# Purpose: Validates only quantity-valued limits/timeouts and converts them to plain numeric
#          scalars.
# Parameters: $config, $warnings
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _validate_numeric_sections {
    my ($config, $warnings) = @_;

    # Only keys which represent quantities are checked here.  Policy strings
    # such as timeouts.on_processing_timeout intentionally live in the same
    # table and must not be mistaken for numeric values merely because of the
    # table name.
    my %numeric_key = map { $_ => 1 } qw(
        absolute_multipost_limit
        cooldown_seconds
        dns_query_seconds
        dns_total_seconds
        failure_threshold
        future_grace_seconds
        allowed_media_max_decoded_bytes
        armored_block_max_bytes
        base64_max_line_length
        base64_min_contiguous_lines
        base64_min_decoded_bytes
        base64_min_line_length
        base64_single_line_min_decoded_bytes
        max_blank_ratio
        max_body_scan_bytes
        max_body_size
        max_crosspost
        max_empty_ratio
        max_followup
        max_fup_no_crosspost
        max_groups_difference
        max_header_length
        max_header_size
        max_hierarchies_followup
        max_hierarchies_post
        max_line_length
        max_mime_depth
        max_mime_parts
        max_processing_ms
        max_quoted_ratio
        max_rule_evaluations
        max_total_size
        max_unique_domains
        max_urls_to_check
        negative_cache_seconds
        positive_cache_seconds
        too_old_seconds
    );

    my @numeric_section = (
        ['limits', $config->{limits}],
        ['timeouts', $config->{timeouts}],
        ['article_types.text.limits', $config->{article_types}{text}{limits}],
        ['article_types.binary.limits', $config->{article_types}{binary}{limits}],
        ['article_types.text.mime', $config->{article_types}{text}{mime}],
        ['article_types.binary.mime', $config->{article_types}{binary}{mime}],
    );

    for my $definition (@numeric_section) {
        my ($section, $table) = @{$definition};
        next unless ref($table) eq 'HASH';

        for my $key (keys %{$table}) {
            next unless $numeric_key{$key};

            my $value = $table->{$key};
            next unless defined $value;

            if (!looks_like_number($value)) {
                push @{$warnings},
                    "Invalid numeric value $section.$key; setting removed";
                delete $table->{$key};
                next;
            }

            # Force a plain numeric scalar so callers do not receive a parser
            # wrapper or a string that only happens to look numeric.
            $table->{$key} = 0 + $value;
        }
    }

    return;
}

# Function: _validate_article_type_configuration
# Purpose: Validates binary-group globs, per-type check lists, save selectors, and rule scopes.
# Parameters: $config, $warnings
# Operational notes: Invalid optional entries are removed while the remaining policy stays active.
sub _validate_article_type_configuration {
    my ($config, $warnings) = @_;

    my $patterns = $config->{article_types}{binary_group_patterns};
    if (ref($patterns) ne 'ARRAY') {
        push @{$warnings},
            'article_types.binary_group_patterns is not an array; using no binary groups';
        $config->{article_types}{binary_group_patterns} = [];
    }
    else {
        my @valid = grep { defined $_ && !ref($_) && length($_) } @{$patterns};
        if (@valid != @{$patterns}) {
            push @{$warnings},
                'Ignored empty or non-scalar binary group glob patterns';
        }
        $config->{article_types}{binary_group_patterns} = \@valid;
    }

    for my $type (qw(text binary)) {
        my $skip = $config->{article_types}{$type}{checks}{skip};
        if (ref($skip) ne 'ARRAY') {
            push @{$warnings},
                "article_types.$type.checks.skip is not an array; using no skips";
            $config->{article_types}{$type}{checks}{skip} = [];
        }

        my $save = $config->{article_types}{$type}{save_rejected};
        for my $key (qw(reason_codes compatibility_codes rule_ids)) {
            if (ref($save->{$key}) ne 'ARRAY') {
                push @{$warnings},
                    "article_types.$type.save_rejected.$key is not an array; cleared";
                $save->{$key} = [];
            }
        }

        my $subdirectory = $save->{subdirectory};
        if (
            !defined($subdirectory)
            || ref($subdirectory)
            || $subdirectory !~ /\A[A-Za-z0-9_.-]+\z/
            || $subdirectory eq '.'
            || $subdirectory eq '..'
        ) {
            push @{$warnings},
                "article_types.$type.save_rejected.subdirectory is unsafe; using $type";
            $save->{subdirectory} = $type;
        }
    }

    return;
}

# Function: _validate_rule_lists
# Purpose: Checks rule-list shape, IDs, enabled state, duplicates, and rule-specific regex fields.
# Parameters: $config, $warnings
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _validate_rule_lists {
    my ($config, $warnings) = @_;

    for my $list_name (qw(
        access_profile badword ban_rule content_type_rule dnsbl
        forbidden_crosspost forbidden_header_rule surbl trusted_profile uribl
    )) {
        next unless exists $config->{$list_name};

        if (ref($config->{$list_name}) ne 'ARRAY') {
            push @{$warnings}, "$list_name is not an array; list disabled";
            $config->{$list_name} = [];
            next;
        }

        my %seen_id;
        my $position = 0;
        for my $entry (@{ $config->{$list_name} }) {
            $position++;
            next unless ref($entry) eq 'HASH';

            $entry->{id} //= "$list_name-$position";
            my $id = $entry->{id};

            if ($seen_id{$id}++) {
                $entry->{enabled} = 0;
                $entry->{_invalid} = 'duplicate id';
                push @{$warnings},
                    "Disabled duplicate $list_name entry '$id'";
                next;
            }

            $entry->{enabled} = 1 unless exists $entry->{enabled};
            if (exists $entry->{article_types}) {
                if (ref($entry->{article_types}) ne 'ARRAY') {
                    _disable_entry(
                        $entry,
                        $warnings,
                        $list_name,
                        'article_types must be an array containing text and/or binary',
                    );
                    next;
                }
                my @valid = grep { $_ eq 'text' || $_ eq 'binary' }
                    @{ $entry->{article_types} };
                if (@valid != @{ $entry->{article_types} }) {
                    _disable_entry(
                        $entry,
                        $warnings,
                        $list_name,
                        'article_types contains an unsupported value',
                    );
                    next;
                }
            }
            _validate_entry_regexes($list_name, $entry, $warnings);
        }
    }

    return;
}

# Function: _validate_entry_regexes
# Purpose: Compiles every regex used by one rule and disables only that rule on failure.
# Parameters: $list_name, $entry, $warnings
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _validate_entry_regexes {
    my ($list_name, $entry, $warnings) = @_;

    my @fields;
    if ($list_name eq 'badword') {
        @fields = ($entry->{match_type} // 'regex') eq 'regex'
            ? ('pattern')
            : ();
    }
    elsif ($list_name eq 'ban_rule') {
        @fields = grep { defined $entry->{$_} } qw(
            exclude_group_pattern
            header_name_pattern
            header_value_pattern
            include_group_pattern
        );
        push @fields, 'pattern'
            if defined $entry->{pattern}
            && ($entry->{match_type} // 'regex') eq 'regex';
    }
    elsif ($list_name eq 'trusted_profile') {
        @fields = grep { defined $entry->{$_} } qw(from_pattern group_pattern);

        if (ref($entry->{header_match}) eq 'ARRAY') {
            my $position = 0;
            for my $match (@{ $entry->{header_match} }) {
                $position++;
                next
                    unless ref($match) eq 'HASH'
                    && defined $match->{pattern};

                if (!_valid_regex($match->{pattern})) {
                    _disable_entry(
                        $entry,
                        $warnings,
                        $list_name,
                        "invalid header_match regex at position $position",
                    );
                    return;
                }
            }
        }
    }
    elsif ($list_name eq 'access_profile') {
        @fields = ('pattern')
            if defined $entry->{pattern}
            && ($entry->{match_type} // 'regex') eq 'regex';
    }
    elsif ($list_name eq 'content_type_rule') {
        @fields = qw(group_pattern allowed_pattern);
    }
    elsif ($list_name eq 'forbidden_header_rule') {
        @fields = qw(name_pattern exception_pattern);
    }
    elsif ($list_name eq 'forbidden_crosspost') {
        @fields = qw(left right);
    }

    for my $field (@fields) {
        next unless defined $entry->{$field};
        next if _valid_regex($entry->{$field});

        _disable_entry(
            $entry,
            $warnings,
            $list_name,
            "invalid regex in $field",
        );
        return;
    }

    return;
}

# Function: _disable_entry
# Purpose: Marks one malformed optional entry disabled and records a precise configuration
#          warning.
# Parameters: $entry, $warnings, $list_name, $reason
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _disable_entry {
    my ($entry, $warnings, $list_name, $reason) = @_;

    $entry->{enabled} = 0;
    $entry->{_invalid} = $reason;
    push @{$warnings},
        "Disabled $list_name '$entry->{id}': $reason";

    return;
}

# Function: _validate_provider_failure_policies
# Purpose: Validates provider-specific failure decisions so timeout/refusal
#          handling can never be driven by an arbitrary misspelt string.
# Parameters: $config, $warnings
# Operational notes: Invalid optional values are reset to fail-open accept and
#                    reported during configuration loading.
sub _validate_provider_failure_policies {
    my ($config, $warnings) = @_;

    for my $list_name (qw(dnsbl surbl uribl)) {
        for my $provider (@{ $config->{$list_name} // [] }) {
            next unless ref($provider) eq 'HASH';

            for my $key (qw(on_error on_timeout)) {
                next unless exists $provider->{$key};
                next if $provider->{$key} eq 'accept'
                    || $provider->{$key} eq 'reject';

                push @{$warnings},
                    "Invalid $list_name '$provider->{id}' $key; using accept";
                $provider->{$key} = 'accept';
            }
        }
    }

    for my $key (qw(on_error)) {
        next unless exists $config->{tor}{$key};
        next if $config->{tor}{$key} eq 'accept'
            || $config->{tor}{$key} eq 'reject';
        push @{$warnings}, "Invalid tor.$key; using accept";
        $config->{tor}{$key} = 'accept';
    }

    return;
}

# Function: _validate_retention_policy
# Purpose: Enforces the intentional no-automatic-deletion policy for legal
#          article history, rule hits, and saved articles.
# Parameters: $config, $warnings
# Operational notes: Any finite value is reset to forever.  Deletion remains
#                    possible only through the explicit audited purge command.
sub _validate_retention_policy {
    my ($config, $warnings) = @_;

    for my $key (qw(events rule_hits saved_articles)) {
        my $value = $config->{retention}{$key} // 'forever';
        next if $value eq 'forever';

        push @{$warnings},
            "retention.$key must be 'forever'; automatic deletion is disabled";
        $config->{retention}{$key} = 'forever';
    }

    return;
}

# Function: _validate_regex_arrays
# Purpose: Removes invalid standalone regexes while preserving every valid sibling expression.
# Parameters: $config, $warnings
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _validate_regex_arrays {
    my ($config, $warnings) = @_;

    for my $name (qw(
        forbidden_groups html_allowed_groups html_patterns moderated_exceptions
    )) {
        next unless exists $config->{$name};

        if (ref($config->{$name}) ne 'ARRAY') {
            push @{$warnings}, "$name is not an array; list disabled";
            $config->{$name} = [];
            next;
        }

        my @valid;
        for my $pattern (@{ $config->{$name} }) {
            if (defined $pattern && _valid_regex($pattern)) {
                push @valid, $pattern;
            }
            else {
                push @{$warnings},
                    "Ignored invalid regular expression in $name";
            }
        }

        $config->{$name} = \@valid;
    }

    return;
}

# Function: _normalise_encryption_mode
# Purpose: Maps deprecated crypt/sha256 aliases to encrypted and validates allowed privacy modes.
# Parameters: $hash, $key, $warnings, $default, $allowed
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _normalise_encryption_mode {
    my ($hash, $key, $warnings, $default, $allowed) = @_;
    $allowed //= [qw(none plain encrypted)];

    my $value = $hash->{$key};
    if (defined $value && ($value eq 'sha256' || $value eq 'crypt')) {
        push @{$warnings},
            "$key value '$value' is deprecated; using 'encrypted'";
        $hash->{$key} = 'encrypted';
    }

    _enum($hash, $key, $allowed, $warnings, $default);
    return;
}

# Function: _valid_regex
# Purpose: Compiles a candidate expression inside eval and returns whether it is safe to activate.
# Parameters: $pattern
# Operational notes: No persistent external state is changed.
sub _valid_regex {
    my ($pattern) = @_;
    return eval { qr/$pattern/; 1 } ? 1 : 0;
}

# Function: _enum
# Purpose: Validates one scalar against an explicit allow-list and applies a documented fallback.
# Parameters: $hash, $key, $allowed, $warnings, $default
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _enum {
    my ($hash, $key, $allowed, $warnings, $default) = @_;
    my %allowed_value = map { $_ => 1 } @{$allowed};

    if (!defined $hash->{$key} || !$allowed_value{ $hash->{$key} }) {
        push @{$warnings}, "Invalid $key; using $default";
        $hash->{$key} = $default;
    }

    return;
}

# Function: _integer
# Purpose: Validates an integer range used by a bounded operational setting.
# Parameters: $hash, $key, $minimum, $maximum, $warnings, $default
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _integer {
    my ($hash, $key, $minimum, $maximum, $warnings, $default) = @_;

    if (
        !defined $hash->{$key}
        || $hash->{$key} !~ /^\d+$/
        || $hash->{$key} < $minimum
        || $hash->{$key} > $maximum
    ) {
        push @{$warnings}, "Invalid $key; using $default";
        $hash->{$key} = $default;
    }

    return;
}

# Function: _deep_merge
# Purpose: Recursively merges a configuration fragment and appends designated arrays of tables.
# Parameters: $destination, $source
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _deep_merge {
    my ($destination, $source) = @_;

    for my $key (keys %{$source}) {
        if (
            ref($source->{$key}) eq 'HASH'
            && ref($destination->{$key}) eq 'HASH'
        ) {
            _deep_merge($destination->{$key}, $source->{$key});
            next;
        }

        if (
            ref($source->{$key}) eq 'ARRAY'
            && ref($destination->{$key}) eq 'ARRAY'
            && $APPEND_ARRAY{$key}
        ) {
            push @{ $destination->{$key} }, @{ $source->{$key} };
            next;
        }

        $destination->{$key} = $source->{$key};
    }

    return;
}

# Function: _generation_id
# Purpose: Creates a human-sortable UTC generation identifier with a collision-resistant suffix.
# Parameters: No positional parameters, or arguments are read directly by the command wrapper.
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _generation_id {
    my @time = gmtime;
    return sprintf(
        '%04d%02d%02dT%02d%02d%02dZ-%06x',
        $time[5] + 1900,
        $time[4] + 1,
        $time[3],
        $time[2],
        $time[1],
        $time[0],
        int(rand(0xffffff)),
    );
}

1;
