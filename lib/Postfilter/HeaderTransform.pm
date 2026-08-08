package Postfilter::HeaderTransform;

use strict;
use warnings;

=head1 NAME

Postfilter::HeaderTransform - Explicit, policy-driven article header changes.

=head1 IMPORTANT DEFAULTS

Postfilter-NG preserves C<Sender> by default.  Sender is a meaningful
message header and may identify the actual sending agent when it differs from
C<From>; deleting or pseudonymising it without an explicit operator decision can
change reply behaviour and remove information intentionally published by the
user.  The same opt-in principle is applied to posting account and posting host.

No transformation uses a compiled-in emergency salt.  If a pseudonymisation key
is unavailable, the original header is preserved and C<news.err> receives an
explicit diagnostic.  Reversible TOR-header encryption similarly falls back to
C<yes>, never to plaintext and never to a predictable key.

=cut

use Postfilter::Codes;
use Postfilter::Result;
use Postfilter::Util qw(hmac_id);

# Function: apply
# Purpose: Applies all explicitly enabled header transformations in a deterministic order.
# Parameters: $class, $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub apply {
    my ($class, $context) = @_;

    my $config = $context->{config};
    my $header_config = $config->{headers};
    my $headers = $context->{headers};

    if ($header_config->{force_default_organization}) {
        $headers->{Organization} = $header_config->{organization} // '';
        $context->{logger}->headers(
            'header_replaced',
            header => 'Organization',
        );
    }

    _transform_sender($context);
    _transform_injection_information($context);
    _transform_path($context);

    if ($header_config->{delete_user_agent}) {
        _delete_named_headers($context, qw(User-Agent X-Mailer X-Newsreader));
    }

    if ($header_config->{delete_mail_headers}) {
        _delete_named_headers(
            $context,
            qw(Received In-Reply-To Delivered-To BCC Bcc CC Cc To),
        );
    }

    _delete_named_headers($context, 'X-No-Archive')
        if $header_config->{delete_x_no_archive};
    _delete_named_headers($context, 'X-Trace')
        if $header_config->{delete_x_trace};

    if ($header_config->{delete_custom_headers}) {
        _keep_only_configured_headers($context);
    }

    my $distribution_result = _transform_distribution($context);
    return $distribution_result
        if !$distribution_result->is_pass
        && ($config->{policy}{mode} // 'enforce') ne 'audit';

    # Audit-mode technical rejections are accepted by nnrpd.  Complete the
    # non-destructive header finalisation so an audit-accepted article receives
    # the same configured operational headers as an ordinarily accepted one.
    _add_tor_header($context) if $context->{tor};

    if ($header_config->{include_new_headers}) {
        for my $name (keys %{ $config->{new_headers} // {} }) {
            $headers->{$name} = $config->{new_headers}{$name};
            $context->{logger}->headers(
                'header_added',
                header => $name,
            );
        }
    }

    _repair_mime_headers($context);

    return $distribution_result unless $distribution_result->is_pass;

    return Postfilter::Result->pass(
        code    => 'PF-HEADER-000',
        legacy  => 0,
        message => 'Header transformations completed',
    );
}

=head2 _transform_sender($context)

Supported modes:

  preserve      leave Sender exactly as supplied
  delete        remove Sender
  replace       use headers.sender.replacement
  pseudonymize  create pf-<HMAC>@<configured-domain>

The pseudonymised form is a syntactically valid mailbox using the configured
pseudonym domain.

=cut

# Function: _transform_sender
# Purpose: Preserves, deletes, replaces, or pseudonymises Sender only when explicitly configured.
# Parameters: $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _transform_sender {
    my ($context) = @_;

    my $settings = $context->{config}{headers}{sender};
    my $mode = $settings->{mode} // 'preserve';
    my $headers = $context->{headers};

    return if $mode eq 'preserve';

    if ($mode eq 'delete') {
        if (exists $headers->{Sender}) {
            _remove_header($headers, 'Sender');
            $context->{logger}->headers(
                'header_deleted',
                header => 'Sender',
            );
        }
        return;
    }

    if ($mode eq 'replace') {
        $headers->{Sender} = $settings->{replacement} // '';
        $context->{logger}->headers(
            'header_replaced',
            header => 'Sender',
        );
        return;
    }

    return unless $mode eq 'pseudonymize';

    my $key = _load_pseudonym_key($context, 'Sender');
    return unless $key;

    my $source_value = length($headers->{Sender} // '')
        ? $headers->{Sender}
        : (($context->{user} // '') . '@' . ($context->{interface} // ''));
    my $identifier = hmac_id($source_value, $key, 32);
    my $domain = $settings->{pseudonym_domain} // 'postfilter.invalid';

    $headers->{Sender} = "pf-$identifier\@$domain";
    $context->{logger}->headers(
        'header_pseudonymized',
        header => 'Sender',
    );

    return;
}

=head2 _transform_injection_information($context)

Parses the semicolon-separated fields used by INN's C<Injection-Info>.  Unknown
fields are preserved unless a configured transformation specifically replaces
posting-host or posting-account.  Values are split on the first equals sign so
embedded equals characters are not lost.

=cut

# Function: _transform_injection_information
# Purpose: Parses Injection-Info and applies independent posting-host/account policies.
# Parameters: $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _transform_injection_information {
    my ($context) = @_;

    my $headers = $context->{headers};
    my $header_config = $context->{config}{headers};

    if ($header_config->{delete_posting_date}) {
        _remove_header($headers, 'NNTP-Posting-Date');
        _remove_header($headers, 'Injection-Date');
    }

    my $injection_info = $headers->{'Injection-Info'} // '';
    if (length $injection_info) {
        my ($server, @raw_items) = split /\s*;\s*/, $injection_info;
        my @items;

        for my $raw_item (@raw_items) {
            next unless length $raw_item;
            my ($name, $value) = split /\s*=\s*/, $raw_item, 2;
            next unless defined $value;
            $value =~ s/^"|"$//g;
            push @items, {
                name  => lc($name),
                value => $value,
            };
        }

        _apply_injection_field_mode(
            $context,
            \@items,
            'posting-host',
            $header_config->{posting_host},
            $context->{client_hostname} // $context->{client_ip},
        );
        _apply_injection_field_mode(
            $context,
            \@items,
            'posting-account',
            $header_config->{posting_account},
            $context->{user} // '',
        );

        my @output = grep { length } ($server);
        for my $item (@items) {
            push @output, sprintf('%s="%s"', $item->{name}, $item->{value});
        }
        $headers->{'Injection-Info'} = join('; ', @output) . ';';
        return;
    }

    # Older INN configurations may expose only NNTP-Posting-Host.
    my $posting_host = $headers->{'NNTP-Posting-Host'} // '';
    return unless length $posting_host;

    my $settings = $header_config->{posting_host};
    my $mode = $settings->{mode} // 'preserve';

    if ($mode eq 'delete') {
        _remove_header($headers, 'NNTP-Posting-Host');
    }
    elsif ($mode eq 'replace') {
        $headers->{'NNTP-Posting-Host'} = $settings->{replacement} // '';
    }
    elsif ($mode eq 'pseudonymize') {
        my $key = _load_pseudonym_key($context, 'NNTP-Posting-Host');
        if ($key) {
            my $identifier = hmac_id($posting_host, $key, 32);
            $headers->{'NNTP-Posting-Host'} =
                "$identifier.user." . ($context->{interface} // 'localhost');
        }
    }

    return;
}

# Function: _apply_injection_field_mode
# Purpose: Applies preserve/delete/replace/pseudonymize to one parsed Injection-Info field.
# Parameters: $context, $items, $field_name, $settings, $fallback_value
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _apply_injection_field_mode {
    my ($context, $items, $field_name, $settings, $fallback_value) = @_;

    my $mode = $settings->{mode} // 'preserve';
    my @matching = grep { $_->{name} eq $field_name } @{$items};

    if ($mode eq 'preserve') {
        return;
    }

    @{$items} = grep { $_->{name} ne $field_name } @{$items};
    return if $mode eq 'delete';

    if ($mode eq 'replace') {
        push @{$items}, {
            name  => $field_name,
            value => $settings->{replacement} // '',
        };
        return;
    }

    return unless $mode eq 'pseudonymize';

    my $key = _load_pseudonym_key($context, $field_name);
    return unless $key;

    my $source = @matching
        ? $matching[0]{value}
        : $fallback_value;
    my $identifier = hmac_id($source // '', $key, 32);

    push @{$items}, {
        name  => $field_name,
        value => $identifier,
    };

    return;
}

=head2 _transform_path($context)

C<Path> must exist when INN stores the article.  Therefore the configured
C<delete> mode does not remove the header; it replaces it with the minimal
C<not-for-mail>.  C<replace> uses the configured literal and C<pseudonymize>
keeps a stable HMAC marker without exposing the source address.

=cut

# Function: _transform_path
# Purpose: Ensures Path remains storable while applying the configured replacement or HMAC marker.
# Parameters: $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _transform_path {
    my ($context) = @_;

    my $settings = $context->{config}{headers}{path};
    my $mode = $settings->{mode} // 'replace';

    return if $mode eq 'preserve';

    if ($mode eq 'delete') {
        $context->{headers}{Path} = 'not-for-mail';
        return;
    }

    if ($mode eq 'replace') {
        my $replacement = $settings->{replacement} // 'not-for-mail';
        $context->{headers}{Path} = $context->{tor}
            ? "tor-network!$replacement"
            : $replacement;
        return;
    }

    return unless $mode eq 'pseudonymize';

    my $key = _load_pseudonym_key($context, 'Path');
    return unless $key;

    my $identifier = hmac_id(
        $context->{client_hostname} // $context->{client_ip},
        $key,
        32,
    );
    $context->{headers}{Path} = $context->{tor}
        ? "$identifier.POSTED!tor-network!not-for-mail"
        : "$identifier.POSTED!not-for-mail";

    return;
}

# Function: _transform_distribution
# Purpose: Validates Distribution, marks accepted local Message-IDs for deferred storage, and removes the usenet marker.
# Parameters: $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _transform_distribution {
    my ($context) = @_;

    my $headers = $context->{headers};
    my $database = $context->{db};

    if (length($headers->{References} // '') && $database && $database->available) {
        my @references = $headers->{References} =~ /(<[^>]+>)/g;
        my $last_reference = $references[-1];

        if (
            $last_reference
            && $database->local_distribution_exists($last_reference)
            && ($headers->{Distribution} // '') !~ /^(?:local|usenet)$/i
        ) {
            $headers->{Distribution} = 'local';
        }
    }

    if (($headers->{Distribution} // '') =~ /^local$/i) {
        # Do not write the state table here.  Header transformation can still
        # be followed by a custom-rule, persistence or policy rejection.  The
        # orchestrator commits this marker only after the final action accepts
        # the article.
        $context->{local_distribution_to_store} = $context->{message_id};
    }
    elsif (($headers->{Distribution} // '') =~ /^usenet$/i) {
        _remove_header($headers, 'Distribution');
    }
    elsif (length($headers->{Distribution} // '')) {
        my %allowed = map { lc($_) => 1 }
            @{ $context->{config}{distributions} // [] };

        return _reject(
            108,
            distribution => $headers->{Distribution},
        ) unless $allowed{ lc $headers->{Distribution} };
    }

    return Postfilter::Result->pass(
        code    => 'PF-GROUP-000',
        legacy  => 0,
        message => 'Distribution transformed',
    );
}

# Function: _add_tor_header
# Purpose: Writes yes, plaintext IP, or reversible encrypted TOR metadata according to policy.
# Parameters: $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _add_tor_header {
    my ($context) = @_;

    my $settings = $context->{config}{tor}{header};
    my $mode = $settings->{mode} // 'none';
    my $name = $settings->{name} // 'X-Postfilter-TOR';

    if ($mode eq 'none') {
        $context->{headers}{$name} = 'yes';
        $context->{logger}->headers(
            'header_added',
            header => $name,
            mode   => 'marker',
        );
        return;
    }

    if ($mode eq 'plain') {
        $context->{headers}{$name} = $context->{client_ip};
        $context->{logger}->headers(
            'header_added',
            header => $name,
            mode   => 'plain',
        );
        return;
    }

    return unless $mode eq 'encrypted';

    my $key_path =
        $settings->{key_file}
        // $context->{config}{keys}{tor_header};

    my $encrypted = eval {
        my $key = $context->{crypto}->load_key($key_path);
        $context->{crypto}->encrypt_token(
            $context->{client_ip},
            $key,
            'tor-header',
        );
    };

    if ($@ || !defined $encrypted) {
        $context->{logger}->error(
            'tor_header_encryption_failed',
            error => $@ || 'unknown encryption error',
        );
        $context->{headers}{$name} = 'yes';
        $context->{logger}->headers(
            'header_added',
            header => $name,
            mode   => 'encryption-fallback-marker',
        );
        return;
    }

    $context->{headers}{$name} = $encrypted;
    $context->{logger}->headers(
        'header_added',
        header => $name,
        mode   => 'encrypted',
    );
    return;
}

# Function: _keep_only_configured_headers
# Purpose: Deletes headers not present in saved_headers when strict allow-list mode is enabled.
# Parameters: $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _keep_only_configured_headers {
    my ($context) = @_;

    my %keep = map { lc($_) => 1 }
        @{ $context->{config}{saved_headers} // [] };

    for my $name (keys %{ $context->{headers} }) {
        next if $keep{ lc $name };
        _remove_header($context->{headers}, $name);
        $context->{logger}->headers(
            'header_deleted',
            header => $name,
            reason => 'not-in-saved-headers',
        );
    }

    return;
}

# Function: _repair_mime_headers
# Purpose: Normalises MIME-related header values without rewriting valid user content
#          unnecessarily.
# Parameters: $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _repair_mime_headers {
    my ($context) = @_;

    my $loaded = eval {
        require Encode;
        require Encode::MIME::Header;
        1;
    };
    return unless $loaded;

    for my $name (qw(From Subject Sender)) {
        my $value = $context->{headers}{$name} // '';
        next unless length $value;

        my $valid_utf8 = eval {
            Encode::decode('UTF-8', $value, Encode::FB_CROAK());
            1;
        };
        next if $valid_utf8;

        my $encoded = eval { Encode::encode('MIME-Header', $value) };
        next unless defined $encoded;

        $context->{headers}{$name} = $encoded;
        $context->{logger}->headers(
            'header_mime_encoded',
            header => $name,
        );
    }

    return;
}

# Function: _delete_named_headers
# Purpose: Deletes an explicit list of header names and records each transformation.
# Parameters: $context, @names
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _delete_named_headers {
    my ($context, @names) = @_;

    for my $name (@names) {
        next unless exists $context->{headers}{$name};
        _remove_header($context->{headers}, $name);
        $context->{logger}->headers(
            'header_deleted',
            header => $name,
        );
    }

    return;
}


# Function: _remove_header
# Purpose: Marks a header for deletion using the representation required by INN's nnrpd Perl hook.
# Parameters: $headers, $name
# Operational notes: INN documents undef or an empty value for reliable header removal when
#                    $modify_headers is true; deleting the hash key is not portable across headers.
sub _remove_header {
    my ($headers, $name) = @_;
    return 0 unless exists $headers->{$name};
    $headers->{$name} = undef;
    return 1;
}

# Function: _load_pseudonym_key
# Purpose: Loads the dedicated header pseudonym key; on failure it logs and preserves original
#          data.
# Parameters: $context, $header_name
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _load_pseudonym_key {
    my ($context, $header_name) = @_;

    my $path =
        $context->{config}{keys}{header_pseudonym}
        // $context->{config}{headers}{pseudonym_key_file};

    my $key = eval { $context->{crypto}->load_key($path) };
    if ($@ || !defined $key) {
        $context->{logger}->error(
            'header_pseudonym_key_unavailable',
            error  => $@ || 'no key returned',
            header => $header_name,
        );
        return;
    }

    return $key;
}

# Function: _reject
# Purpose: Constructs a rejection result while preserving the historical numeric compatibility
#          code.
# Parameters: $legacy_code, %details
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _reject {
    my ($legacy_code, %details) = @_;
    my ($code, $message) = Postfilter::Codes->lookup($legacy_code);

    return Postfilter::Result->reject(
        code    => $code,
        legacy  => $legacy_code,
        message => $message,
        %details,
    );
}

1;
