package Postfilter::Logger;

use strict;
use warnings;

=head1 NAME

Postfilter::Logger - Structured syslog output with nine verbosity levels.

=head1 DESCRIPTION

INN filters should use C<INN::syslog> instead of opening log files directly.
This class provides one place for severity mapping, newline sanitisation and the
verbosity policy agreed for Postfilter-NG:

  1  final article result
  2  posting identity and group summary
  3  pipeline/profile decisions
  4  structural checks
  5  header transformations
  6  SQLite and rate-limit activity
  7  DNS reputation activity
  8  rule matches and scoring
  9  detailed trace and timings

Warnings and errors are never hidden by the configured verbosity.

=cut

# Function: new
# Purpose: Constructs a logger with prefix, verbosity, and optional stderr fallback.
# Parameters: $class, %arguments
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub new {
    my ($class, %arguments) = @_;

    return bless {
        verbosity => $arguments{verbosity} // 3,
        include_rule_ids => exists $arguments{include_rule_ids}
            ? $arguments{include_rule_ids}
            : 1,
        include_timing => exists $arguments{include_timing}
            ? $arguments{include_timing}
            : 1,
        prefix    => $arguments{prefix}    // 'postfilter-ng',
        stderr    => $arguments{stderr}    // 0,
    }, $class;
}

# Function: verbosity
# Purpose: Returns the current cumulative logging verbosity.
# Parameters: $self, $verbosity
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub verbosity {
    return $_[0]->{verbosity};
}

# Function: set_verbosity
# Purpose: Changes the process-local logging verbosity after a validated configuration reload.
# Parameters: $self, $verbosity
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub set_verbosity {
    my ($self, $verbosity) = @_;
    $self->{verbosity} = $verbosity;
    return;
}

# Function: set_options
# Purpose: Applies validated logging presentation flags after a configuration
#          load or reload without replacing the process-local logger object.
# Parameters: $self, $logging_config
# Operational notes: Only formatting/field-selection settings are changed;
#                    severity and fail-safe error visibility remain fixed.
sub set_options {
    my ($self, $logging_config) = @_;

    $logging_config ||= {};
    $self->{include_rule_ids} = $logging_config->{include_rule_ids} ? 1 : 0;
    $self->{include_timing} = $logging_config->{include_timing} ? 1 : 0;
    return;
}

=head2 event($severity, $required_verbosity, $message, %fields)

Emits one structured line.  Field values are quoted and control characters are
replaced with spaces to prevent an article header from injecting fake log lines.
When the module is used outside INN, C<POSTFILTER_STDERR=1> or the constructor's
C<stderr> flag sends the same line to standard error.

=cut

# Function: event
# Purpose: Formats one structured log line, sanitises untrusted fields, and writes through INN
#          syslog or stderr.
# Parameters: $self, $severity, $required_verbosity, $message, %fields
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub event {
    my ($self, $severity, $required_verbosity, $message, %fields) = @_;

    my $always_visible = $severity =~ /^(?:warning|err|crit|alert)$/;
    return
        if !$always_visible
        && $required_verbosity > $self->{verbosity};

    my @pairs;
    for my $key (sort keys %fields) {
        next unless defined $fields{$key};
        next if !$self->{include_rule_ids} && $key eq 'rule_id';
        next if !$self->{include_timing}
            && $key =~ /(?:elapsed|duration|latency|timing|_ms$)/;

        my $value = $fields{$key};
        if (!ref $value) {
            $value =~ s/[\r\n\t]+/ /g;
            $value =~ s/([\\"])/\\$1/g;
        }

        push @pairs, qq{$key="$value"};
    }

    my $line = join ' ', $self->{prefix}, $message, @pairs;

    if (defined &INN::syslog) {
        my %inn_severity = (
            alert   => 'alert',
            crit    => 'crit',
            debug   => 'debug',
            err     => 'err',
            info    => 'info',
            notice  => 'notice',
            warning => 'warning',
        );
        INN::syslog($inn_severity{$severity} // 'notice', $line);
        return;
    }

    if ($self->{stderr} || $ENV{POSTFILTER_STDERR}) {
        print STDERR scalar(localtime) . " [$severity] $line\n";
    }

    return;
}

# Function: fatal
# Purpose: Writes an unconditional critical-severity event.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub fatal {
    my ($self, $message, %fields) = @_;
    return $self->event('crit', 1, $message, %fields);
}
# Function: error
# Purpose: Creates an internal-error result for callers that need to distinguish failure from
#          policy rejection.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub error {
    my ($self, $message, %fields) = @_;
    return $self->event('err', 1, $message, %fields);
}
# Function: warning
# Purpose: Writes an unconditional warning-severity event.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub warning {
    my ($self, $message, %fields) = @_;
    return $self->event('warning', 1, $message, %fields);
}
# Function: result
# Purpose: Implements the module-specific result operation.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub result {
    my ($self, $message, %fields) = @_;
    return $self->event('notice', 1, $message, %fields);
}
# Function: identity
# Purpose: Writes level-2 posting identity information.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub identity {
    my ($self, $message, %fields) = @_;
    return $self->event('info', 2, $message, %fields);
}
# Function: pipeline
# Purpose: Writes level-3 pipeline and trusted-profile decisions.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub pipeline {
    my ($self, $message, %fields) = @_;
    return $self->event('info', 3, $message, %fields);
}
# Function: structural
# Purpose: Writes level-4 structural-check diagnostics.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub structural {
    my ($self, $message, %fields) = @_;
    return $self->event('debug', 4, $message, %fields);
}
# Function: headers
# Purpose: Writes level-5 header-transformation diagnostics.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub headers {
    my ($self, $message, %fields) = @_;
    return $self->event('debug', 5, $message, %fields);
}
# Function: database
# Purpose: Writes level-6 SQLite and rate-limit diagnostics.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub database {
    my ($self, $message, %fields) = @_;
    return $self->event('debug', 6, $message, %fields);
}
# Function: reputation
# Purpose: Writes level-7 DNS reputation diagnostics.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub reputation {
    my ($self, $message, %fields) = @_;
    return $self->event('debug', 7, $message, %fields);
}
# Function: rules
# Purpose: Writes level-8 rule and scoring diagnostics.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub rules {
    my ($self, $message, %fields) = @_;
    return $self->event('debug', 8, $message, %fields);
}
# Function: trace
# Purpose: Writes level-9 detailed execution timing and trace data.
# Parameters: $s, $m, %f
# Operational notes: Output is routed through INN::syslog when available; control characters are
#                    sanitised centrally.
sub trace {
    my ($self, $message, %fields) = @_;
    return $self->event('debug', 9, $message, %fields);
}

1;
