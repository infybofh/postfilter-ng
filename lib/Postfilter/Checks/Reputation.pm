package Postfilter::Checks::Reputation;

use strict;
use warnings;

=head1 NAME

Postfilter::Checks::Reputation - TOR, DNSBL, SURBL and URIBL checks.

=head1 DESIGN

All DNS-based checks share a resolver, health state and bounded cache for the
lifetime of the current nnrpd process. Queries use the Net::DNS background API;
the wait ends at the earliest per-query, whole-article DNS or processing
deadline. Resolver retry is limited to one, so the synchronous query API's
default retransmission cycle cannot extend the configured wall-clock budget.

Provider failures are never interpreted as positive listings.  Reply codes in
C<refused_codes> identify blocked public-resolver queries such as URIBL's
127.0.0.1 response.  Only configured C<positive_codes>, or any A answer when the
list deliberately leaves that array empty, produce a listing.

=cut

use Socket qw(AF_INET6 inet_pton);
use Time::HiRes qw(sleep time);

use Postfilter::Codes;
use Postfilter::Result;
use Postfilter::Util qw(ip_in_cidr);

my %CACHE;
my %HEALTH;
my %RESOLVER_BY_PID;

# Function: run_tor
# Purpose: Determines whether the client is a local or DNS-listed TOR node and applies the
#          configured policy.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub run_tor {
    my ($class, $context) = @_;

    my $tor_config = $context->{config}{tor};
    unless ($context->{config}{modules}{tor} && $tor_config->{enabled}) {
        return _pass('PF-TOR-000', 'TOR checks disabled');
    }

    my $is_tor = 0;
    for my $network (@{ $tor_config->{local_tor_networks} // [] }) {
        if (ip_in_cidr($context->{client_ip}, $network)) {
            $is_tor = 1;
            $context->{notes} && push @{ $context->{notes} },
                "tor_local_network=$network";
            last;
        }
    }

    if (!$is_tor) {
        my $zone = $tor_config->{node_scope} eq 'exit'
            ? $tor_config->{dns_zone_exit}
            : $tor_config->{dns_zone_all};

        my $result = _query_ip_list(
            $context,
            $context->{client_ip},
            {
                cooldown_seconds       => $tor_config->{cooldown_seconds},
                failure_threshold      => $tor_config->{failure_threshold},
                id                     => 'tor',
                negative_cache_seconds => $tor_config->{negative_cache_seconds},
                on_error               => $tor_config->{on_error} // 'accept',
                positive_cache_seconds => $tor_config->{positive_cache_seconds},
                positive_codes         => $tor_config->{positive_codes},
                refused_codes          => $tor_config->{refused_codes} // [],
                zone                   => $zone,
            },
            'tor',
        );

        return _reject(50, reason => 'provider-error')
            if $result->{policy_reject};

        $is_tor = 1 if $result->{listed};
    }

    return _pass('PF-TOR-000', 'Client is not a TOR node') unless $is_tor;

    $context->{tor} = 1;
    my $action = $tor_config->{action} // 'mark';

    return _reject(50) if $action eq 'reject';
    return _pass(
        'PF-TOR-001',
        $action eq 'mark' ? 'TOR client marked' : 'TOR client allowed',
    );
}

