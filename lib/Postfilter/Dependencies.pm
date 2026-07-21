package Postfilter::Dependencies;

use strict;
use warnings;

=head1 NAME

Postfilter::Dependencies - Runtime capability checks and safe degradation.

=head1 DESCRIPTION

The installer refuses to activate an incomplete installation, but packages can
be removed later or a manual deployment can omit a module.  Postfilter-NG must
not misreport a missing server dependency as a malformed article.

This module checks capabilities once when an engine is created.  Features that
can be safely disabled are disabled in the process-local configuration and an
explicit C<news.err> message is emitted.  Fundamental failures such as an
unavailable configuration parser are handled by Postfilter::Config through the
last-known-good JSON fallback.

=cut

# Function: apply_runtime_capabilities
# Purpose: Checks runtime module availability and disables only features whose configured failure
#          policy allows degradation.
# Parameters: $class, $config, $logger
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub apply_runtime_capabilities {
    my ($class, $config, $logger) = @_;

    my @disabled;

    if ($config->{modules}{dates} && !_can_load('Date::Parse')) {
        $config->{modules}{dates} = 0;
        push @disabled, 'dates';
        _log_missing(
            $logger,
            module  => 'Date::Parse',
            feature => 'date validation',
            action  => 'disabled dates module',
        );
    }

    my $dns_required =
        $config->{modules}{rbl}
        || $config->{modules}{uribl}
        || $config->{modules}{surbl}
        || $config->{modules}{tor};

    if ($dns_required && !_can_load('Net::DNS')) {
        for my $module (qw(rbl uribl surbl tor)) {
            $config->{modules}{$module} = 0;
        }
        push @disabled, qw(rbl uribl surbl tor);
        _log_missing(
            $logger,
            module  => 'Net::DNS',
            feature => 'DNS reputation checks',
            action  => 'disabled RBL, URIBL, SURBL and TOR DNS checks',
        );
    }

    if ($config->{database}{enabled}) {
        my @database_modules = grep { !_can_load($_) } qw(DBI DBD::SQLite);
        if (@database_modules) {
            my $failure_action = $config->{database}{on_failure} // 'accept';
            if ($failure_action ne 'reject') {
                $config->{database}{enabled} = 0;
                push @disabled, 'database';
            }
            _log_missing(
                $logger,
                module  => join(', ', @database_modules),
                feature => 'SQLite persistence and rate limits',
                action  => $failure_action eq 'reject'
                    ? 'database remains mandatory; articles will be rejected'
                    : 'disabled database-backed features for this nnrpd process',
            );
        }
    }

    my $encryption_requested =
        ($config->{tor}{header}{mode} // '') eq 'encrypted'
        || ($config->{html_report}{privacy}{identity_mode} // '') eq 'encrypted'
        || ($config->{database}{privacy}{identity_mode} // '') eq 'encrypted';

    if ($encryption_requested && !_can_load('Crypt::Mode::CBC')) {
        # Reversible encryption is not silently replaced by a known or weak
        # mechanism.  Each consumer applies its documented safe fallback:
        # TOR headers become "yes", reports fail to generate, and database
        # identity protection falls back according to database.on_failure.
        _log_missing(
            $logger,
            module  => 'Crypt::Mode::CBC',
            feature => 'reversible encryption',
            action  => 'encrypted operations will report an explicit error',
        );
    }

    return \@disabled;
}

# Function: _can_load
# Purpose: Tests whether a Perl module can be required without terminating the filter.
# Parameters: $module
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _can_load {
    my ($module) = @_;
    return eval "require $module; 1" ? 1 : 0; ## no critic (ProhibitStringyEval)
}

# Function: _log_missing
# Purpose: Writes a clear dependency diagnostic including affected feature and chosen degradation.
# Parameters: $logger, %fields
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _log_missing {
    my ($logger, %fields) = @_;
    return unless $logger;

    $logger->error(
        'runtime_dependency_missing',
        %fields,
    );

    return;
}

1;
