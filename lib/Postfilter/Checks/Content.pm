package Postfilter::Checks::Content;

use strict;
use warnings;

=head1 NAME

Postfilter::Checks::Content - Body encoding and configurable badword checks.

=head1 DESCRIPTION

The module preserves the historical uuencode, yEnc and score-based badword
features while enforcing explicit work limits.  Badword rules are validated at
configuration load time, evaluated against a bounded body slice and recorded in
SQLite through the context's rule-hit list.

=cut

use Postfilter::Codes;
use Postfilter::Result;

=head2 run_binary($context)

Detects traditional uuencode blocks and yEnc headers.  The regular expressions
are intentionally anchored to line starts to avoid rejecting ordinary prose that
merely mentions the strings C<begin> or C<=ybegin>.

=cut

# Function: run_binary
# Purpose: Detects forbidden uuencode and yEnc payload markers within the configured scan budget.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub run_binary {
    my ($class, $context) = @_;

    if (
        exists($context->{config}{modules}{content})
        && !$context->{config}{modules}{content}
    ) {
        return Postfilter::Result->pass(
            code    => 'PF-BODY-000',
            legacy  => 0,
            message => 'Content checks disabled',
        );
    }

    my $body = $context->body_for_expensive_checks;
    my $allow_uuencode = $context->content_setting('allow_uuencode');
    my $allow_yenc = $context->content_setting('allow_yenc');

    my $contains_uuencode = $body =~ m{
        (?:^|\n)
        begin\s+[0-7]{3}\s+[^\r\n]+\r?\n
        (?:[\x20-\x60]{10,}\r?\n)+
    }mx;

    if (!$allow_uuencode && $contains_uuencode) {
        return $context->{article_type} eq 'binary'
            ? _reject(102, encoding => 'uuencode')
            : _reject(52, encoding => 'uuencode');
    }

    my $contains_yenc = $body =~ /(?:^|\n)=ybegin\s+[^\r\n]+/mi;
    if (!$allow_yenc && $contains_yenc) {
        return $context->{article_type} eq 'binary'
            ? _reject(102, encoding => 'yenc')
            : _reject(62, encoding => 'yenc');
    }

    return Postfilter::Result->pass(
        code    => 'PF-BODY-000',
        legacy  => 0,
        message => 'Binary encoding checks passed',
    );
}

=head2 run_badwords($context)

Evaluates C<[[badword]]> entries in order.  A rule may score Subject, body or
both, request immediate rejection, save the article or merely contribute to a
threshold.  The reported score reflects only targets that actually matched.

=cut