# Function: run_rbl
# Purpose: Checks the client address against enabled IP DNSBL providers under the shared DNS
#          budget.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub run_rbl {
    my ($class, $context) = @_;

    unless ($context->{config}{modules}{rbl}) {
        return _pass('PF-RBL-000', 'RBL checks disabled');
    }

    for my $provider (@{ $context->{config}{dnsbl} // [] }) {
        next unless $context->rule_applies_to_article_type($provider);
        next unless ref($provider) eq 'HASH' && ($provider->{enabled} // 1);

        my $result = _query_ip_list(
            $context,
            $context->{client_ip},
            $provider,
            'rbl',
        );

        return _reject(
            56,
            provider => $provider->{id},
            reason   => 'provider-error',
        ) if $result->{policy_reject};

        next unless $result->{listed};

        $context->add_hit({
            action  => $provider->{action} // 'reject',
            rule_id => $provider->{id},
            target  => 'client.ip',
            value   => join(',', @{ $result->{answers} }),
        });

        if (($provider->{action} // 'reject') eq 'reject') {
            return _reject(
                56,
                answers  => $result->{answers},
                provider => $provider->{id},
            );
        }
    }

    return _pass('PF-RBL-000', 'RBL checks passed');
}

# Function: run_uri_lists
# Purpose: Extracts registrable domains from article URLs and evaluates enabled SURBL/URIBL
#          providers.
# Parameters: $class, $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub run_uri_lists {
    my ($class, $context) = @_;

    my @domains = @{ $context->extract_domains };
    return _pass('PF-URIBL-000', 'No domains to check') unless @domains;

    for my $list_type (qw(surbl uribl)) {
        next unless $context->{config}{modules}{$list_type};

        for my $provider (@{ $context->{config}{$list_type} // [] }) {
            next unless $context->rule_applies_to_article_type($provider);
            next unless ref($provider) eq 'HASH' && ($provider->{enabled} // 1);

            DOMAIN:
            for my $domain (@domains) {
                my $query_name = "$domain.$provider->{zone}";
                my $result = _dns_query(
                    $context,
                    $query_name,
                    $provider,
                    $list_type,
                );

                my $legacy_code = $list_type eq 'surbl' ? 60 : 61;
                return _reject(
                    $legacy_code,
                    domain   => $domain,
                    provider => $provider->{id},
                    reason   => 'provider-error',
                ) if $result->{policy_reject};

                next DOMAIN unless $result->{listed};

                $context->add_hit({
                    action  => $provider->{action} // 'reject',
                    rule_id => $provider->{id},
                    target  => 'domain',
                    value   => $domain,
                });

                if (($provider->{action} // 'reject') eq 'reject') {
                    return _reject(
                        $legacy_code,
                        answers  => $result->{answers},
                        domain   => $domain,
                        provider => $provider->{id},
                    );
                }
            }
        }
    }

    return _pass('PF-URIBL-000', 'URI reputation checks passed');
}

# Function: _query_ip_list
# Purpose: Reverses an IPv4/IPv6 address and queries one DNSBL-style provider.
# Parameters: $context, $ip, $provider, $list_type
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _query_ip_list {
    my ($context, $ip, $provider, $list_type) = @_;

    my $reversed = _reverse_ip($ip);
    return {
        answers => [],
        error   => 'invalid-ip',
        listed  => 0,
    } unless $reversed;

    return _dns_query(
        $context,
        "$reversed.$provider->{zone}",
        $provider,
        $list_type,
    );
}

=head2 _dns_query($context, $name, $provider, $list_type)

Returns a hash containing C<listed>, C<refused>, C<answers>, optional C<error>
and optional C<policy_reject>.  The function never throws for an ordinary DNS
failure.  Missing Net::DNS is handled as a provider failure, although the runtime
capability check normally disables these modules before the first article.

=cut

# Function: _dns_query
# Purpose: Performs a cached, budget-aware DNS A query and updates provider health/cooldown state.
# Parameters: $context, $query_name, $provider, $list_type
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _dns_query {
    my ($context, $query_name, $provider, $list_type) = @_;

    my $provider_id =
        $provider->{id}
        // $provider->{zone}
        // $query_name;
    my $now = time;

    if (my $health = $HEALTH{$provider_id}) {
        if (($health->{cooldown_until} // 0) > $now) {
            return {
                answers => [],
                error   => 'provider-cooldown',
                listed  => 0,
            };
        }
    }

    my $cache_key = "$provider_id|$query_name";
    if (my $cached = $CACHE{$cache_key}) {
        return $cached->{result} if $cached->{expires} > $now;
        delete $CACHE{$cache_key};
    }

    my $budget_error = _dns_budget_error($context);
    if ($budget_error) {
        return _failure_result(
            $context,
            $provider,
            $provider_id,
            $budget_error,
        );
    }

    my $result;
    my $query_ok = eval {
        require Net::DNS;

        my $resolver = _resolver($context);
        my ($packet, $background_error) = _background_dns_query(
            $context,
            $resolver,
            $query_name,
        );

        if (!$packet) {
            $result = {
                answers => [],
                error   => $background_error || 'dns-failure',
                listed  => 0,
            };
        }
        else {
            my $rcode = eval { $packet->header->rcode } // '';

            if ($rcode eq 'NXDOMAIN') {
                $result = {
                    answers => [],
                    listed  => 0,
                };
            }
            elsif (length($rcode) && $rcode ne 'NOERROR') {
                $result = {
                    answers => [],
                    error   => "dns-rcode-$rcode",
                    listed  => 0,
                };
            }
            else {
                my @answers = map { $_->address }
                    grep { $_->type eq 'A' }
                    $packet->answer;

                my %positive = map { $_ => 1 }
                    @{ $provider->{positive_codes} // [] };
                my %refused = map { $_ => 1 }
                    @{ $provider->{refused_codes} // ['127.0.0.1'] };

                my $is_refused = scalar grep { $refused{$_} } @answers;
                my $is_listed = @{ $provider->{positive_codes} // [] }
                    ? scalar grep { $positive{$_} } @answers
                    : scalar @answers;

                $is_listed = 0 if $is_refused;

                $result = {
                    answers => \@answers,
                    listed  => $is_listed ? 1 : 0,
                    refused => $is_refused ? 1 : 0,
                };
            }
        }

        1;
    };

    if (!$query_ok) {
        $result = {
            answers => [],
            error   => $@ || 'Net::DNS unavailable',
            listed  => 0,
        };
    }

    if ($result->{error} || $result->{refused}) {
        my $failure_text =
            $result->{error}
            // 'query-refused';
        $result = _failure_result(
            $context,
            $provider,
            $provider_id,
            $failure_text,
            $result,
        );
    }
    else {
        $HEALTH{$provider_id} = {
            failures    => 0,
            last_success => $now,
        };
    }

    my $cache_seconds = $result->{listed}
        ? ($provider->{positive_cache_seconds} // 3_600)
        : ($provider->{negative_cache_seconds} // 300);

    $CACHE{$cache_key} = {
        created => $now,
        expires => $now + $cache_seconds,
        result  => $result,
    };
    _prune_cache($context);

    $context->{logger}->reputation(
        'dns_reputation_query',
        answers  => join(',', @{ $result->{answers} // [] }),
        error    => $result->{error} // '',
        listed   => $result->{listed} // 0,
        provider => $provider_id,
        query    => $query_name,
        refused  => $result->{refused} // 0,
        type     => $list_type,
    );

    return $result;
}

# Function: _background_dns_query
# Purpose: Performs one asynchronous DNS query within the smaller of query, DNS-total and article
#          deadlines.
# Parameters: $context, $resolver, $query_name
# Operational notes: The method never calls the synchronous query() API and therefore does not
#                    inherit its multi-retry wall-clock behaviour.
sub _background_dns_query {
    my ($context, $resolver, $query_name) = @_;

    $context->{dns_started_at} //= time;
    my $now = time;
    my @deadline;

    my $query_seconds =
        $context->{config}{timeouts}{dns_query_seconds}
        // 1;
    push @deadline, $now + $query_seconds if $query_seconds > 0;

    my $total_seconds =
        $context->{config}{timeouts}{dns_total_seconds}
        // 1;
    push @deadline, $context->{dns_started_at} + $total_seconds
        if $total_seconds > 0;

    my $remaining_processing_ms = $context->remaining_processing_ms;
    push @deadline, $now + ($remaining_processing_ms / 1_000)
        if defined $remaining_processing_ms;

    my $deadline = @deadline
        ? (sort { $a <=> $b } @deadline)[0]
        : undef;

    if (defined $deadline && $deadline <= $now) {
        return (undef, _dns_budget_error($context) || 'dns-query-timeout');
    }

    my $handle = $resolver->bgsend($query_name, 'A');
    return (undef, $resolver->errorstring || 'dns-send-failure')
        unless $handle;

    while ($resolver->bgbusy($handle)) {
        my $budget_error = _dns_budget_error($context);
        return (undef, $budget_error) if $budget_error;

        $now = time;
        return (undef, 'dns-query-timeout')
            if defined $deadline && $now >= $deadline;

        my $pause = 0.01;
        if (defined $deadline) {
            my $remaining = $deadline - $now;
            $pause = $remaining if $remaining < $pause;
        }
        sleep($pause) if $pause > 0;
    }

    my $packet = $resolver->bgread($handle);
    return ($packet, undef) if $packet;
    return (undef, $resolver->errorstring || 'dns-no-response');
}

# Function: _resolver
# Purpose: Lazily constructs and reuses one Net::DNS resolver per nnrpd process.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _resolver {
    my ($context) = @_;

    return $RESOLVER_BY_PID{$$} if $RESOLVER_BY_PID{$$};

    my $resolver = Net::DNS::Resolver->new;
    my $timeout =
        $context->{config}{timeouts}{dns_query_seconds}
        // 1;
    $resolver->retry(1);
    $resolver->retrans($timeout);
    $resolver->udp_timeout($timeout);
    $resolver->tcp_timeout($timeout);

    $RESOLVER_BY_PID{$$} = $resolver;
    return $resolver;
}

# Function: _dns_budget_error
# Purpose: Detects exhausted per-article DNS time and returns the provider’s configured failure
#          outcome.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _dns_budget_error {
    my ($context) = @_;

    return 'article-processing-deadline-exceeded'
        if $context->deadline_exceeded;

    $context->{dns_started_at} //= time;
    my $total_seconds =
        $context->{config}{timeouts}{dns_total_seconds}
        // 1;

    return
        if $total_seconds <= 0
        || time - $context->{dns_started_at} < $total_seconds;

    return 'dns-total-budget-exceeded';
}

# Function: _failure_result
# Purpose: Translates provider timeout/refusal/internal failure into accept, skip, or rejection
#          policy.
# Parameters: $context, $provider, $provider_id, $error, $base_result
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _failure_result {
    my ($context, $provider, $provider_id, $error, $base_result) = @_;

    my $health = $HEALTH{$provider_id} //= { failures => 0 };
    $health->{failures}++;
    $health->{last_error} = $error;

    my $failure_threshold = $provider->{failure_threshold} // 5;
    if ($health->{failures} >= $failure_threshold) {
        $health->{cooldown_until} = time
            + ($provider->{cooldown_seconds} // 300);
    }

    $context->{logger}->warning(
        'reputation_provider_failure',
        error     => $error,
        failures  => $health->{failures},
        provider  => $provider_id,
    );

    my %result = %{ $base_result // {} };
    $result{answers} //= [];
    $result{error} = $error;
    $result{listed} = 0;
    my $policy_name = $error =~ /(?:timeout|budget|deadline)/i
        ? 'on_timeout'
        : 'on_error';
    my $failure_policy =
        $provider->{$policy_name}
        // $provider->{on_error}
        // 'accept';

    $result{policy_reject} = 1
        if $failure_policy eq 'reject';
    $result{failure_policy} = $failure_policy;

    return \%result;
}

# Function: _prune_cache
# Purpose: Removes expired/oldest DNS cache entries to enforce the process-local bound.
# Parameters: $context
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _prune_cache {
    my ($context) = @_;

    my $maximum_entries =
        $context->limit('dns_cache_max_entries')
        // 2_000;
    return if $maximum_entries <= 0 || keys(%CACHE) <= $maximum_entries;

    my @oldest = sort {
        ($CACHE{$a}{created} // 0) <=> ($CACHE{$b}{created} // 0)
    } keys %CACHE;

    my $to_remove = keys(%CACHE) - $maximum_entries;
    for my $cache_key (@oldest[0 .. $to_remove - 1]) {
        delete $CACHE{$cache_key};
    }

    return;
}

# Function: _reverse_ip
# Purpose: Converts IPv4 or IPv6 into DNSBL nibble/reversed-octet query form.
# Parameters: $ip
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _reverse_ip {
    my ($ip) = @_;

    if ($ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/) {
        return join '.', reverse($1, $2, $3, $4);
    }

    my $packed = inet_pton(AF_INET6, $ip);
    return unless $packed;

    my $hexadecimal = unpack('H*', $packed);
    return join '.', reverse split //, $hexadecimal;
}

# Function: _pass
# Purpose: Constructs a successful reputation-check result.
# Parameters: $code, $message
# Operational notes: Does not write an NNTP response directly; the orchestrator resolves the
#                    returned result.
sub _pass {
    my ($code, $message) = @_;
    return Postfilter::Result->pass(
        code    => $code,
        legacy  => 0,
        message => $message,
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
