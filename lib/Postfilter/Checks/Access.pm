package Postfilter::Checks::Access;

use strict;
use warnings;

=head1 NAME

Postfilter::Checks::Access - SQLite-backed rate limits and multipost detection.

=head1 IDENTITY MODEL

An empty nnrpd username is always public. A non-empty username is authenticated
unless it appears in C<access.public_user_ids> or matches the optional
C<access.public_user_pattern>.

Public sessions are checked by source IP and, optionally, registered domain.
Authenticated sessions are checked by user id.  C<server_type> can force a pure
public or pure authenticated deployment.

=head1 MULTIPOST LIMITS

C<limits.default_multipost_limit> supplies the profile default and may be raised
or lowered by a matching access profile. C<limits.absolute_multipost_limit> is a
hard ceiling enforced after the effective profile limit is resolved.

=cut

use Postfilter::Codes;
use Postfilter::Result;
use Postfilter::Util qw(ip_in_cidr);

my %REJECTION_CODE = (
    IP => {
        max_articles          => 31,
        max_short_articles    => 70,
        max_total_errors      => 64,
        max_short_errors      => 67,
        max_short_size        => 73,
        max_total_size        => 76,
        max_short_groups      => 79,
        max_total_groups      => 82,
        max_short_followups   => 85,
        max_total_followups   => 88,
    },
    DN => {
        max_articles          => 32,
        max_short_articles    => 71,
        max_total_errors      => 65,
        max_short_errors      => 68,
        max_short_size        => 74,
        max_total_size        => 77,
        max_short_groups      => 80,
        max_total_groups      => 83,
        max_short_followups   => 86,
        max_total_followups   => 89,
    },
    ID => {
        max_articles          => 33,
        max_short_articles    => 72,
        max_total_errors      => 66,
        max_short_errors      => 69,
        max_short_size        => 75,
        max_total_size        => 78,
        max_short_groups      => 81,
        max_total_groups      => 84,
        max_short_followups   => 87,
        max_total_followups   => 90,
    },
);

# Function: run
# Purpose: Applies SQLite-backed multipost and rate limits to the article’s resolved identities.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub run {
    my ($class, $context) = @_;

    unless ($context->{config}{modules}{access}) {
        return Postfilter::Result->pass(
            code    => 'PF-RATE-000',
            legacy  => 0,
            message => 'Access checks disabled',
        );
    }

    my $database = $context->{db};
    unless ($database && $database->available) {
        return Postfilter::Result->pass(
            code    => 'PF-RATE-000',
            legacy  => 0,
            message => 'Access database unavailable; fail-open',
        );
    }

    my @identities = _identities_for_article($context);

    my $multipost_count;
    my $multipost_ok = eval {
        $multipost_count = $database->multipost_count($context);
        1;
    };
    if (!$multipost_ok) {
        return _database_failure_result($context, $@);
    }

    my $absolute_limit =
        $context->limit('absolute_multipost_limit')
        // 0;
    if ($absolute_limit > 0 && $multipost_count >= $absolute_limit) {
        return _reject(
            30,
            absolute_limit => $absolute_limit,
            count          => $multipost_count,
        );
    }

    for my $identity (@identities) {
        my ($identity_type, $identity_value) = @{$identity};
        next unless defined $identity_value && length $identity_value;

        my $profile = _profile_for_identity(
            $context,
            $identity_type,
            $identity_value,
        );

        my $snapshot;
        my $snapshot_ok = eval {
            $snapshot = $database->rate_snapshot(
                $context,
                $identity_type,
                $identity_value,
            );
            1;
        };
        if (!$snapshot_ok) {
            my $result = _database_failure_result($context, $@);
            return $result unless $result->is_pass;
            next;
        }

        my $default_multipost_limit =
            $context->limit('default_multipost_limit')
            // 2;
        my $profile_multipost_limit =
            exists $profile->{multipost}
            ? $profile->{multipost}
            : $default_multipost_limit;

        if (
            $profile_multipost_limit > 0
            && $multipost_count >= $profile_multipost_limit
        ) {
            return _reject(
                30,
                count         => $multipost_count,
                identity_type => $identity_type,
                limit         => $profile_multipost_limit,
            );
        }

        for my $metric (qw(
            max_articles
            max_short_articles
            max_total_errors
            max_short_errors
            max_short_size
            max_total_size
            max_short_groups
            max_total_groups
            max_short_followups
            max_total_followups
        )) {
            next unless exists $profile->{$metric};

            my $current = $snapshot->{$metric} // 0;
            my $prospective = $current + _current_article_increment(
                $context,
                $metric,
            );

            next if $prospective <= $profile->{$metric};

            return _reject(
                $REJECTION_CODE{$identity_type}{$metric},
                current       => $current,
                identity_type => $identity_type,
                limit         => $profile->{$metric},
                metric        => $metric,
                prospective   => $prospective,
            );
        }
    }

    return Postfilter::Result->pass(
        code    => 'PF-RATE-000',
        legacy  => 0,
        message => 'Access checks passed',
    );
}

