package Postfilter::NG;

use strict;
use warnings;

=head1 NAME

Postfilter::NG - Orchestrator for the INN nnrpd posting filter.

=head1 PROCESS MODEL

INN loads C<filter_nnrpd.pl> once for each nnrpd process.  One process can handle
multiple POST commands during a client session, so the engine, database handle,
DNS resolver and immutable configuration are reused, while a fresh
Postfilter::Context is created for every article.

=head1 PIPELINE

  server policy
  trusted profile
  structural checks
  binary-content checks
  per-group sender database
  TOR
  IP DNSBL
  URI DNS lists
  ban rules
  badword rules
  rate limits and multipost
  custom local filter
  header transformations
  policy resolution
  optional article save
  one SQLite event
  one final syslog line

Audit mode records the first technical rejection but returns success to the
client.  C<server_status = "closed"> remains enforced even in audit mode.

=cut

use Digest::SHA qw(sha256_hex);
use Time::HiRes qw(time);

use Postfilter::Checks::Access;
use Postfilter::Checks::Attachments;
use Postfilter::Checks::Content;
use Postfilter::Checks::Reputation;
use Postfilter::Checks::Rules;
use Postfilter::Checks::Style;
use Postfilter::Checks::UserDB;
use Postfilter::Codes;
use Postfilter::Config;
use Postfilter::Context;
use Postfilter::Crypto;
use Postfilter::Database;
use Postfilter::Dependencies;
use Postfilter::HeaderTransform;
use Postfilter::Logger;
use Postfilter::PublicSuffix;
use Postfilter::Result;
use Postfilter::SavedArticle;

our $VERSION = '2026.07.5-rc3';

# Function: new
# Purpose: Constructs one reusable per-nnrpd engine, loads configuration, dependencies, SQLite,
#          and suffix data.
# Parameters: $class, %arguments
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub new {
    my ($class, %arguments) = @_;

    my $logger = Postfilter::Logger->new(
        stderr    => $arguments{stderr} // 0,
        verbosity => $arguments{verbosity} // 3,
    );

    my $source =
        $arguments{config}
        // $ENV{POSTFILTER_CONFIG}
        // '/etc/news/postfilter-ng/postfilter.toml';
    my $state_directory =
        $arguments{state_dir}
        // $ENV{POSTFILTER_STATE_DIR}
        // '/var/lib/news/postfilter-ng';

    my $loader = Postfilter::Config->new(
        logger    => $logger,
        source    => $source,
        state_dir => $state_directory,
    );

    my ($config) = $loader->load;
    Postfilter::Dependencies->apply_runtime_capabilities($config, $logger);

    my $crypto = Postfilter::Crypto->new(logger => $logger);
    my $database = Postfilter::Database->new(
        config => $config,
        crypto => $crypto,
        logger => $logger,
    );
    my $suffixes = Postfilter::PublicSuffix->load(
        $config->{paths}{public_suffix_file},
        $logger,
    );

    if ($config->{database}{enabled}) {
        my $connected = eval {
            $database->connect;
            1;
        };
        if (!$connected) {
            my $action = $database->handle_failure($@);
            $logger->warning(
                'database_startup_degraded',
                action => $action,
            );
        }
    }

    return bless {
        config     => $config,
        crypto     => $crypto,
        database   => $database,
        loader     => $loader,
        logger     => $logger,
        source     => $source,
        state_dir  => $state_directory,
        suffixes   => $suffixes,

        # The custom module is a local extension point outside TOML.  Keep the
        # last successfully loaded coderef so a malformed edit cannot remove a
        # working rule set from an already-running nnrpd process.
        custom_filter_coderef => undef,
        custom_filter_mtime   => undef,
        custom_filter_path    => undef,
    }, $class;
}

=head2 process_article(%arguments)

Processes one article.  The method catches unexpected exceptions at the outer
boundary so an optional module cannot terminate the nnrpd process.  Expected
check failures are ordinary Postfilter::Result objects and never use exceptions
as control flow.

=cut

