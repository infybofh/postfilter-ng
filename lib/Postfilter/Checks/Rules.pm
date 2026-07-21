package Postfilter::Checks::Rules;

use strict;
use warnings;

=head1 NAME

Postfilter::Checks::Rules - Trusted profiles and configurable ban-rule actions.

=head1 RULE VOCABULARY

The clean rewrite uses names that describe what the code actually does.  Historical action
names are accepted only by the migration command and are converted to:

  reject
  drop
  log
  save
  score
  set_score_limit
  add_metric
  set_article_config

No runtime function is named C<legacy_something>.  Compatibility belongs in the
numeric C<legacy_code> field and migration documentation, not in operational API
names.

=head1 SAFETY

Scores are local to one article.  Body rules are evaluated once, not once per
header.  Output files use locking or exclusive creation, sendmail is executed in
list form without a shell, and configuration mutations use the context's
copy-on-write configuration.

=cut

use Fcntl qw(:DEFAULT :flock);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use POSIX qw(strftime);

use Postfilter::Article;
use Postfilter::Codes;
use Postfilter::Result;
use Postfilter::Util qw(ip_in_cidr);

=head2 apply_trusted_profile($context)

Selects the highest-priority enabled profile whose configured conditions match.
C<match_mode = "all"> requires every specified condition; C<any> requires one.
C<match_all = true> creates an unconditional profile.  The selected profile may
skip any named pipeline check or request an explicit full bypass.

=cut