# Function: _identities_for_article
# Purpose: Selects IP/domain or authenticated-user identities according to server type and public-
#          user rules.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _identities_for_article {
    my ($context) = @_;

    my $server_type = $context->{config}{access}{server_type} // 'both';
    my $public = $context->is_public_user;

    if ($server_type eq 'auth') {
        return (['ID', $context->{user}]);
    }

    if ($server_type eq 'both' && !$public) {
        return (['ID', $context->{user}]);
    }

    my @identities = (['IP', $context->{client_ip}]);
    if ($context->{config}{access}{enable_domain_check}) {
        push @identities, ['DN', $context->{client_domain}];
    }

    return @identities;
}

=head2 _profile_for_identity($context, $type, $value)

Returns the highest-priority matching profile, or the configured defaults for
that identity type.  CIDR matching is meaningful only for IP profiles; exact and
regex matching are available for every type.

=cut

# Function: _profile_for_identity
# Purpose: Returns the highest-priority matching access profile or the appropriate default limits.
# Parameters: $context, $identity_type, $identity_value
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _profile_for_identity {
    my ($context, $identity_type, $identity_value) = @_;

    my @profiles = sort {
        ($b->{priority} // 0) <=> ($a->{priority} // 0)
    } grep {
        ref($_) eq 'HASH'
        && ($_->{enabled} // 1)
        && ($_->{identity_type} // '') eq $identity_type
    } @{ $context->{config}{access_profile} // [] };

    for my $profile (@profiles) {
        next unless $context->rule_applies_to_article_type($profile);
        my $match_type = $profile->{match_type} // 'regex';
        my $pattern = $profile->{pattern} // '.*';
        my $matches = 0;

        if ($match_type eq 'exact') {
            $matches = $identity_value eq $pattern;
        }
        elsif ($match_type eq 'cidr') {
            $matches = ip_in_cidr($identity_value, $pattern);
        }
        else {
            $matches = eval { $identity_value =~ /$pattern/i } ? 1 : 0;
        }

        return $profile->{limits} // $profile if $matches;
    }

    return $context->{config}{access}{authenticated_limits} // {}
        if $identity_type eq 'ID';
    return $context->{config}{access}{domain_limits} // {}
        if $identity_type eq 'DN';
    return $context->{config}{access}{public_limits} // {};
}

# Function: _current_article_increment
# Purpose: Calculates how the pending article contributes to each prospective rate metric.
# Parameters: $context, $metric
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _current_article_increment {
    my ($context, $metric) = @_;

    return 1 if $metric =~ /articles/;

    # The current article has not yet received a final technical verdict, so
    # error counters describe only previous rejected attempts.  The final event
    # is recorded after the pipeline and affects the next POST in the session.
    return 0 if $metric =~ /errors/;

    return $context->{total_size}      if $metric =~ /size/;
    return $context->{group_count}     if $metric =~ /groups/;
    return $context->{followup_count}  if $metric =~ /followups/;
    return 0;
}

# Function: _database_failure_result
# Purpose: Translates an access-query SQLite failure into configured fail-open or historical-code
#          rejection.
# Parameters: $context, $error
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _database_failure_result {
    my ($context, $error) = @_;

    my $action = $context->{db}->handle_failure($error);
    return _reject(40) if $action eq 'reject';

    return Postfilter::Result->pass(
        code    => 'PF-RATE-000',
        legacy  => 0,
        message => 'Access checks skipped after SQLite failure',
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