# Function: process_article
# Purpose: Coordinates configuration reload, filtering, policy resolution, persistence, logging,
#          and the INN reply.
# Parameters: $self, %arguments
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub process_article {
    my ($self, %arguments) = @_;

    my $article_started_at = time;
    my $configuration_started_at = time;
    my ($candidate_config) = eval { $self->{loader}->maybe_reload };
    if ($@) {
        $self->{logger}->error(
            'configuration_reload_exception',
            error => $@,
        );
        $candidate_config = $self->{config};
    }

    $self->{logger}->trace(
        'phase_completed',
        elapsed_ms => sprintf(
            '%.3f',
            (time - $configuration_started_at) * 1_000,
        ),
        phase => 'configuration',
    );

    if (_generation_changed($self->{config}, $candidate_config)) {
        Postfilter::Dependencies->apply_runtime_capabilities(
            $candidate_config,
            $self->{logger},
        );
        $self->{config} = $candidate_config;
        $self->{database}->update_config($candidate_config);
        $self->{suffixes} = Postfilter::PublicSuffix->load(
            $candidate_config->{paths}{public_suffix_file},
            $self->{logger},
        );
    }

    my $context_started_at = time;
    my $context = Postfilter::Context->new(
        attributes => $arguments{attributes},
        body       => $arguments{body},
        config     => $self->{config},
        crypto     => $self->{crypto},
        db         => $self->{database},
        headers    => $arguments{headers},
        logger     => $self->{logger},
        processing_start => $article_started_at,
        suffixes   => $self->{suffixes},
        user       => $arguments{user},
    );
    $context->{message_id_hash} = substr(
        sha256_hex($context->{message_id} // ''),
        0,
        24,
    );

    $self->{logger}->trace(
        'phase_completed',
        elapsed_ms => sprintf(
            '%.3f',
            (time - $context_started_at) * 1_000,
        ),
        phase => 'context',
    );

    $self->{logger}->identity(
        'article_identity',
        article_type => $context->{article_type},
        groups     => $context->{group_count},
        ip         => $context->{client_ip},
        message_id => $context->{message_id},
        user       => $context->{user},
    );

    my $result;
    my $pipeline_started_at = time;
    my $pipeline_completed = eval {
        $result = $self->_run_pipeline($context);
        1;
    };
    my $pipeline_elapsed_ms = (time - $pipeline_started_at) * 1_000;
    $self->{logger}->trace(
        'phase_completed',
        elapsed_ms => sprintf('%.3f', $pipeline_elapsed_ms),
        phase      => 'pipeline',
    );

    if (!$pipeline_completed) {
        my $error = $@ || 'unknown internal exception';
        $self->{logger}->error(
            'article_processing_exception',
            error      => $error,
            message_id => $context->{message_id},
        );
        push @{ $context->{notes} }, "internal_exception=$error";

        my $emergency_action =
            $context->{config}{resilience}{emergency_action}
            // 'accept';
        $result = $emergency_action eq 'reject'
            ? Postfilter::Result->reject(
                code    => 'PF-INTERNAL-999',
                legacy  => 55,
                message => 'Internal filter failure',
            )
            : Postfilter::Result->pass(
                code    => 'PF-INTERNAL-998',
                legacy  => 0,
                message => 'Internal filter failure; emergency fail-open',
            );
    }

    my $finalization_started_at = time;
    my $final = $self->_resolve_policy($context, $result);

    my $saved_article;

    if ($final->{save}) {
        my $saved = eval {
            $saved_article = Postfilter::SavedArticle->save($context, $result);
            1;
        };

        if (!$saved) {
            $self->{logger}->error(
                'save_article_failed',
                error      => $@,
                message_id => $context->{message_id},
            );

            if (
                ($context->{config}{saved_articles}{on_failure} // 'continue')
                eq 'reject'
            ) {
                $result = _create_rejection_result(41);
                $final = $self->_resolve_policy($context, $result);
            }
        }
    }

    # Distribution: local creates persistent reply-inheritance state only for
    # an article that will actually be accepted by nnrpd.  Writing it during
    # header transformation would leave false state behind when a later policy
    # step rejects or discards the article.
    my $local_distribution_stored = 0;
    if (
        $final->{nntp_result} eq 'accepted'
        && $context->{local_distribution_to_store}
        && $context->{config}{database}{enabled}
        && $self->{database}->available
    ) {
        my $stored = eval {
            $self->{database}->local_distribution_add(
                $context->{local_distribution_to_store},
                $context->{received_at},
            );
            1;
        };

        if ($stored) {
            $local_distribution_stored = 1;
        }
        else {
            my $failure_action = $self->{database}->handle_failure($@);
            push @{ $context->{notes} },
                'local_distribution_store_failed=' . ($@ || 'unknown error');

            if ($failure_action eq 'reject') {
                $result = _create_rejection_result(107);
                $final = $self->_resolve_policy($context, $result);
            }
        }
    }

    my $event_id;
    if ($context->{config}{database}{enabled}) {
        my $database_started_at = time;
        my $recorded = eval {
            $event_id = $self->{database}->record_event(
                $context,
                $result,
                $final,
            );
            1;
        };
        $self->{logger}->trace(
            'phase_completed',
            elapsed_ms => sprintf(
                '%.3f',
                (time - $database_started_at) * 1_000,
            ),
            phase => 'database_event',
        );

        if (!$recorded) {
            my $failure_action = $self->{database}->handle_failure($@);
            if ($failure_action eq 'reject') {
                if ($local_distribution_stored) {
                    my $removed = eval {
                        $self->{database}->local_distribution_remove(
                            $context->{local_distribution_to_store},
                        );
                        1;
                    };
                    $self->{logger}->error(
                        'local_distribution_rollback_failed',
                        error => $@,
                    ) unless $removed;
                }

                $result = Postfilter::Result->reject(
                    code    => 'PF-DB-040',
                    legacy  => 40,
                    message => 'Persistent audit database unavailable',
                );
                $final = {
                    action       => 'reject',
                    audit_mode   => 0,
                    nntp_result  => 'rejected',
                    save         => 0,
                    would_reject => 1,
                };
            }
        }

        if ($saved_article && $event_id) {
            my $linked = eval {
                $self->{database}->saved_article_add(
                    event_id => $event_id,
                    %{$saved_article},
                );
                1;
            };
            $self->{logger}->error(
                'saved_article_db_record_failed',
                error => $@,
            ) unless $linked;
        }
    }

    my $finalization_elapsed_ms =
        (time - $finalization_started_at) * 1_000;
    $self->{logger}->trace(
        'phase_completed',
        elapsed_ms => sprintf('%.3f', $finalization_elapsed_ms),
        phase      => 'finalization',
    );

    my $log_final_result = $final->{nntp_result} eq 'accepted'
        ? ($context->{config}{logging}{log_accepted} // 1)
        : ($context->{config}{logging}{log_rejected} // 1);

    if ($log_final_result) {
        $self->{logger}->result(
            'article_result',
            action      => $final->{action},
            article_type => $context->{article_type},
            audit       => $final->{audit_mode} ? 1 : 0,
            elapsed_ms  => sprintf('%.3f', $context->elapsed_ms),
            groups      => $context->{group_count},
            ip          => $context->{client_ip},
            finalization_ms => sprintf('%.3f', $finalization_elapsed_ms),
            legacy      => $result->{legacy},
            message_id  => $context->{message_id},
            pipeline_ms => sprintf('%.3f', $pipeline_elapsed_ms),
            reason      => $result->{code},
            result      => $final->{nntp_result},
            saved       => $context->{saved_path} // '',
            technical   => $result->{verdict},
            user        => $context->{user},
        );
    }

    return $self->_inn_response($context, $result, $final);
}

# Function: _run_pipeline
# Purpose: Runs ordered checks, honours trusted skips/audit/deadlines, and returns the first
#          technical failure.
# Parameters: $self, $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _run_pipeline {
    my ($self, $context) = @_;

    my $config = $context->{config};

    return _create_rejection_result(48)
        if $config->{policy}{server_status} eq 'closed';

    if ($config->{policy}{server_status} eq 'disabled') {
        return Postfilter::Result->pass(
            code    => 'PF-POLICY-000',
            legacy  => 0,
            message => 'Filter disabled by configuration',
        );
    }

    # Mixed crossposts are rejected before trusted-profile processing.  A text
    # group must never inherit binary limits or binary payload permissions merely
    # because one alt.binaries.* group was added to Newsgroups.
    my $mixed_crosspost_policy =
        $config->{article_types}{mixed_crosspost_policy}
        // 'reject';

    return _create_rejection_result(95)
        if $context->{classification_mixed}
        && $mixed_crosspost_policy eq 'reject';

    my $trusted_profile_started_at = time;
    Postfilter::Checks::Rules->apply_trusted_profile($context);
    $self->{logger}->trace(
        'phase_completed',
        elapsed_ms => sprintf(
            '%.3f',
            (time - $trusted_profile_started_at) * 1_000,
        ),
        phase => 'trusted_profile',
    );

    if ($context->{trusted_profile}{full_bypass}) {
        return Postfilter::Result->pass(
            code    => 'PF-TRUST-001',
            legacy  => 0,
            message => 'Full trusted-profile bypass',
        );
    }

    $context->start_processing_budget;

    my @steps = (
        ['style',      sub { Postfilter::Checks::Style->run($context) }],
        ['attachments', sub { Postfilter::Checks::Attachments->run($context) }],
        ['binary',     sub { Postfilter::Checks::Content->run_binary($context) }],
        ['userdb',     sub { Postfilter::Checks::UserDB->run($context) }],
        ['tor',        sub { Postfilter::Checks::Reputation->run_tor($context) }],
        ['rbl',        sub { Postfilter::Checks::Reputation->run_rbl($context) }],
        ['uribl',      sub { Postfilter::Checks::Reputation->run_uri_lists($context) }],
        ['banlist',    sub { Postfilter::Checks::Rules->run_banlist($context) }],
        ['badwords',   sub { Postfilter::Checks::Content->run_badwords($context) }],
        ['rate_limit', sub { Postfilter::Checks::Access->run($context) }],
        ['custom',     sub { $self->_run_custom_filter($context) }],
    );

    my $first_rejection;

    for my $step (@steps) {
        my ($name, $code) = @{$step};

        if ($context->deadline_exceeded) {
            my $timeout_result = $self->_processing_timeout_result($context, $name);
            return $timeout_result unless $config->{policy}{mode} eq 'audit';
            $first_rejection //= $timeout_result unless $timeout_result->is_pass;
            last;
        }

        if ($context->skip($name)) {
            $self->{logger}->pipeline(
                'check_skipped',
                check   => $name,
                profile => $context->{trusted_profile}{id} // '',
            );
            next;
        }

        my $started_at = time;
        my $step_result = $code->();
        $self->{logger}->trace(
            'check_completed',
            check      => $name,
            elapsed_ms => sprintf('%.3f', (time - $started_at) * 1_000),
            verdict    => $step_result->{verdict},
        );

        next if $step_result->is_pass;

        return $step_result unless $config->{policy}{mode} eq 'audit';
        $first_rejection //= $step_result;
    }

    if ($context->deadline_exceeded) {
        my $timeout_result = $self->_processing_timeout_result(
            $context,
            'headers',
        );
        return $timeout_result unless $config->{policy}{mode} eq 'audit';
        $first_rejection //= $timeout_result unless $timeout_result->is_pass;
    }

    if ($config->{modules}{headers} && !$context->skip('headers')) {
        my $headers_started_at = time;
        my $transformation = Postfilter::HeaderTransform->apply($context);
        $self->{logger}->trace(
            'phase_completed',
            elapsed_ms => sprintf(
                '%.3f',
                (time - $headers_started_at) * 1_000,
            ),
            phase => 'headers',
        );
        if (!$transformation->is_pass) {
            return $transformation unless $config->{policy}{mode} eq 'audit';
            $first_rejection //= $transformation;
        }
    }

    if (!$first_rejection && $context->deadline_exceeded) {
        my $timeout_result = $self->_processing_timeout_result(
            $context,
            'complete',
        );
        return $timeout_result unless $config->{policy}{mode} eq 'audit';
        $first_rejection //= $timeout_result unless $timeout_result->is_pass;
    }

    return $first_rejection if $first_rejection;

    return Postfilter::Result->pass(
        code    => 'PF-ACCEPT-000',
        legacy  => 0,
        message => 'Article accepted by all checks',
    );
}

=head2 _run_custom_filter($context)

Loads the administrator's custom module and applies C<custom.on_error> to a
missing file, load failure or runtime exception.

=cut

# Function: _run_custom_filter
# Purpose: Executes the last successfully loaded local custom rule function and normalises its
#          return value.
# Parameters: $self, $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _run_custom_filter {
    my ($self, $context) = @_;

    unless ($context->{config}{modules}{custom}) {
        return Postfilter::Result->pass(
            code    => 'PF-RULE-000',
            legacy  => 0,
            message => 'Custom filter disabled',
        );
    }

    my $file = $context->{config}{custom}{module_file} // '';
    my $custom_filter = $self->_load_custom_filter($context, $file);

    unless ($custom_filter) {
        return $self->_custom_error_result(
            $context,
            "Custom module '$file' has never loaded successfully",
        );
    }

    my $custom_result = eval {
        $custom_filter->($context);
    };
    if ($@) {
        return $self->_custom_error_result($context, $@);
    }

    if (!defined $custom_result || $custom_result eq '' || $custom_result eq '0') {
        return Postfilter::Result->pass(
            code    => 'PF-RULE-000',
            legacy  => 0,
            message => 'Custom filter passed',
        );
    }

    if (ref($custom_result) eq 'Postfilter::Result') {
        return $custom_result;
    }

    if ($custom_result =~ /^\d+$/) {
        return _create_rejection_result(0 + $custom_result);
    }

    return Postfilter::Result->reject(
        code    => 'PF-RULE-063',
        legacy  => 63,
        message => "Custom rule rejected article: $custom_result",
    );
}

# Function: _load_custom_filter
# Purpose: Reloads a changed custom module only after success and retains the previous working
#          coderef on error.
# Parameters: $self, $context, $file
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _load_custom_filter {
    my ($self, $context, $file) = @_;

    my $cached_filter = $self->{custom_filter_coderef};

    if (!$file || !-r $file) {
        $self->{logger}->error(
            'custom_filter_file_unavailable',
            file => $file,
        );
        return $cached_filter;
    }

    my $mtime = (stat($file))[9] // 0;
    if (
        $cached_filter
        && ($self->{custom_filter_path} // '') eq $file
        && defined($self->{custom_filter_mtime})
        && $self->{custom_filter_mtime} == $mtime
    ) {
        return $cached_filter;
    }

    my $loaded;
    {
        no warnings 'redefine';
        $loaded = eval {
            my $return_value = do $file;
            die $@ if $@;
            die "Unable to read $file: $!" unless defined $return_value;
            die "Custom module $file returned false" unless $return_value;
            die "Custom module $file did not define Postfilter::Local::custom_rules"
                unless defined &Postfilter::Local::custom_rules;
            1;
        };
    }

    if (!$loaded) {
        $self->{logger}->error(
            'custom_filter_reload_rejected',
            error => $@ || 'unknown custom module load failure',
            file  => $file,
        );
        return $cached_filter;
    }

    $self->{custom_filter_coderef} = \&Postfilter::Local::custom_rules;
    $self->{custom_filter_mtime} = $mtime;
    $self->{custom_filter_path} = $file;

    $self->{logger}->pipeline(
        'custom_filter_loaded',
        file  => $file,
        mtime => $mtime,
    );

    return $self->{custom_filter_coderef};
}

# Function: _custom_error_result
# Purpose: Applies custom.on_error to a missing module or custom-rule exception.
# Parameters: $self, $context, $error
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _custom_error_result {
    my ($self, $context, $error) = @_;

    $self->{logger}->error(
        'custom_filter_error',
        error => $error,
    );

    my $on_error =
        $context->{config}{custom}{on_error}
        // 'accept';

    if ($on_error eq 'reject') {
        return _create_rejection_result(63);
    }

    return Postfilter::Result->pass(
        code    => 'PF-RULE-000',
        legacy  => 0,
        message => 'Custom filter failed; fail-open policy applied',
    );
}

# Function: _processing_timeout_result
# Purpose: Translates an exhausted whole-article deadline into configured fail-open or rejection
#          behaviour.
# Parameters: $self, $context, $next_check
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _processing_timeout_result {
    my ($self, $context, $next_check) = @_;

    my $action =
        $context->{config}{timeouts}{on_processing_timeout}
        // 'accept';

    $self->{logger}->warning(
        'article_processing_budget_exceeded',
        action     => $action,
        next_check => $next_check,
    );

    if ($action eq 'reject') {
        return Postfilter::Result->reject(
            code    => 'PF-INTERNAL-097',
            legacy  => 55,
            message => 'Article processing time limit exceeded',
        );
    }

    return Postfilter::Result->pass(
        code    => 'PF-INTERNAL-096',
        legacy  => 0,
        message => 'Remaining checks skipped after processing time limit',
    );
}

# Function: _resolve_policy
# Purpose: Combines technical verdict, audit mode, rule request, and global action into one final
#          outcome.
# Parameters: $self, $context, $result
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _resolve_policy {
    my ($self, $context, $result) = @_;

    my $policy = $context->{config}{policy};
    my $technical_rejection = $result->is_reject;

    if (
        $policy->{mode} eq 'audit'
        && $technical_rejection
        && $result->{legacy} != 48
        && $result->{legacy} != 95
    ) {
        # Audit changes only the NNTP outcome.  Diagnostic side effects remain
        # useful: an operator who selected action_on_reject="save" still gets
        # the rejected article on disk while the client receives success.
        my $save_in_audit = $context->should_save_rejection($result);
        $save_in_audit = 1
            if ($policy->{action_on_reject} // 'reject') eq 'save';

        return {
            action       => 'accept',
            audit_mode   => 1,
            nntp_result  => 'accepted',
            save         => $save_in_audit,
            would_reject => 1,
        };
    }

    my $requested_action = $result->requested_action;
    my $action = $requested_action
        // ($technical_rejection
            ? $policy->{action_on_reject}
            : $policy->{action_on_accept});

    $action = 'reject'
        unless $action =~ /^(?:accept|discard|save|reject)$/;

    my $save = $context->should_save_rejection($result);
    $save = 1 if $action eq 'save';

    my $nntp_result;
    if ($action eq 'accept') {
        $nntp_result = 'accepted';
    }
    elsif ($action eq 'save' && !$technical_rejection) {
        $nntp_result = 'accepted';
    }
    elsif ($action eq 'discard') {
        $nntp_result = 'discarded';
    }
    else {
        $nntp_result = 'rejected';
    }

    if (!$technical_rejection && $action eq 'reject') {
        my ($code, $message) = Postfilter::Codes->lookup(47);
        $result->{verdict} = 'reject';
        $result->{legacy} = 47;
        $result->{code} = $code;
        $result->{message} = $message;
    }

    return {
        action       => $action,
        audit_mode   => 0,
        nntp_result  => $nntp_result,
        save         => $save,
        would_reject => $technical_rejection ? 1 : 0,
    };
}

=head2 _inn_response($context, $result, $final)

Returns the value expected by INN's Perl nnrpd hook.  The string C<DROP> is an
INN-documented special response that silently discards the article while telling
the client that posting succeeded.  It is not an innd-only convention.

=cut

# Function: _inn_response
# Purpose: Converts the resolved outcome to INN’s empty, DROP, or rejection-string hook response.
# Parameters: $self, $context, $result, $final
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _inn_response {
    my ($self, $context, $result, $final) = @_;

    return '' if $final->{nntp_result} eq 'accepted';
    return 'DROP' if $final->{nntp_result} eq 'discarded';

    return $context->{config}{policy}{show_error_code}
        ? $result->{message}
        : 'Message rejected';
}

# Function: shutdown
# Purpose: Closes process-local resources; repeated calls are safe.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub shutdown {
    my ($self) = @_;
    $self->{database}->disconnect if $self->{database};
    return;
}

# Function: _generation_changed
# Purpose: Compares explicit generation IDs rather than relying on reference numeric comparison.
# Parameters: $current, $candidate
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _generation_changed {
    my ($current, $candidate) = @_;
    return 0 unless $candidate;

    my $current_generation = $current->{_meta}{generation} // '';
    my $candidate_generation = $candidate->{_meta}{generation} // '';
    return $current_generation ne $candidate_generation;
}

# Function: _create_rejection_result
# Purpose: Builds a rejection result from the historical numeric-code compatibility table.
# Parameters: $legacy_code
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _create_rejection_result {
    my ($legacy_code) = @_;
    my ($code, $message) = Postfilter::Codes->lookup($legacy_code);

    return Postfilter::Result->reject(
        code    => $code,
        legacy  => $legacy_code,
        message => $message,
    );
}

1;
