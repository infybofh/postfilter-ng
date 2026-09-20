package Postfilter::Checks::Style;

use strict;
use warnings;

=head1 NAME

Postfilter::Checks::Style - Structural, header, group and date validation.

=head1 PIPELINE POSITION

This is the first mandatory check for ordinary articles.  It rejects malformed
or policy-incompatible input before expensive DNS and regular-expression work.
Trusted profiles may skip individual check names, but a profile must explicitly
request a full bypass to skip the complete structural stage.

=head1 RETURN VALUE

C<run> returns a Postfilter::Result.  A pass has legacy code zero.  Rejections
retain the original Postfilter numeric code and add the stable symbolic code
from Postfilter::Codes.

=cut

use Postfilter::Codes;
use Postfilter::Checks::Attachments;
use Postfilter::Result;

my %ACTIVE_CACHE;

# Function: run
# Purpose: Runs structural header, group, date, size, line, HTML, and path validation for one
#          article.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub run {
    my ($class, $context) = @_;

    my $config = $context->{config};
    if (exists($config->{modules}{style}) && !$config->{modules}{style}) {
        return Postfilter::Result->pass(
            code    => 'PF-STYLE-000',
            legacy  => 0,
            message => 'Structural checks disabled',
        );
    }

    my $headers = $context->{headers};
    my $limits = {
        map { $_ => $context->limit($_) } qw(
            max_blank_ratio
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
            max_quoted_ratio
            max_total_size
        )
    };
    my $header_config = $config->{headers};

    my $groups_enabled =
        !exists($config->{modules}{groups})
        || $config->{modules}{groups};
    my $dates_enabled =
        !exists($config->{modules}{dates})
        || $config->{modules}{dates};
    my $headers_enabled =
        !exists($config->{modules}{headers})
        || $config->{modules}{headers};

    my $result;

    if ($headers_enabled) {
        return $result
            if !$context->skip('style.control')
            && ($result = _check_control_headers($context));
        return $result if ($result = _check_distribution_header($context));
        return $result
            if !$context->skip('style.content_type')
            && ($result = _check_content_type($context));
    }

    if ($groups_enabled) {
        return $result if ($result = _check_forbidden_crossposts($context));
        return $result if ($result = _check_approved_header($context));

        return _reject(6, detail => 'group_count')
            if $context->{group_count} > $limits->{max_crosspost};

        return _reject(7, detail => 'followup_count')
            if $context->{followup_count} > $limits->{max_followup};

        return _reject(8)
            if $context->{group_count} > ($limits->{max_fup_no_crosspost} // 3)
            && $context->{followup_count} == 0;

        return _reject(10)
            if ($context->{followup_count} - $context->{group_count})
            > $limits->{max_groups_difference};
    }

    return _reject($context->size_rejection_code('body'))
        if $context->{body_size} > $limits->{max_body_size};

    return _reject($context->size_rejection_code('total'))
        if $context->{total_size} > $limits->{max_total_size};

    return _reject($context->size_rejection_code('header'))
        if $headers_enabled
        && $context->{header_size} > $limits->{max_header_size};

    if ($headers_enabled) {
        return _reject(11)
            if ($headers->{Subject} // '') =~ /^Re:\s/i
            && !length($headers->{References} // '');
    }

    if (!$context->skip('style.line_statistics')) {
        my $line_statistics = $context->analyze_lines;
        my $line_count = $line_statistics->{lines} || 1;

        return _reject(12)
            if ($limits->{max_line_length} // 0) > 0
            && $line_statistics->{max_length} > $limits->{max_line_length};

        return _reject(13)
            if $line_statistics->{quoted}
            > $line_count * $limits->{max_quoted_ratio};

        return _reject(14)
            if $line_statistics->{blank}
            > $line_count * $limits->{max_blank_ratio};

        return _reject(15)
            if $line_statistics->{empty}
            > $line_count * $limits->{max_empty_ratio};
    }

    return $result
        if !$context->skip('style.html')
        && ($result = _check_html($context));

    if ($groups_enabled) {
        return $result if ($result = _check_group_existence($context));

        return _reject(25)
            if _count_hierarchies($context->{newsgroups})
            > $limits->{max_hierarchies_post};

        return _reject(26)
            if _count_hierarchies($context->{followups})
            > $limits->{max_hierarchies_followup};

        return $result if ($result = _check_forbidden_groups($context));
    }

    if ($dates_enabled) {
        return $result if ($result = _check_date($context));
    }

    if ($headers_enabled) {
        for my $header_name (keys %{$headers}) {
            return _reject(21, header => $header_name)
                if length($headers->{$header_name} // '')
                > $limits->{max_header_length};
        }

        if (!$header_config->{allow_mail_headers}) {
            for my $header_name (qw(
                Received To Cc CC Bcc BCC Delivered-To Delivered-to
            )) {
                return _reject(22, header => $header_name)
                    if length($headers->{$header_name} // '');
            }
        }

        return _reject(24)
            if length($headers->{References} // '')
            && length($headers->{'In-Reply-To'} // '')
            && index(
                $headers->{References},
                $headers->{'In-Reply-To'},
            ) < 0;

        return $result if ($result = _check_forbidden_headers($context));
        return $result if ($result = _check_path($context));
    }

    return Postfilter::Result->pass(
        code    => 'PF-STYLE-000',
        legacy  => 0,
        message => 'Structural checks passed',
    );
}

=head2 _check_control_headers($context)

Accepts only cancel control messages when C<allow_control_cancel> is true.
Supersedes/Replaces/Cancel are governed separately by C<allow_supersedes>.

=cut

# Function: _check_control_headers
# Purpose: Rejects non-cancel control messages and disallowed cancel/supersedes headers.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_control_headers {
    my ($context) = @_;

    my $headers = $context->{headers};
    my $header_config = $context->{config}{headers};

    for my $name (qw(Control Also-Control)) {
        next unless length($headers->{$name} // '');

        my $is_cancel = $headers->{$name} =~ /^cancel\s+/i;
        return _reject(1, header => $name)
            if !$is_cancel || !$header_config->{allow_control_cancel};
    }

    for my $name (qw(Supersedes Replaces Cancel)) {
        return _reject(51, header => $name)
            if length($headers->{$name} // '')
            && !$header_config->{allow_supersedes};
    }

    return;
}

=head2 _check_forbidden_crossposts($context)

Evaluates configured pairs only when the article targets at least two groups.
Regexes have already been compiled for validity during configuration loading.

=cut

# Function: _check_forbidden_crossposts
# Purpose: Rejects articles whose group set matches both sides of a forbidden-crosspost rule.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_forbidden_crossposts {
    my ($context) = @_;
    return if $context->{group_count} < 2;

    my $joined_groups = join ',', @{ $context->{newsgroups} };

    for my $rule (@{ $context->{config}{forbidden_crosspost} // [] }) {
        next unless ref($rule) eq 'HASH' && ($rule->{enabled} // 1);
        next unless $context->rule_applies_to_article_type($rule);

        my $left  = $rule->{left}  // '';
        my $right = $rule->{right} // '';
        next unless length($left) && length($right);

        if ($joined_groups =~ /$left/i && $joined_groups =~ /$right/i) {
            return _reject(2, rule_id => $rule->{id});
        }
    }

    return;
}

=head2 _check_approved_header($context)

A user-supplied C<Approved> header is rejected unless at least one configured
moderation exception matches the target groups.

=cut

# Function: _check_approved_header
# Purpose: Allows Approved only for configured moderated exceptions.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_approved_header {
    my ($context) = @_;
    return unless length($context->{headers}{Approved} // '');

    my $groups = join ',', @{ $context->{newsgroups} };
    for my $pattern (@{ $context->{config}{moderated_exceptions} // [] }) {
        return if $groups =~ /$pattern/i;
    }

    return _reject(3);
}

=head2 _check_distribution_header($context)

Checks only the syntax/policy whitelist.  The later header transformation stage
handles the special C<local> and C<usenet> behaviours and persists local reply
state in SQLite.

=cut

# Function: _check_distribution_header
# Purpose: Validates an incoming Distribution value against the configured allow-list.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_distribution_header {
    my ($context) = @_;
    return unless $context->{config}{headers}{check_distribution};

    my $distribution = $context->{headers}{Distribution} // '';
    return unless length $distribution;

    my %allowed = map { lc($_) => 1 }
        @{ $context->{config}{distributions} // [] };

    return _reject(4, distribution => $distribution)
        unless $allowed{ lc $distribution };

    return;
}

=head2 _check_content_type($context)

Plain text is accepted directly.  Additional MIME types require a matching
C<content_type_rule> for the target group.  A missing Content-Type is preserved
for compatibility with plain-text Usenet clients.

=cut

# Function: _check_content_type
# Purpose: Accepts text/plain or a group-scoped explicitly allowed MIME content type.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_content_type {
    my ($context) = @_;

    my $content_type = $context->{headers}{'Content-Type'} // '';
    return unless length $content_type;

    return if $content_type =~ m{^\s*text/plain(?:\s*;|\s*$)}i;


    # Complex MIME containers and managed media must reach the dedicated
    # attachment checker.  The helper only approves explicitly configured
    # top-level types; recursive parts are still validated later in the
    # pipeline by Postfilter::Checks::Attachments->run().
    return if Postfilter::Checks::Attachments
        ->top_level_content_type_is_managed($context);
    my $groups = join ',', @{ $context->{newsgroups} };
    for my $rule (@{ $context->{config}{content_type_rule} // [] }) {
        next unless ref($rule) eq 'HASH' && ($rule->{enabled} // 1);
        next unless $context->rule_applies_to_article_type($rule);

        my $group_pattern = $rule->{group_pattern} // '(?!)';
        my $allowed_pattern = $rule->{allowed_pattern} // '(?!)';
        next unless $groups =~ /$group_pattern/i;

        return if $content_type =~ /$allowed_pattern/i;
    }

    return _reject(5, content_type => $content_type);
}

=head2 _check_html($context)

Searches only the configured bounded scan body.  Group exceptions are evaluated
before HTML patterns.  Operators should list specific tags rather than C<.*> to
avoid turning ordinary angle brackets into false positives.

=cut

# Function: _check_html
# Purpose: Detects configured HTML patterns outside explicitly allowed groups.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_html {
    my ($context) = @_;
    return if $context->content_setting('allow_html');

    my $groups = join ',', @{ $context->{newsgroups} };
    for my $pattern (@{ $context->{config}{html_allowed_groups} // [] }) {
        return if $groups =~ /$pattern/i;
    }

    my $scan_body = $context->body_for_expensive_checks;
    for my $pattern (@{ $context->{config}{html_patterns} // [] }) {
        return _reject(16, pattern => $pattern)
            if $scan_body =~ /$pattern/is;
    }

    return;
}

=head2 _check_group_existence($context)

Loads INN's active file into a process-local cache keyed by path and mtime.
This avoids one complete active-file scan per target group while still detecting
changes made during a long client session.

=cut

# Function: _check_group_existence
# Purpose: Loads/caches active and validates Newsgroups and Followup-To entries.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_group_existence {
    my ($context) = @_;
    return unless $context->{config}{headers}{check_groups_existence};

    my $path = $context->{config}{paths}{active_file};
    return _reject(37) unless $path && -r $path;

    my $mtime = (stat($path))[9] // 0;
    if (
        !$ACTIVE_CACHE{$path}
        || $ACTIVE_CACHE{$path}{mtime} != $mtime
    ) {
        open my $handle, '<', $path or return _reject(37);

        my %groups;
        while (my $line = <$handle>) {
            my ($name) = split /\s+/, $line;
            $groups{$name} = 1 if defined $name;
        }
        close $handle;

        $ACTIVE_CACHE{$path} = {
            groups => \%groups,
            mtime  => $mtime,
        };
    }

    my $known_groups = $ACTIVE_CACHE{$path}{groups};

    for my $group (@{ $context->{newsgroups} }) {
        return _reject(17, group => $group)
            unless $known_groups->{$group};
    }

    for my $group (@{ $context->{followups} }) {
        next if $group eq 'poster' || $group eq 'junk';
        return _reject(18, group => $group)
            unless $known_groups->{$group};
    }

    return;
}

=head2 _check_date($context)

Parses the Date header with Date::Parse.  A missing runtime module is a server
problem, not an article error: it is logged and the date check is skipped.  The
installer normally prevents this state, and Postfilter::Dependencies disables
the entire dates module before the first article.

=cut

# Function: _check_date
# Purpose: Parses Date and enforces future grace and maximum-age policy when Date::Parse is
#          available.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_date {
    my ($context) = @_;

    my $value = $context->{headers}{Date} // '';
    return _reject(19, reason => 'missing-date') unless length $value;

    my $loaded = eval { require Date::Parse; 1 };
    if (!$loaded) {
        $context->{logger}->error(
            'date_parser_unavailable',
            error => $@,
        );
        return;
    }

    my $epoch = Date::Parse::str2time($value);
    return _reject(19, reason => 'unparseable-date')
        unless defined $epoch;

    my $now = $context->{received_at};
    my $future_grace =
        $context->{config}{timeouts}{future_grace_seconds}
        // 3_600;
    my $maximum_age =
        $context->{config}{timeouts}{too_old_seconds}
        // 259_200;

    return _reject(19, difference => $epoch - $now)
        if $epoch - $now > $future_grace;

    return _reject(58, difference => $now - $epoch)
        if $now - $epoch > $maximum_age;

    return;
}

=head2 _check_forbidden_headers($context)

Matches header names, not values.  Each rule may provide an exception regex for
safe names that would otherwise match a broad pattern.

=cut

# Function: _check_forbidden_headers
# Purpose: Applies named forbidden-header rules with optional name exceptions.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_forbidden_headers {
    my ($context) = @_;

    for my $rule (@{ $context->{config}{forbidden_header_rule} // [] }) {
        next unless ref($rule) eq 'HASH' && ($rule->{enabled} // 1);
        next unless $context->rule_applies_to_article_type($rule);

        my $match = $rule->{name_pattern} // '';
        next unless length $match;

        my $exception = $rule->{exception_pattern} // '(?!)';
        for my $header_name (keys %{ $context->{headers} }) {
            if (
                $header_name =~ /$match/i
                && $header_name !~ /$exception/i
            ) {
                return _reject(
                    53,
                    header  => $header_name,
                    rule_id => $rule->{id},
                );
            }
        }
    }

    return;
}

# Function: _check_forbidden_groups
# Purpose: Rejects newsgroup/followup sets matching any configured forbidden-group regex.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_forbidden_groups {
    my ($context) = @_;

    # forbidden_groups describes newsgroup names, not the serialized header
    # value.  Match every Newsgroups and Followup-To target independently so
    # anchored expressions (for example ^alt\.example$) still work when the
    # forbidden group is one element of a crosspost or followup list.
    my @groups = (
        @{ $context->{newsgroups} // [] },
        @{ $context->{followups}  // [] },
    );

    for my $pattern (@{ $context->{config}{forbidden_groups} // [] }) {
        for my $group (@groups) {
            return _reject(54, pattern => $pattern, group => $group)
                if $group =~ /$pattern/i;
        }
    }

    return;
}

=head2 _check_path($context)

An absent Path is accepted.  This is necessary for offline raw-client tests and
for compatibility with callers that invoke the engine before INN has inserted
its Path.  When Path is present, embedded CR/LF/NUL or whitespace-only content is
rejected.  INN normally constructs a valid Path before calling C<filter_post>.

=cut

# Function: _check_path
# Purpose: Accepts an absent raw-client Path but rejects present Path values containing injection
#          characters.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _check_path {
    my ($context) = @_;

    my $path = $context->{headers}{Path} // '';
    return unless length $path;

    return _reject(20)
        if $path =~ /[\r\n\0]/
        || $path =~ /^\s+$/;

    return;
}

# Function: _count_hierarchies
# Purpose: Counts unique top-level hierarchies in a group array.
# Parameters: $groups
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _count_hierarchies {
    my ($groups) = @_;

    my %hierarchies;
    for my $group (@{$groups}) {
        my ($hierarchy) = split /\./, $group, 2;
        $hierarchies{$hierarchy} = 1
            if defined $hierarchy && length $hierarchy;
    }

    return scalar keys %hierarchies;
}

# Function: _reject
# Purpose: Constructs a rejection result while preserving the historical numeric compatibility
#          code.
# Parameters: $legacy_code, %details
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _reject {
    my ($legacy_code, %details) = @_;
    my ($symbolic_code, $message) = Postfilter::Codes->lookup($legacy_code);

    return Postfilter::Result->reject(
        code    => $symbolic_code,
        legacy  => $legacy_code,
        message => $message,
        %details,
    );
}

1;