# Function: apply_trusted_profile
# Purpose: Selects the highest-priority trusted profile whose configured conditions match the
#          article.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub apply_trusted_profile {
    my ($class, $context) = @_;

    my @profiles = sort {
        ($b->{priority} // 0) <=> ($a->{priority} // 0)
    } grep {
        ref($_) eq 'HASH' && ($_->{enabled} // 1)
    } @{ $context->{config}{trusted_profile} // [] };

    PROFILE:
    for my $profile (@profiles) {
        next unless $context->rule_applies_to_article_type($profile);
        my @conditions;

        if (@{ $profile->{authenticated_users} // [] }) {
            my %allowed_users = map { $_ => 1 }
                @{ $profile->{authenticated_users} };
            push @conditions,
                $allowed_users{ $context->{user} } ? 1 : 0;
        }

        if (@{ $profile->{source_networks} // [] }) {
            my $network_matched = 0;
            for my $network (@{ $profile->{source_networks} }) {
                if (ip_in_cidr($context->{client_ip}, $network)) {
                    $network_matched = 1;
                    last;
                }
            }
            push @conditions, $network_matched;
        }

        if (defined $profile->{from_pattern}) {
            my $expression = eval { qr/$profile->{from_pattern}/i };
            push @conditions,
                $expression
                && ($context->{headers}{From} // '') =~ $expression
                ? 1
                : 0;
        }

        if (defined $profile->{group_pattern}) {
            my $expression = eval { qr/$profile->{group_pattern}/i };
            my $groups = join ',', @{ $context->{newsgroups} };
            push @conditions,
                $expression && $groups =~ $expression ? 1 : 0;
        }

        if (ref($profile->{header_match}) eq 'ARRAY') {
            for my $header_match (@{ $profile->{header_match} }) {
                my $header_name = $header_match->{name} // '';
                my $expression = eval { qr/$header_match->{pattern}/i };
                push @conditions,
                    $header_name
                    && $expression
                    && ($context->{headers}{$header_name} // '') =~ $expression
                    ? 1
                    : 0;
            }
        }

        my $match_mode = $profile->{match_mode} // 'all';
        my $matched = $profile->{match_all} ? 1 : 0;

        if (@conditions) {
            $matched = $match_mode eq 'any'
                ? scalar(grep { $_ } @conditions) > 0
                : scalar(grep { !$_ } @conditions) == 0;
        }

        next PROFILE unless $matched;

        $context->{trusted_profile} = $profile;
        for my $check (@{ $profile->{skip_checks} // [] }) {
            $context->{skipped_checks}{$check} = 1;
        }

        $context->{logger}->pipeline(
            'trusted_profile_applied',
            profile => $profile->{id},
            skipped => join(',', @{ $profile->{skip_checks} // [] }),
        );

        return $profile;
    }

    return;
}

=head2 run_banlist($context)

Evaluates enabled rules in descending priority.  Matching, scoring and action
state live in lexical hashes created for this call, so a second POST handled by
the same nnrpd process cannot inherit the first article's scores.

=cut

# Function: run_banlist
# Purpose: Evaluates ordered ban rules, named scores, output actions, and configured rejection
#          thresholds.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub run_banlist {
    my ($class, $context) = @_;

    unless ($context->{config}{modules}{banlist}) {
        return Postfilter::Result->pass(
            code    => 'PF-RULE-000',
            legacy  => 0,
            message => 'Banlist disabled',
        );
    }

    my %scores;
    my %score_limits;
    my $evaluations = 0;
    my $evaluation_limit =
        $context->limit('max_rule_evaluations')
        // 2_000;
    my $global_score_limit =
        $context->{config}{banlist}{max_score}
        // 10;

    my @rules = sort {
        ($b->{priority} // 0) <=> ($a->{priority} // 0)
    } @{ $context->{config}{ban_rule} // [] };

    RULE:
    for my $rule (@rules) {
        next unless $context->rule_applies_to_article_type($rule);
        next RULE unless ref($rule) eq 'HASH' && ($rule->{enabled} // 1);

        $evaluations++;
        if ($evaluations > $evaluation_limit) {
            $context->{logger}->warning(
                'ban_rule_evaluation_limit_reached',
                limit => $evaluation_limit,
            );
            last RULE;
        }

        next RULE if _profile_is_excluded($context, $rule);
        next RULE unless _group_scope_matches($context, $rule);

        my ($matched, $matched_target, $matched_value) =
            _rule_matches($context, $rule);
        next RULE unless $matched;

        my $action = lc($rule->{action} // 'reject');
        my $rule_id = $rule->{id} // 'unnamed-rule';
        my $reported_score = 0 + ($rule->{score_value} // $rule->{score} // 0);

        $context->add_hit({
            action  => $action,
            rule_id => $rule_id,
            score   => $reported_score,
            target  => $matched_target,
            value   => $matched_value,
        });

        $context->{force_save} = 1 if $rule->{save_article};

        $context->{logger}->rules(
            'rule_matched',
            action  => $action,
            rule_id => $rule_id,
            target  => $matched_target,
        );

        if ($action eq 'log') {
            my $error = _execute_output_action($context, $rule, 'log');
            return $error if $error;
            next RULE;
        }

        if ($action eq 'save') {
            my $error = _execute_output_action($context, $rule, 'save');
            return $error if $error;

            # With no external destination, save means use Postfilter-NG's
            # standard timestamped rejected-article store.
            $context->{force_save} = 1
                unless _has_output_destination($rule);
            next RULE;
        }

        if ($action eq 'reject') {
            my $error = _execute_output_action($context, $rule, 'reject');
            return $error if $error;
            return _create_rule_rejection($rule, 34);
        }

        if ($action eq 'drop') {
            my $error = _execute_output_action($context, $rule, 'drop');
            return $error if $error;

            my $result = _create_rule_rejection($rule, 34);
            $result->{requested_action} = 'discard';
            return $result;
        }

        if ($action eq 'score') {
            my $result = _apply_score_action(
                $rule,
                \%scores,
                \%score_limits,
                $global_score_limit,
            );
            return $result if $result;
            next RULE;
        }

        if ($action eq 'set_score_limit') {
            my $score_name = $rule->{score_variable} // 'default';
            $score_limits{$score_name} = 0 + ($rule->{score_limit} // 0);
            next RULE;
        }

        if ($action eq 'add_metric') {
            _add_article_metric($context, $rule, \%scores);
            next RULE;
        }

        if ($action eq 'set_article_config') {
            _set_article_config($context, $rule);
            next RULE;
        }

        $context->{logger}->warning(
            'unknown_rule_action',
            action  => $action,
            rule_id => $rule_id,
        );
    }

    for my $score_name (keys %scores) {
        my $error = _score_limit_result(
            {},
            $score_name,
            \%scores,
            \%score_limits,
            $global_score_limit,
        );
        return $error if $error;
    }

    return Postfilter::Result->pass(
        code    => 'PF-RULE-000',
        legacy  => 0,
        message => 'Banlist checks passed',
        scores  => \%scores,
    );
}

=head2 _rule_matches($context, $rule)

Produces candidate values from the target name and applies C<exact>, C<contains>,
C<cidr> or C<regex> matching.  C<any.header> uses separate patterns for the name
and value and returns immediately on the first matching header.

=cut

# Function: _rule_matches
# Purpose: Matches one ban rule against its normalised target and returns match details.
# Parameters: $context, $rule
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _rule_matches {
    my ($context, $rule) = @_;

    my $match_type = $rule->{match_type} // 'regex';
    my $target = $rule->{target} // 'any.header';
    my @candidates;

    if ($target eq 'body') {
        push @candidates, ['body', $context->body_for_expensive_checks];
    }
    elsif ($target eq 'subject') {
        push @candidates, ['subject', $context->{headers}{Subject} // ''];
    }
    elsif ($target eq 'from.address') {
        push @candidates, ['from.address', $context->{from_address}];
    }
    elsif ($target eq 'from.raw') {
        push @candidates, ['from.raw', $context->{headers}{From} // ''];
    }
    elsif ($target eq 'client.ip') {
        push @candidates, ['client.ip', $context->{client_ip}];
    }
    elsif ($target eq 'client.domain') {
        push @candidates, ['client.domain', $context->{client_domain}];
    }
    elsif ($target eq 'auth.user') {
        push @candidates, ['auth.user', $context->{user}];
    }
    elsif ($target eq 'newsgroups') {
        push @candidates, [
            'newsgroups',
            join(',', @{ $context->{newsgroups} }),
        ];
    }
    elsif ($target =~ /^header\.(.+)$/i) {
        my $header_name = $1;
        push @candidates, [
            "header.$header_name",
            $context->{headers}{$header_name} // '',
        ];
    }
    elsif ($target eq 'any.header' || $target eq 'header') {
        return _match_any_header($context, $rule);
    }

    my $pattern = $rule->{pattern} // '';
    my $case_sensitive = $rule->{case_sensitive} ? 1 : 0;

    for my $candidate (@candidates) {
        my ($candidate_name, $candidate_value) = @{$candidate};
        my $matched = 0;

        if ($match_type eq 'exact') {
            $matched = $case_sensitive
                ? $candidate_value eq $pattern
                : lc($candidate_value) eq lc($pattern);
        }
        elsif ($match_type eq 'contains') {
            $matched = $case_sensitive
                ? index($candidate_value, $pattern) >= 0
                : index(lc($candidate_value), lc($pattern)) >= 0;
        }
        elsif ($match_type eq 'cidr') {
            $matched = ip_in_cidr($candidate_value, $pattern);
        }
        else {
            my $expression = eval {
                $case_sensitive ? qr/$pattern/ : qr/$pattern/i;
            };
            $matched = $expression && $candidate_value =~ $expression;
        }

        return (1, $candidate_name, $candidate_value) if $matched;
    }

    return (0);
}

# Function: _match_any_header
# Purpose: Applies separate header-name and header-value expressions across all article headers.
# Parameters: $context, $rule
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _match_any_header {
    my ($context, $rule) = @_;

    my $name_pattern = $rule->{header_name_pattern} // '.*';
    my $value_pattern =
        $rule->{header_value_pattern}
        // $rule->{pattern}
        // '.*';

    my $name_expression = eval { qr/$name_pattern/i };
    my $value_expression = eval { qr/$value_pattern/i };
    return (0) unless $name_expression && $value_expression;

    for my $header_name (keys %{ $context->{headers} }) {
        my $header_value = $context->{headers}{$header_name} // '';
        if (
            $header_name =~ $name_expression
            && $header_value =~ $value_expression
        ) {
            return (1, "header.$header_name", $header_value);
        }
    }

    return (0);
}

=head2 _execute_output_action($context, $rule, $trigger_action)

Implements syslog/file logging and the historical message, maildir, rnews, mbox
and mail save destinations.  New configuration fields describe the actual
operation: C<output_type>, C<output_path>, C<save_format> and C<mail_recipients>.

=cut

# Function: _execute_output_action
# Purpose: Executes configured syslog, file, message, maildir, rnews, mbox, or mail side effects.
# Parameters: $context, $rule, $trigger_action
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _execute_output_action {
    my ($context, $rule, $trigger_action) = @_;

    my $output_type = lc($rule->{output_type} // '');
    return unless length $output_type;

    my $message = _expand_template(
        $context,
        $rule->{log_message}
        // $rule->{response}
        // $rule->{description}
        // 'Ban rule matched',
    );

    if ($output_type eq 'syslog') {
        $context->{logger}->error(
            'ban_rule_output',
            action  => $trigger_action,
            message => $message,
            rule_id => $rule->{id} // '',
        );
        return;
    }

    if ($output_type eq 'file') {
        my $path = $rule->{output_path} // '';
        return _output_failure($context, $rule, 'No output_path configured')
            unless length $path;

        my $line = sprintf(
            "%s rule=%s action=%s message_id=%s message=%s\n",
            strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
            $rule->{id} // '',
            $trigger_action,
            $context->{message_id} // '',
            $message,
        );

        return _append_locked($path, $line)
            ? undef
            : _output_failure(
                $context,
                $rule,
                "Unable to append $path: $!",
            );
    }

    return unless $trigger_action eq 'save';

    my $format = lc($rule->{save_format} // $output_type);
    my $destination =
        $rule->{output_path}
        // $rule->{maildir_path}
        // '';
    my $article = Postfilter::Article->serialize($context);

    if ($format eq 'message' || $format eq 'maildir') {
        my $directory = $format eq 'maildir'
            ? "$destination/new"
            : $destination;
        return _output_failure($context, $rule, 'No output directory configured')
            unless length $directory;

        my $created = eval {
            make_path($directory, { mode => 0750 }) unless -d $directory;
            1;
        };
        return _output_failure(
            $context,
            $rule,
            "Unable to create $directory: $@",
        ) unless $created;

        my $filename = sprintf(
            '%d.%06d.%d.%s',
            int($context->{received_at}),
            int(
                ($context->{received_at} - int($context->{received_at}))
                * 1_000_000
            ),
            $$,
            $context->{message_id_hash} // 'no-message-id',
        );
        my $path = "$directory/$filename";

        return _write_exclusive($path, $article)
            ? undef
            : _output_failure(
                $context,
                $rule,
                "Unable to write $path: $!",
            );
    }

    if ($format eq 'rnews') {
        return _output_failure($context, $rule, 'No output_path configured')
            unless length $destination;
        my $record = '#! rnews ' . length($article) . "\n" . $article;
        return _append_locked($destination, $record)
            ? undef
            : _output_failure(
                $context,
                $rule,
                "Unable to append rnews batch $destination: $!",
            );
    }

    if ($format eq 'mbox') {
        return _output_failure($context, $rule, 'No output_path configured')
            unless length $destination;

        my $sender = $context->{from_address} || 'postfilter-ng';
        my $date = scalar localtime(int($context->{received_at}));
        my $escaped_article = $article;
        $escaped_article =~ s/^From />From /mg;
        my $record = "From $sender $date\n$escaped_article\n";

        return _append_locked($destination, $record)
            ? undef
            : _output_failure(
                $context,
                $rule,
                "Unable to append mbox $destination: $!",
            );
    }

    if ($format eq 'mail') {
        return _send_article_by_mail($context, $rule, $article);
    }

    return _output_failure(
        $context,
        $rule,
        "Unsupported output type or save format '$format'",
    );
}

# Function: _send_article_by_mail
# Purpose: Invokes the configured mailer with a list-form pipe so recipient data never reaches a
#          shell.
# Parameters: $context, $rule, $article
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _send_article_by_mail {
    my ($context, $rule, $article) = @_;

    my $mailer = $context->{config}{paths}{sendmail} // '';
    return _output_failure(
        $context,
        $rule,
        'paths.sendmail is not configured or executable',
    ) unless $mailer && -x $mailer;

    my @recipients = @{ $rule->{mail_recipients} // [] };
    return _output_failure($context, $rule, 'No mail_recipient configured')
        unless @recipients;

    my $sent = eval {
        open my $mail, '|-',
            $mailer,
            '-s',
            ($rule->{mail_subject} // 'Message from Postfilter-NG'),
            @recipients
            or die "Unable to execute $mailer: $!";

        print {$mail} $article
            or die "Unable to write article to $mailer: $!";
        close $mail
            or die "$mailer returned an error";
        1;
    };

    return $sent
        ? undef
        : _output_failure($context, $rule, $@);
}

# Function: _apply_score_action
# Purpose: Implements add, clear, verify, and named score-variable operations.
# Parameters: $rule, $scores, $score_limits, $global_score_limit
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _apply_score_action {
    my ($rule, $scores, $score_limits, $global_score_limit) = @_;

    my $operation = lc($rule->{score_operation} // 'add');
    my $score_name = $rule->{score_variable} // 'default';

    if ($operation eq 'clear') {
        $scores->{$score_name} = 0;
        return;
    }

    if ($operation eq 'verify') {
        return _score_limit_result(
            $rule,
            $score_name,
            $scores,
            $score_limits,
            $global_score_limit,
        );
    }

    my $delta = defined $rule->{score_value}
        ? $rule->{score_value}
        : ($rule->{score} // 1);
    $scores->{$score_name} += 0 + $delta;
    return;
}

# Function: _add_article_metric
# Purpose: Adds group/followup/line/byte metrics to a named rule score.
# Parameters: $context, $rule, $scores
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _add_article_metric {
    my ($context, $rule, $scores) = @_;

    my $metric = $rule->{metric} // 'groups';
    my $score_name = $rule->{score_variable} // 'default';
    my $line_statistics = $context->analyze_lines;

    my %value = (
        body_bytes   => $context->{body_size},
        body_lines   => $line_statistics->{lines},
        followups    => $context->{followup_count},
        groups       => $context->{group_count},
        header_bytes => $context->{header_size},
        lines        => $line_statistics->{lines},
        total_bytes  => $context->{total_size},
    );

    $scores->{$score_name} += $value{$metric} // 0;
    return;
}

# Function: _set_article_config
# Purpose: Applies a dotted configuration override to the article-local copy-on-write
#          configuration.
# Parameters: $context, $rule
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _set_article_config {
    my ($context, $rule) = @_;

    my $key = $rule->{config_key};
    return unless defined $key && length $key;

    my $config = $context->make_config_writable;
    my @path = split /\./, $key;
    my $leaf = pop @path;
    my $cursor = $config;

    for my $component (@path) {
        $cursor->{$component} //= {};
        return unless ref($cursor->{$component}) eq 'HASH';
        $cursor = $cursor->{$component};
    }

    $cursor->{$leaf} = $rule->{config_value};
    return;
}

# Function: _score_limit_result
# Purpose: Returns a rejection only when a named score exceeds its specific or global ceiling.
# Parameters: $rule, $score_name, $scores, $limits, $global_limit
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _score_limit_result {
    my ($rule, $score_name, $scores, $limits, $global_limit) = @_;

    my $score = $scores->{$score_name} // 0;
    my $specific_limit = $limits->{$score_name} // 0;

    return
        unless $score > $global_limit
        || ($specific_limit > 0 && $score > $specific_limit);

    return _create_rule_rejection(
        $rule,
        49,
        maximum => $specific_limit || $global_limit,
        score    => $score,
        variable => $score_name,
    );
}

# Function: _group_scope_matches
# Purpose: Applies optional include/exclude group expressions before evaluating a rule.
# Parameters: $context, $rule
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _group_scope_matches {
    my ($context, $rule) = @_;

    my $groups = join ',', @{ $context->{newsgroups} };

    if ($rule->{include_group_pattern}) {
        return 0 unless $groups =~ /$rule->{include_group_pattern}/i;
    }

    if ($rule->{exclude_group_pattern}) {
        return 0 if $groups =~ /$rule->{exclude_group_pattern}/i;
    }

    return 1;
}

# Function: _profile_is_excluded
# Purpose: Skips a rule for explicitly excluded trusted-profile IDs.
# Parameters: $context, $rule
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _profile_is_excluded {
    my ($context, $rule) = @_;

    my $profile_id = $context->{trusted_profile}{id} // '';
    my %excluded = map { $_ => 1 }
        @{ $rule->{exclude_profiles} // [] };

    return $excluded{$profile_id};
}

# Function: _has_output_destination
# Purpose: Reports whether a rule sends output to an external destination rather than standard
#          saving.
# Parameters: $rule
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _has_output_destination {
    my ($rule) = @_;
    return length($rule->{output_type} // '') ? 1 : 0;
}

# Function: _output_failure
# Purpose: Translates a rule side-effect failure according to banlist.side_effect_failure.
# Parameters: $context, $rule, $detail
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _output_failure {
    my ($context, $rule, $detail) = @_;

    $context->{logger}->error(
        'rule_output_failed',
        detail  => $detail,
        rule_id => $rule->{id} // '',
    );

    return
        if ($context->{config}{banlist}{side_effect_failure} // 'reject')
        ne 'reject';

    my ($code, $message) = Postfilter::Codes->lookup(35);
    return Postfilter::Result->reject(
        code    => $code,
        detail  => $detail,
        legacy  => 35,
        message => $message,
        rule_id => $rule->{id} // '',
    );
}

# Function: _append_locked
# Purpose: Appends a complete record while holding an exclusive advisory file lock.
# Parameters: $path, $content
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _append_locked {
    my ($path, $content) = @_;

    my $directory = dirname($path);
    make_path($directory, { mode => 0750 }) unless -d $directory;

    sysopen(
        my $handle,
        $path,
        O_WRONLY | O_CREAT | O_APPEND,
        0640,
    ) or return;

    flock($handle, LOCK_EX) or do {
        close $handle;
        return;
    };

    my $success = print {$handle} $content;
    $success &&= close $handle;
    return $success ? 1 : 0;
}

# Function: _write_exclusive
# Purpose: Creates one output file with O_EXCL so concurrent nnrpd processes cannot overwrite it.
# Parameters: $path, $content
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _write_exclusive {
    my ($path, $content) = @_;

    sysopen(
        my $handle,
        $path,
        O_WRONLY | O_CREAT | O_EXCL,
        0640,
    ) or return;

    my $success = print {$handle} $content;
    $success &&= close $handle;
    return $success ? 1 : 0;
}

# Function: _expand_template
# Purpose: Expands documented percent placeholders with current article metadata.
# Parameters: $context, $template
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _expand_template {
    my ($context, $template) = @_;

    my %replacement = (
        F => $context->{headers}{From} // '',
        I => $context->{headers}{'NNTP-Posting-Host'}
            // $context->{client_ip}
            // '',
        M => $context->{message_id} // '',
        N => $context->{headers}{Newsgroups} // '',
        P => $context->{headers}{Path} // '',
    );

    $template =~ s/%([MFNPI])/$replacement{$1}/ge;
    return $template;
}

# Function: _create_rule_rejection
# Purpose: Builds a rule rejection using explicit rule codes/messages where supplied.
# Parameters: $rule, $default_legacy_code, %details
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _create_rule_rejection {
    my ($rule, $default_legacy_code, %details) = @_;

    my ($default_code, $default_message) =
        Postfilter::Codes->lookup($default_legacy_code);

    return Postfilter::Result->reject(
        code    => $rule->{reason_code} // $default_code,
        legacy  => defined $rule->{legacy_code}
            ? $rule->{legacy_code}
            : $default_legacy_code,
        message => $rule->{response} // $default_message,
        rule_id => $rule->{id},
        %details,
    );
}

1;
