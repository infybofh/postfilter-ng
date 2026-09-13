package Postfilter::Context;

use strict;
use warnings;

=head1 NAME

Postfilter::Context - Per-article state shared by Postfilter-NG checks.

=head1 DESCRIPTION

A new context is created for every C<filter_post> invocation.  No score, rule
match, deadline or article-derived value is stored in a package global.  This is
essential because one nnrpd process may accept several POST commands during the
same client session.

The configuration reference is immutable and shared by all articles in a process.
The C<set_article_config> rule action uses copy-on-write, so only an article that
matches that action receives a private configuration copy.

=cut

use Digest::SHA qw(sha256_hex);
use Storable qw(dclone);
use Time::HiRes qw(time);

use Postfilter::ArticleType;
use Postfilter::Util qw(
    normalize_email
    registered_domain
    split_groups
    valid_followup_to
    valid_newsgroup_list
);

# Function: new
# Purpose: Builds a fresh isolated context from one INN article, client attributes, and immutable
#          configuration.
# Parameters: $class, %arguments
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub new {
    my ($class, %arguments) = @_;

    my $headers    = $arguments{headers}    || {};
    my $body       = $arguments{body}       // '';
    my $attributes = $arguments{attributes} || {};
    my $config     = $arguments{config};
    my $now        = time;

    my $client_ip = $attributes->{ipaddress} // '';
    my $client_hostname = $attributes->{hostname} // $client_ip;
    my $interface = $attributes->{interface} // '';

    # The X-Trace fallback preserves compatibility with older INN deployments
    # and with offline fixtures that do not provide the attributes hash.
    if (!$client_ip && ($headers->{'X-Trace'} // '') =~ /^\S+\s+\d+\s+\d+\s+(\S+)/) {
        $client_ip = $1;
        $client_hostname = $headers->{'NNTP-Posting-Host'} // $client_ip;
    }

    if (
        $client_ip eq '::1'
        && ($config->{compatibility}{map_ipv6_loopback_to_ipv4} // 0)
    ) {
        $client_ip = '127.0.0.1';
    }

    my $newsgroups_syntax_valid = valid_newsgroup_list($headers->{Newsgroups});
    my $followup_present = exists $headers->{'Followup-To'};
    my $followup_syntax_valid = !$followup_present
        || valid_followup_to($headers->{'Followup-To'});

    my $newsgroups = split_groups($headers->{Newsgroups});
    my $followups  = split_groups($headers->{'Followup-To'});

    # Article type is resolved before any policy check.  Mixed text/binary
    # crossposts therefore cannot obtain a trusted-profile bypass and binary
    # articles receive their own limits before the first size comparison.
    my $classification = Postfilter::ArticleType->classify(
        $config,
        $newsgroups,
    );
    my $article_type = $classification->{article_type};
    my $article_type_profile =
        $article_type eq 'text' || $article_type eq 'binary'
        ? ($config->{article_types}{$article_type} || {})
        : {};

    my $header_text = '';
    for my $header_name (sort keys %{$headers}) {
        next if $header_name eq '__BODY__';
        $header_text .= "$header_name: " . ($headers->{$header_name} // '') . "\n";
    }

    my $digest_input = _digest_input(
        $config->{access}{article_digest_mode} // 'simple',
        $headers,
        $body,
    );

    my $self = bless {
        article_digest  => sha256_hex($digest_input),
        article_type    => $article_type,
        article_type_profile => $article_type_profile,
        binary_groups   => $classification->{binary_groups},
        classification_mixed => $classification->{mixed},
        text_groups     => $classification->{text_groups},
        attributes      => $attributes,
        body            => $body,
        body_size       => length($body),
        client_domain   => registered_domain(
            $client_hostname,
            $arguments{suffixes},
        ),
        client_hostname => $client_hostname,
        client_ip       => $client_ip,
        config          => $config,
        config_is_copy  => 0,
        crypto          => $arguments{crypto},
        db              => $arguments{db},
        deadline        => undef,
        deadline_started_at => undef,
        dns_started_at  => undef,
        final_action    => undef,
        followup_count  => scalar(@{$followups}),
        followups       => $followups,
        force_save      => 0,
        from_address    => normalize_email($headers->{From}),
        group_count     => scalar(@{$newsgroups}),
        header_size     => length($header_text),
        headers         => $headers,
        interface       => $interface,
        line_stats      => undef,

        # Set by the Distribution transformation and committed only after the
        # final policy accepts the article.  This prevents a later rejection
        # from leaving a false local-distribution history record.
        local_distribution_to_store => undef,

        logger          => $arguments{logger},
        message_id      => $headers->{'Message-ID'} // '',
        newsgroups      => $newsgroups,
        newsgroups_syntax_valid => $newsgroups_syntax_valid ? 1 : 0,
        followup_syntax_valid   => $followup_syntax_valid ? 1 : 0,
        notes           => [],
        pid             => $$,
        processing_start => $arguments{processing_start} // $now,
        received_at      => $now,
        received_at_int  => int($now),
        rule_hits        => [],
        saved_path       => undef,
        skipped_checks   => {},
        suffixes         => $arguments{suffixes} || {},
        technical_result => undef,
        tor              => 0,
        total_size       => length($body) + length($header_text),
        trusted_profile  => {},
        unique_domains   => undef,
        urls             => undef,
        user             => $arguments{user} // '',
    }, $class;

    return $self;
}

# Function: _digest_input
# Purpose: Builds the configured body/simple/complex/all byte sequence used for multipost hashing.
# Parameters: $mode, $headers, $body
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _digest_input {
    my ($mode, $headers, $body) = @_;

    return $body if $mode eq 'body';

    if ($mode eq 'simple') {
        return 'Subject: ' . ($headers->{Subject} // '') . "\n\n$body";
    }

    if ($mode eq 'complex') {
        return 'Newsgroups: ' . ($headers->{Newsgroups} // '')
            . "\nSubject: " . ($headers->{Subject} // '')
            . "\n\n$body";
    }

    return 'Newsgroups: ' . ($headers->{Newsgroups} // '')
        . "\nFrom: " . ($headers->{From} // '')
        . "\nFollowup-To: " . ($headers->{'Followup-To'} // '')
        . "\nSubject: " . ($headers->{Subject} // '')
        . "\n\n$body";
}

=head2 body_for_expensive_checks()

Returns at most C<limits.max_body_scan_bytes> bytes for checks whose cost grows
with body size, such as badword and URL scans.  A value of zero means the whole
body.  Absolute article-size validation always uses the original complete body.

=cut

# Function: body_for_expensive_checks
# Purpose: Returns the full body or the configured prefix used by cost-bounded scans.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub body_for_expensive_checks {
    my ($self) = @_;

    my $maximum = $self->limit('max_body_scan_bytes') // 0;
    return $self->{body} if $maximum <= 0;
    return substr($self->{body}, 0, $maximum);
}

=head2 analyze_lines()

Computes line statistics once and caches them inside this article context.  The
body may be truncated according to C<max_body_scan_bytes>; the configuration
comments explicitly warn that a limit lower than C<max_body_size> trades complete
inspection for a hard CPU bound.

=cut

# Function: analyze_lines
# Purpose: Computes and caches line, quote, blank, empty, and maximum-length statistics.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub analyze_lines {
    my ($self) = @_;
    return $self->{line_stats} if $self->{line_stats};

    my @lines = split /\r?\n/, $self->body_for_expensive_checks, -1;
    my ($quoted, $empty, $blank, $maximum_length) = (0, 0, 0, 0);

    for my $line (@lines) {
        $quoted++ if $line =~ /^[>:|]/;
        $empty++  if $line eq '';
        $blank++  if $line ne '' && $line =~ /^\s+$/;

        my $length = length $line;
        $maximum_length = $length if $length > $maximum_length;
    }

    $self->{line_stats} = {
        blank      => $blank,
        empty      => $empty,
        lines      => scalar(@lines),
        max_length => $maximum_length,
        quoted     => $quoted,
    };

    return $self->{line_stats};
}

=head2 extract_urls()

Extracts unique HTTP/HTTPS URLs up to C<max_urls_to_check>.  The routine is not a
full HTML parser; it intentionally recognises the forms useful for URI DNS lists
while enforcing a predictable work bound.

=cut

# Function: extract_urls
# Purpose: Extracts unique HTTP/HTTPS URLs under the configured work limit.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub extract_urls {
    my ($self) = @_;
    return $self->{urls} if $self->{urls};

    my $maximum_urls = $self->limit('max_urls_to_check') // 20;
    my $scan_body = $self->body_for_expensive_checks;
    my (%seen, @urls);

    while ($scan_body =~ m{\bhttps?://[^\s<>"'\]\[()]+}ig) {
        my $url = $&;
        $url =~ s/[.,;:!?]+$//;
        next if $seen{$url}++;

        push @urls, $url;
        last if @urls >= $maximum_urls;
    }

    $self->{urls} = \@urls;
    return $self->{urls};
}

=head2 extract_domains()

Returns unique registrable domains from the extracted URLs, bounded by
C<max_unique_domains>.  This prevents an article containing thousands of unique
URLs from causing thousands of DNS queries.

=cut

# Function: extract_domains
# Purpose: Converts extracted URL hosts to unique registrable domains under the configured limit.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub extract_domains {
    my ($self) = @_;
    return $self->{unique_domains} if $self->{unique_domains};

    my $maximum_domains = $self->limit('max_unique_domains') // 10;
    my (%seen, @domains);

    for my $url (@{ $self->extract_urls }) {
        my ($host) = $url =~ m{
            ^https?://
            (?:[^@/]+@)?
            (\[[^\]]+\]|[^/:]+)
        }ix;
        next unless $host;

        $host =~ s/^\[|\]$//g;
        my $domain = registered_domain($host, $self->{suffixes});
        next unless $domain;
        next if $seen{$domain}++;

        push @domains, $domain;
        last if @domains >= $maximum_domains;
    }

    $self->{unique_domains} = \@domains;
    return $self->{unique_domains};
}

=head2 make_config_writable()

Creates a deep copy of the configuration only when a matched rule needs to alter
an article-local setting.  It returns the writable hash reference.

=cut

# Function: make_config_writable
# Purpose: Creates a private configuration copy only when an article-local rule override is
#          required.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub make_config_writable {
    my ($self) = @_;

    if (!$self->{config_is_copy}) {
        $self->{config} = dclone($self->{config});
        $self->{config_is_copy} = 1;
    }

    return $self->{config};
}

=head2 start_processing_budget() / deadline_exceeded() / remaining_processing_ms()

The article context measures total wall-clock latency from C<processing_start>,
while the bounded filtering deadline begins explicitly after context creation,
identity logging and trusted-profile resolution.  This prevents slow syslog
routing from consuming the budget before the first article check.

=cut

# Function: start_processing_budget
# Purpose: Starts the bounded check-and-transformation deadline once per article.
# Parameters: $self
# Operational notes: Repeated calls are harmless.  A zero max_processing_ms value leaves the
#                    deadline disabled while total elapsed timing remains available.
sub start_processing_budget {
    my ($self) = @_;
    return if defined $self->{deadline_started_at};

    my $started_at = time;
    my $maximum_processing_ms =
        $self->{config}{timeouts}{max_processing_ms}
        // 0;

    $self->{deadline_started_at} = $started_at;
    $self->{deadline} = $maximum_processing_ms > 0
        ? $started_at + ($maximum_processing_ms / 1000)
        : undef;

    return;
}

# Function: deadline_exceeded
# Purpose: Reports whether the bounded check-and-transformation deadline has expired.
# Parameters: $self
# Operational notes: A budget that has not started, or a configured zero limit, never expires.
sub deadline_exceeded {
    my ($self) = @_;
    return 0 unless defined $self->{deadline};
    return time >= $self->{deadline};
}

# Function: remaining_processing_ms
# Purpose: Returns milliseconds left in the bounded check-and-transformation budget.
# Parameters: $self
# Operational notes: Returns undef when the deadline is disabled or has not started.
sub remaining_processing_ms {
    my ($self) = @_;
    return undef unless defined $self->{deadline};

    my $remaining = ($self->{deadline} - time) * 1000;
    return $remaining > 0 ? $remaining : 0;
}

# Function: pipeline_elapsed_ms
# Purpose: Returns wall-clock milliseconds since the bounded filtering budget began.
# Parameters: $self
# Operational notes: Returns zero before start_processing_budget is called.
sub pipeline_elapsed_ms {
    my ($self) = @_;
    return 0 unless defined $self->{deadline_started_at};
    return (time - $self->{deadline_started_at}) * 1000;
}

=head2 is_public_user()

Classifies the nnrpd user. An undefined or empty user is public. Administrators
may also list synthetic public identities assigned by F<readers.conf> or provide
an optional regular expression for site-specific public identities.

=cut

# Function: is_public_user
# Purpose: Classifies empty and configured synthetic nnrpd identities as public without inverting
#          real users.
# Parameters: $self
# Operational notes: No persistent external state is changed.
sub is_public_user {
    my ($self) = @_;

    my $user = $self->{user} // '';
    return 1 if $user eq '';

    my %public_ids = map { $_ => 1 }
        @{ $self->{config}{access}{public_user_ids} // [] };
    return 1 if $public_ids{$user};

    my $pattern = $self->{config}{access}{public_user_pattern} // '';
    return 0 unless length $pattern;

    my $regexp = eval { qr/$pattern/i };
    return $regexp && $user =~ $regexp ? 1 : 0;
}

# Function: header
# Purpose: Returns one article header or an empty string.
# Parameters: $self, $name
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub header {
    my ($self, $name) = @_;
    return $self->{headers}{$name} // '';
}

# Function: set_header
# Purpose: Sets one article header in the current per-article context.
# Parameters: $self, $name, $value
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub set_header {
    my ($self, $name, $value) = @_;
    $self->{headers}{$name} = $value;
    return;
}

# Function: delete_header
# Purpose: Deletes one article header from the current per-article context.
# Parameters: $self, $name
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub delete_header {
    my ($self, $name) = @_;
    $self->{headers}{$name} = undef if exists $self->{headers}{$name};
    return;
}

# Function: skip
# Purpose: Returns whether a trusted profile skipped a named check.
# Parameters: $self, $check
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub skip {
    my ($self, $check) = @_;

    return 1 if $self->{skipped_checks}{$check};

    my %article_type_skip = map { $_ => 1 }
        @{ $self->{article_type_profile}{checks}{skip} // [] };
    return $article_type_skip{$check} ? 1 : 0;
}

=head2 limit($name)

Returns the article-type-specific limit when configured, otherwise the shared
limit.  This preserves one common policy for values the newsmaster does not want
to split while permitting completely different text and binary size budgets.

=cut

sub limit {
    my ($self, $name) = @_;

    if (exists $self->{article_type_profile}{limits}{$name}) {
        return $self->{article_type_profile}{limits}{$name};
    }

    return $self->{config}{limits}{$name};
}

=head2 content_setting($name)

Returns a text/binary content option such as C<allow_yenc>, C<allow_uuencode>,
or C<allow_html>.  When no article-type override exists, the historical shared
header setting is used for backwards compatibility.

=cut

sub content_setting {
    my ($self, $name) = @_;

    if (exists $self->{article_type_profile}{content}{$name}) {
        return $self->{article_type_profile}{content}{$name};
    }

    return $self->{config}{headers}{$name};
}

=head2 rule_applies_to_article_type($entry)

Rules and providers are shared by default.  Adding
C<article_types = ["text"]> or C<["binary"]> limits one entry without
requiring duplicate configuration files or group regexes.

=cut

sub rule_applies_to_article_type {
    my ($self, $entry) = @_;

    my $types = $entry->{article_types};
    return 1 unless ref($types) eq 'ARRAY' && @{$types};

    for my $type (@{$types}) {
        return 1 if $type eq $self->{article_type};
    }

    return 0;
}

=head2 should_save_rejection($result)

Applies the independent text/binary reject-save policy.  C<all> saves every
technical rejection, C<none> saves none, and C<selected> matches symbolic codes,
numeric compatibility codes, or rule IDs.  A rule-level C<save_article> request
always wins.

=cut

sub should_save_rejection {
    my ($self, $result) = @_;

    return 1 if $self->{force_save};
    return 0 unless $result && $result->is_reject;

    my $policy = $self->{article_type_profile}{save_rejected} || {};
    my $mode = $policy->{mode} // 'none';
    return 1 if $mode eq 'all';
    return 0 if $mode eq 'none';

    my %reason_code = map { $_ => 1 }
        @{ $policy->{reason_codes} // [] };
    return 1 if $reason_code{ $result->{code} // '' };

    my %compatibility_code = map { 0 + $_ => 1 }
        grep { defined $_ && /^\d+$/ }
        @{ $policy->{compatibility_codes} // [] };
    return 1 if $compatibility_code{ 0 + ($result->{legacy} // 0) };

    my %rule_id = map { $_ => 1 }
        @{ $policy->{rule_ids} // [] };
    return 1 if $rule_id{ $result->{rule_id} // '' };

    return 0;
}

=head2 saved_article_subdirectory()

Returns the configured text/binary subdirectory.  The default keeps the two
worlds physically separate even when they share one C<paths.saved_dir> root.

=cut

sub saved_article_subdirectory {
    my ($self) = @_;

    return $self->{article_type_profile}{save_rejected}{subdirectory}
        // $self->{article_type};
}

=head2 size_rejection_code($component)

Maps body/header/total size failures to distinct text and binary compatibility
codes.  This makes statistics and selective saved-article debugging unambiguous.

=cut

sub size_rejection_code {
    my ($self, $component) = @_;

    my %code = (
        text => {
            body   => 96,
            header => 97,
            total  => 98,
        },
        binary => {
            body   => 99,
            header => 100,
            total  => 101,
        },
    );

    return $code{ $self->{article_type} }{$component}
        // 103;
}

# Function: add_hit
# Purpose: Appends one structured rule-hit record for later SQLite persistence.
# Parameters: $self, $hit
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub add_hit {
    my ($self, $hit) = @_;
    push @{ $self->{rule_hits} }, $hit;
    return;
}

# Function: elapsed_ms
# Purpose: Returns total processing time elapsed for the current article.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub elapsed_ms {
    my ($self) = @_;
    return (time - $self->{processing_start}) * 1000;
}

1;