# Function: run_badwords
# Purpose: Evaluates badword rules against Subject/body and applies score or immediate-reject
#          actions.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub run_badwords {
    my ($class, $context) = @_;

    my $config = $context->{config};
    unless ($config->{modules}{badwords}) {
        return Postfilter::Result->pass(
            code    => 'PF-RULE-000',
            legacy  => 0,
            message => 'Badword checks disabled',
        );
    }

    my $subject_score = 0;
    my $body_score = 0;
    my $evaluations = 0;
    my $maximum_evaluations =
        $context->limit('max_rule_evaluations')
        // 2_000;
    my $scan_body = $context->body_for_expensive_checks;

    for my $rule (@{ $config->{badword} // [] }) {
        next unless ref($rule) eq 'HASH' && ($rule->{enabled} // 1);
        next unless $context->rule_applies_to_article_type($rule);

        $evaluations++;
        if ($evaluations > $maximum_evaluations) {
            $context->{logger}->warning(
                'badword_evaluation_limit_reached',
                limit => $maximum_evaluations,
            );
            last;
        }

        my $pattern = $rule->{pattern} // '';
        next unless length $pattern;

        my $matcher = _build_matcher($rule, $pattern);
        next unless $matcher;

        my %targets = map { $_ => 1 }
            @{ $rule->{targets} // ['subject', 'body'] };

        my $subject_matched =
            $targets{subject}
            && $matcher->($context->{headers}{Subject} // '');
        my $body_matched =
            $targets{body}
            && $matcher->($scan_body);

        next unless $subject_matched || $body_matched;

        my $matched_score = 0;
        if ($subject_matched) {
            my $score = 0 + ($rule->{subject_score} // 0);
            $subject_score += $score;
            $matched_score += $score;
        }
        if ($body_matched) {
            my $score = 0 + ($rule->{body_score} // 0);
            $body_score += $score;
            $matched_score += $score;
        }

        $context->add_hit({
            action  => $rule->{action} // 'score',
            rule_id => $rule->{id},
            score   => $matched_score,
            target  => join(',', grep {
                ($_ eq 'subject' && $subject_matched)
                || ($_ eq 'body' && $body_matched)
            } qw(subject body)),
        });

        $context->{force_save} = 1 if $rule->{save_article};

        if ($rule->{log_match} // 1) {
            $context->{logger}->rules(
                'badword_rule_matched',
                rule_id => $rule->{id},
                score   => $matched_score,
                target  => join(',', grep {
                    ($_ eq 'subject' && $subject_matched)
                    || ($_ eq 'body' && $body_matched)
                } qw(subject body)),
            );
        }

        if (($rule->{action} // 'score') eq 'reject') {
            my $legacy_code = $subject_matched ? 28 : 29;
            return _rule_rejection($rule, $legacy_code);
        }

        last if $rule->{stop_on_match};
    }

    my $maximum_subject_score =
        $config->{badwords}{max_subject_score}
        // 0;
    my $maximum_body_score =
        $config->{badwords}{max_body_score}
        // 0;

    return _reject(28, score => $subject_score)
        if $subject_score > $maximum_subject_score;

    return _reject(29, score => $body_score)
        if $body_score > $maximum_body_score;

    return Postfilter::Result->pass(
        body_score    => $body_score,
        code          => 'PF-RULE-000',
        legacy        => 0,
        message       => 'Badword checks passed',
        subject_score => $subject_score,
    );
}


=head2 _build_matcher($rule, $pattern)

Returns a closure implementing exact, contains or regex matching.  Exact and
contains rules avoid unnecessary regular-expression complexity and make common
operator intentions unambiguous.

=cut

# Function: _build_matcher
# Purpose: Compiles exact, contains, or regex matching once for a badword rule evaluation.
# Parameters: $rule, $pattern
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _build_matcher {
    my ($rule, $pattern) = @_;

    my $match_type = $rule->{match_type} // 'regex';
    my $case_sensitive = $rule->{case_sensitive} ? 1 : 0;

    if ($match_type eq 'exact') {
        return $case_sensitive
            ? sub { $_[0] eq $pattern }
            : sub { lc($_[0]) eq lc($pattern) };
    }

    if ($match_type eq 'contains') {
        return $case_sensitive
            ? sub { index($_[0], $pattern) >= 0 }
            : sub { index(lc($_[0]), lc($pattern)) >= 0 };
    }

    my $regular_expression = eval {
        $case_sensitive ? qr/$pattern/ : qr/$pattern/i;
    };
    return unless $regular_expression;

    return sub { $_[0] =~ $regular_expression ? 1 : 0 };
}

# Function: _rule_rejection
# Purpose: Builds a badword-specific rejection using rule overrides or default code/message.
# Parameters: $rule, $default_legacy_code
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _rule_rejection {
    my ($rule, $default_legacy_code) = @_;

    my ($default_code, $default_message) =
        Postfilter::Codes->lookup($default_legacy_code);

    return Postfilter::Result->reject(
        code    => $rule->{reason_code} // $default_code,
        legacy  => defined $rule->{legacy_code}
            ? $rule->{legacy_code}
            : $default_legacy_code,
        message => $rule->{response} // $default_message,
        rule_id => $rule->{id},
    );
}

# Function: _reject
# Purpose: Constructs a rejection result while preserving the historical numeric compatibility
#          code.
# Parameters: $legacy_code, %details
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
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
