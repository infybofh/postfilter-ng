package Postfilter::Database;

use strict;
use warnings;

=head1 NAME

Postfilter::Database - SQLite persistence, rate history and legal audit storage.

=head1 RETENTION POLICY

C<article_events> and C<rule_hits> replace the historical C<legal.log>.  The rewrite
therefore performs no automatic event deletion.  The default retention value is
C<forever>, and records are removed only by an explicit C<postfilterctl purge>
command.  Destructive commands support dry-run and write an administrative audit
record inside the same database.

=head1 CONCURRENCY

Every nnrpd process owns its DBI connection.  SQLite WAL permits concurrent
readers and serialises short write transactions.  No DNS query, body scan or file
write occurs while a transaction is open.  The database must reside on a local
filesystem with reliable locking.

=head1 IDENTITY PRIVACY

The operator chooses C<plain>, C<hmac> or C<encrypted> storage for IP, domain,
user and From values.  Separate deterministic lookup columns allow rate limits
to work even when displayed values use randomised reversible encryption.  The
default is C<plain> because the database is private and intended for long-term
law-enforcement queries; report privacy is configured separately.

=cut

use File::Basename qw(dirname);
use File::Path qw(make_path);
use JSON::PP;

# Function: new
# Purpose: Constructs the SQLite component without opening a connection until required.
# Parameters: $class, %arguments
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub new {
    my ($class, %arguments) = @_;

    return bless {
        config     => $arguments{config},
        crypto     => $arguments{crypto},
        dbh        => undef,
        disabled   => 0,
        last_error => undef,
        logger     => $arguments{logger},
    }, $class;
}

# Function: available
# Purpose: Reports whether SQLite is enabled and not disabled after a configured failure.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub available {
    my ($self) = @_;
    return 0 if $self->{disabled};
    return 0 unless $self->{config}{database}{enabled};
    return 1;
}

=head2 update_config($config)

Updates process-local settings after a successful configuration reload.  A
changed database path or privacy key disconnects the current handle so the next
operation reopens with the new values.

=cut

# Function: update_config
# Purpose: Replaces the database component’s validated configuration after a generation reload.
# Parameters: $self, $config
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub update_config {
    my ($self, $config) = @_;

    my $old_path = $self->{config}{database}{path} // '';
    my $new_path = $config->{database}{path} // '';
    my $old_mode = $self->{config}{database}{privacy}{identity_mode} // 'plain';
    my $new_mode = $config->{database}{privacy}{identity_mode} // 'plain';

    $self->{config} = $config;
    $self->{disabled} = 0 if $config->{database}{enabled};

    if ($old_path ne $new_path || $old_mode ne $new_mode) {
        $self->disconnect;
    }

    return;
}

=head2 connect()

Opens SQLite, applies WAL-related pragmas and migrates the schema.  Throws on
failure; callers apply C<database.on_failure> through C<handle_failure>.

=cut

# Function: connect
# Purpose: Opens/reuses SQLite, applies WAL and durability pragmas, and runs idempotent
#          migrations.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub connect {
    my ($self) = @_;

    return if $self->{disabled};
    return $self->{dbh}
        if $self->{dbh} && eval { $self->{dbh}->ping };

    my $database_config = $self->{config}{database};
    return unless $database_config->{enabled};

    eval { require DBI; 1 }
        or die "DBI is not installed\n";
    eval { require DBD::SQLite; 1 }
        or die "DBD::SQLite is not installed\n";

    my $path = $database_config->{path};
    make_path(dirname($path), { mode => 0750 }) unless -d dirname($path);

    my $database = DBI->connect(
        "dbi:SQLite:dbname=$path",
        '',
        '',
        {
            AutoCommit    => 1,
            PrintError    => 0,
            RaiseError    => 1,
            sqlite_unicode => 1,
        },
    );

    $database->do('PRAGMA journal_mode=WAL');
    $database->do('PRAGMA foreign_keys=ON');
    $database->do(
        'PRAGMA busy_timeout=' .
        (0 + ($database_config->{busy_timeout_ms} // 5_000))
    );

    my $synchronous = $database_config->{synchronous} // 'FULL';
    $synchronous = 'FULL'
        unless $synchronous =~ /^(?:OFF|NORMAL|FULL|EXTRA)$/;
    $database->do("PRAGMA synchronous=$synchronous");

    $self->{dbh} = $database;
    $self->migrate;
    return $database;
}

=head2 require_connection($operation)

Returns a live SQLite handle for administrative commands.  Unlike C<connect>,
this method treats a disabled database as an explicit operator error instead of
returning C<undef>.

=cut

# Function: require_connection
# Purpose: Returns a live SQLite handle or raises a clear command-oriented diagnostic.
# Parameters: $self, $operation
# Operational notes: Runtime filtering may intentionally disable SQLite; administrative database
#                    commands must never continue with an undefined DBI handle.
sub require_connection {
    my ($self, $operation) = @_;
    $operation //= 'database operation';

    die "SQLite is disabled in the effective configuration; "
        . "$operation cannot continue\n"
        unless $self->available;

    my $database = eval { $self->connect };
    my $error = $@;
    if (!$database) {
        $error ||= 'no database handle was returned';
        $error =~ s/\s+\z//;
        die "Unable to open SQLite for $operation: $error\n";
    }

    return $database;
}

=head2 migrate()

Creates a fresh schema or upgrades any previously published Postfilter-NG schema.
Migration versions add deterministic identity lookup columns, per-row privacy
metadata, article-type fields and administrative audit records. The method is
idempotent.

=cut

# Function: migrate
# Purpose: Creates or upgrades the SQLite schema transactionally and records applied versions.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub migrate {
    my ($self) = @_;

    my $database = $self->{dbh} || $self->connect;
    $database->do(q{
        CREATE TABLE IF NOT EXISTS schema_migrations(
            version INTEGER PRIMARY KEY,
            applied_at INTEGER NOT NULL
        )
    });

    my ($version) = $database->selectrow_array(
        'SELECT COALESCE(MAX(version), 0) FROM schema_migrations'
    );

    if ($version < 1) {
        $database->begin_work;
        my $created = eval {
            $database->do(q{
                CREATE TABLE article_events(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    received_at REAL NOT NULL,
                    message_id TEXT,
                    message_id_hash TEXT,
                    article_digest TEXT,
                    article_type TEXT NOT NULL DEFAULT 'text',
                    client_ip TEXT,
                    client_ip_lookup TEXT,
                    client_domain TEXT,
                    client_domain_lookup TEXT,
                    auth_user TEXT,
                    auth_user_lookup TEXT,
                    from_address TEXT,
                    from_address_lookup TEXT,
                    identity_storage_mode TEXT NOT NULL DEFAULT 'plain',
                    newsgroups TEXT,
                    followup_to TEXT,
                    group_count INTEGER NOT NULL DEFAULT 0,
                    followup_count INTEGER NOT NULL DEFAULT 0,
                    body_size INTEGER NOT NULL DEFAULT 0,
                    header_size INTEGER NOT NULL DEFAULT 0,
                    total_size INTEGER NOT NULL DEFAULT 0,
                    trusted_profile TEXT,
                    technical_verdict TEXT NOT NULL,
                    final_action TEXT NOT NULL,
                    nntp_result TEXT NOT NULL,
                    reason_code TEXT NOT NULL,
                    legacy_code INTEGER NOT NULL,
                    reason_text TEXT,
                    audit_mode INTEGER NOT NULL DEFAULT 0,
                    would_reject INTEGER NOT NULL DEFAULT 0,
                    tor INTEGER NOT NULL DEFAULT 0,
                    saved_path TEXT,
                    elapsed_ms REAL,
                    config_generation TEXT,
                    details_json TEXT
                )
            });

            $database->do(q{
                CREATE INDEX article_events_received_idx
                    ON article_events(received_at)
            });
            $database->do(q{
                CREATE INDEX article_events_type_time_idx
                    ON article_events(article_type, received_at)
            });
            $database->do(q{
                CREATE INDEX article_events_ip_time_idx
                    ON article_events(client_ip_lookup, received_at)
            });
            $database->do(q{
                CREATE INDEX article_events_domain_time_idx
                    ON article_events(client_domain_lookup, received_at)
            });
            $database->do(q{
                CREATE INDEX article_events_user_time_idx
                    ON article_events(auth_user_lookup, received_at)
            });
            $database->do(q{
                CREATE INDEX article_events_digest_time_idx
                    ON article_events(article_digest, received_at)
            });
            $database->do(q{
                CREATE INDEX article_events_reason_time_idx
                    ON article_events(reason_code, received_at)
            });
            $database->do(q{
                CREATE INDEX article_events_message_id_idx
                    ON article_events(message_id)
            });

            $database->do(q{
                CREATE TABLE rule_hits(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id INTEGER NOT NULL,
                    rule_id TEXT NOT NULL,
                    target TEXT,
                    score REAL DEFAULT 0,
                    action TEXT,
                    details TEXT,
                    FOREIGN KEY(event_id)
                        REFERENCES article_events(id)
                        ON DELETE CASCADE
                )
            });
            $database->do(q{
                CREATE INDEX rule_hits_rule_idx
                    ON rule_hits(rule_id, event_id)
            });

            $database->do(q{
                CREATE TABLE saved_articles(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id INTEGER,
                    article_type TEXT NOT NULL DEFAULT 'text',
                    path TEXT NOT NULL UNIQUE,
                    file_sha256 TEXT NOT NULL,
                    file_size INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    FOREIGN KEY(event_id)
                        REFERENCES article_events(id)
                        ON DELETE SET NULL
                )
            });

            $database->do(q{
                CREATE INDEX saved_articles_type_time_idx
                    ON saved_articles(article_type, created_at)
            });

            $database->do(q{
                CREATE TABLE local_distribution(
                    message_id TEXT PRIMARY KEY,
                    created_at REAL NOT NULL
                )
            });
            $database->do(q{
                CREATE INDEX local_distribution_time_idx
                    ON local_distribution(created_at)
            });

            $database->do(q{
                CREATE TABLE provider_health(
                    provider_id TEXT PRIMARY KEY,
                    provider_type TEXT NOT NULL,
                    state TEXT NOT NULL DEFAULT 'healthy',
                    failures INTEGER NOT NULL DEFAULT 0,
                    last_failure_at REAL,
                    cooldown_until REAL,
                    last_error TEXT,
                    last_success_at REAL
                )
            });

            $database->do(q{
                CREATE TABLE configuration_generations(
                    generation TEXT PRIMARY KEY,
                    loaded_at REAL NOT NULL,
                    origin TEXT,
                    warnings INTEGER NOT NULL DEFAULT 0
                )
            });

            $database->do(q{
                CREATE TABLE administrative_actions(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    performed_at REAL NOT NULL,
                    operating_user TEXT,
                    command TEXT NOT NULL,
                    parameters_json TEXT,
                    affected_rows INTEGER,
                    note TEXT
                )
            });

            $database->do(q{
                INSERT INTO schema_migrations(version, applied_at)
                VALUES(1, strftime('%s', 'now'))
            });

            $database->commit;
            1;
        };

        if (!$created) {
            my $error = $@;
            eval { $database->rollback };
            die $error;
        }

        $version = 1;
    }

    if ($version < 2) {
        $database->begin_work;
        my $upgraded = eval {
            for my $column (qw(
                client_ip_lookup
                client_domain_lookup
                auth_user_lookup
                from_address_lookup
            )) {
                _add_column_if_missing(
                    $database,
                    'article_events',
                    $column,
                    'TEXT',
                );
            }

            # Current rate and administrative queries use deterministic lookup
            # columns in every privacy mode. Rebuild older clear-text identity
            # indexes during upgrade. Fresh databases use the same code path.
            for my $index_name (qw(
                article_events_ip_time_idx
                article_events_domain_time_idx
                article_events_user_time_idx
            )) {
                $database->do("DROP INDEX IF EXISTS $index_name");
            }

            $database->do(q{
                CREATE INDEX article_events_ip_time_idx
                    ON article_events(client_ip_lookup, received_at)
            });
            $database->do(q{
                CREATE INDEX article_events_domain_time_idx
                    ON article_events(client_domain_lookup, received_at)
            });
            $database->do(q{
                CREATE INDEX article_events_user_time_idx
                    ON article_events(auth_user_lookup, received_at)
            });
            $database->do(q{
                CREATE INDEX IF NOT EXISTS article_events_from_lookup_time_idx
                    ON article_events(from_address_lookup, received_at)
            });

            $database->do(q{
                CREATE TABLE IF NOT EXISTS administrative_actions(
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    performed_at REAL NOT NULL,
                    operating_user TEXT,
                    command TEXT NOT NULL,
                    parameters_json TEXT,
                    affected_rows INTEGER,
                    note TEXT
                )
            });

            $database->do(q{
                INSERT INTO schema_migrations(version, applied_at)
                VALUES(2, strftime('%s', 'now'))
            });

            $database->commit;
            1;
        };

        if (!$upgraded) {
            my $error = $@;
            eval { $database->rollback };
            die $error;
        }
    }

    if ($version < 3) {
        $database->begin_work;
        my $upgraded = eval {
            _add_column_if_missing(
                $database,
                'article_events',
                'identity_storage_mode',
                q{TEXT NOT NULL DEFAULT 'plain'},
            );

            $database->do(q{
                INSERT INTO schema_migrations(version, applied_at)
                VALUES(3, strftime('%s', 'now'))
            });

            $database->commit;
            1;
        };

        if (!$upgraded) {
            my $error = $@;
            eval { $database->rollback };
            die $error;
        }
    }

    if ($version < 4) {
        $database->begin_work;
        my $upgraded = eval {
            _add_column_if_missing(
                $database,
                'article_events',
                'article_type',
                q{TEXT NOT NULL DEFAULT 'text'},
            );
            _add_column_if_missing(
                $database,
                'saved_articles',
                'article_type',
                q{TEXT NOT NULL DEFAULT 'text'},
            );
            $database->do(q{
                CREATE INDEX IF NOT EXISTS article_events_type_time_idx
                    ON article_events(article_type, received_at)
            });
            $database->do(q{
                CREATE INDEX IF NOT EXISTS saved_articles_type_time_idx
                    ON saved_articles(article_type, created_at)
            });
            $database->do(q{
                INSERT INTO schema_migrations(version, applied_at)
                VALUES(4, strftime('%s', 'now'))
            });
            $database->commit;
            1;
        };

        if (!$upgraded) {
            my $error = $@;
            eval { $database->rollback };
            die $error;
        }
    }

    return 1;
}

# Function: _add_column_if_missing
# Purpose: Adds one upgrade column only after PRAGMA table_info confirms it is absent.
# Parameters: $database, $table, $column, $definition
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _add_column_if_missing {
    my ($database, $table, $column, $definition) = @_;

    my $columns = $database->selectall_arrayref(
        "PRAGMA table_info($table)",
        { Slice => {} },
    );
    return if grep { $_->{name} eq $column } @{$columns};

    $database->do(
        "ALTER TABLE $table ADD COLUMN $column $definition"
    );
    return;
}

=head2 handle_failure($error)

Logs a SQLite error and returns the configured action.  C<disable> suppresses
future connection attempts for the lifetime of the current nnrpd process.

=cut

# Function: handle_failure
# Purpose: Logs an SQLite failure and translates database.on_failure into accept, reject, or
#          disable.
# Parameters: $self, $error
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub handle_failure {
    my ($self, $error) = @_;

    $self->{last_error} = $error;
    $self->{logger}->error(
        'sqlite_failure',
        error => $error,
    ) if $self->{logger};

    my $action = $self->{config}{database}{on_failure} // 'accept';
    $self->{disabled} = 1 if $action eq 'disable';
    return $action;
}

=head2 rate_snapshot($context, $identity_type, $identity_value)

Returns historical counters for one identity.  The deterministic lookup key is
used instead of the display value, so rate limiting remains functional in all
privacy modes.

=cut

# Function: rate_snapshot
# Purpose: Queries long/short accepted, rejected, byte, group, and followup counters for one
#          identity.
# Parameters: $self, $context, $identity_type, $identity_value
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub rate_snapshot {
    my ($self, $context, $identity_type, $identity_value) = @_;

    my $database = $self->connect or return {};
    my $now = $context->{received_at};
    my $period = $context->{config}{access}{period_seconds} // 86_400;
    my $short_period =
        $context->{config}{access}{short_period_seconds}
        // 600;

    my %identity_definition = (
        IP => {
            lookup_column => 'client_ip_lookup',
            lookup_purpose => 'client_ip',
        },
        DN => {
            lookup_column => 'client_domain_lookup',
            lookup_purpose => 'client_domain',
        },
        ID => {
            lookup_column => 'auth_user_lookup',
            lookup_purpose => 'auth_user',
        },
    );

    my $definition = $identity_definition{$identity_type}
        or die "Invalid rate identity type $identity_type";

    my $column = $definition->{lookup_column};
    my $lookup_value = $self->_identity_lookup(
        $definition->{lookup_purpose},
        $identity_value,
    );

    my $sql = qq{
        SELECT
            SUM(CASE WHEN received_at >= ? AND nntp_result = 'accepted'
                     THEN 1 ELSE 0 END),
            SUM(CASE WHEN received_at >= ? AND nntp_result = 'accepted'
                     THEN 1 ELSE 0 END),
            SUM(CASE WHEN received_at >= ? AND technical_verdict = 'reject'
                     THEN 1 ELSE 0 END),
            SUM(CASE WHEN received_at >= ? AND technical_verdict = 'reject'
                     THEN 1 ELSE 0 END),
            SUM(CASE WHEN received_at >= ? THEN total_size ELSE 0 END),
            SUM(CASE WHEN received_at >= ? THEN total_size ELSE 0 END),
            SUM(CASE WHEN received_at >= ? THEN group_count ELSE 0 END),
            SUM(CASE WHEN received_at >= ? THEN group_count ELSE 0 END),
            SUM(CASE WHEN received_at >= ? THEN followup_count ELSE 0 END),
            SUM(CASE WHEN received_at >= ? THEN followup_count ELSE 0 END)
        FROM article_events
        WHERE $column = ?
    };

    my @bind = (
        $now - $period,
        $now - $short_period,
        $now - $period,
        $now - $short_period,
        $now - $period,
        $now - $short_period,
        $now - $period,
        $now - $short_period,
        $now - $period,
        $now - $short_period,
        $lookup_value,
    );

    if ($context->{config}{access}{separate_counters_by_article_type}) {
        $sql .= ' AND article_type = ?';
        push @bind, $context->{article_type};
    }

    my @values = $database->selectrow_array(
        $sql,
        undef,
        @bind,
    );

    return {
        max_articles          => $values[0] // 0,
        max_short_articles    => $values[1] // 0,
        max_total_errors      => $values[2] // 0,
        max_short_errors      => $values[3] // 0,
        max_total_size        => $values[4] // 0,
        max_short_size        => $values[5] // 0,
        max_total_groups      => $values[6] // 0,
        max_short_groups      => $values[7] // 0,
        max_total_followups   => $values[8] // 0,
        max_short_followups   => $values[9] // 0,
    };
}

# Function: multipost_count
# Purpose: Counts previously accepted events with the same article digest inside the configured
#          period.
# Parameters: $self, $context
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub multipost_count {
    my ($self, $context) = @_;

    my $database = $self->connect or return 0;
    my $period = $context->{config}{access}{period_seconds} // 86_400;

    my $sql = q{
        SELECT COUNT(*)
        FROM article_events
        WHERE article_digest = ?
          AND received_at >= ?
          AND nntp_result = 'accepted'
    };
    my @bind = (
        $context->{article_digest},
        $context->{received_at} - $period,
    );

    if ($context->{config}{access}{separate_counters_by_article_type}) {
        $sql .= ' AND article_type = ?';
        push @bind, $context->{article_type};
    }

    my ($count) = $database->selectrow_array(
        $sql,
        undef,
        @bind,
    );

    return $count // 0;
}

# Function: local_distribution_add
# Purpose: Records a local-distribution Message-ID for reply inheritance.
# Parameters: $self, $message_id, $time
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub local_distribution_add {
    my ($self, $message_id, $time) = @_;
    my $database = $self->connect or return;

    $database->do(
        q{
            INSERT OR REPLACE INTO local_distribution(message_id, created_at)
            VALUES(?, ?)
        },
        undef,
        $message_id,
        $time,
    );

    return;
}

# Function: local_distribution_remove
# Purpose: Removes a local-distribution marker when a later mandatory persistence failure rejects
#          the article before nnrpd receives its final response.
# Parameters: $self, $message_id
# Operational notes: This compensating operation is used only during the same filter invocation;
#                    ordinary legal-history purge never touches this table implicitly.
sub local_distribution_remove {
    my ($self, $message_id) = @_;

    my $database = $self->connect or return;
    $database->do(
        'DELETE FROM local_distribution WHERE message_id = ?',
        undef,
        $message_id,
    );

    return;
}

# Function: local_distribution_exists
# Purpose: Tests whether a referenced Message-ID was recorded with local distribution.
# Parameters: $self, $message_id
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub local_distribution_exists {
    my ($self, $message_id) = @_;
    my $database = $self->connect or return 0;

    my ($exists) = $database->selectrow_array(
        'SELECT 1 FROM local_distribution WHERE message_id = ?',
        undef,
        $message_id,
    );

    return $exists ? 1 : 0;
}

=head2 record_event($context, $result, $final)

Persists the single final event and every rule hit in one short transaction.
There is no double accept/reject row.  Audit mode records the technical rejection
and the accepted NNTP result in separate columns of the same event.

=cut

# Function: record_event
# Purpose: Writes the single final article event and all rule hits in one short SQLite
#          transaction.
# Parameters: $self, $context, $result, $final
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub record_event {
    my ($self, $context, $result, $final) = @_;

    my $database = $self->connect or return;

    my $details = JSON::PP->new->canonical->encode({
        article_type   => $context->{article_type},
        binary_groups  => $context->{binary_groups},
        text_groups    => $context->{text_groups},
        attributes     => $context->{attributes},
        notes          => $context->{notes},
        skipped_checks => $context->{skipped_checks},
    });

    my %identity = (
        client_ip     => $context->{client_ip},
        client_domain => $context->{client_domain},
        auth_user     => $context->{user},
        from_address  => $context->{from_address},
    );

    my %stored;
    for my $name (keys %identity) {
        $stored{$name} = $self->_protect_identity($name, $identity{$name});
        $stored{"${name}_lookup"} =
            $self->_identity_lookup($name, $identity{$name});
    }

    my $event_id;
    $database->begin_work;

    my $stored_ok = eval {
        my $statement = $database->prepare(q{
            INSERT INTO article_events(
                received_at, message_id, message_id_hash, article_digest,
                article_type,
                client_ip, client_ip_lookup,
                client_domain, client_domain_lookup,
                auth_user, auth_user_lookup,
                from_address, from_address_lookup, identity_storage_mode,
                newsgroups, followup_to, group_count, followup_count,
                body_size, header_size, total_size, trusted_profile,
                technical_verdict, final_action, nntp_result, reason_code,
                legacy_code, reason_text, audit_mode, would_reject, tor,
                saved_path, elapsed_ms, config_generation, details_json
            ) VALUES(
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
        });

        $statement->execute(
            $context->{received_at},
            $context->{message_id},
            $context->{message_id_hash},
            $context->{article_digest},
            $context->{article_type},
            $stored{client_ip},
            $stored{client_ip_lookup},
            $stored{client_domain},
            $stored{client_domain_lookup},
            $stored{auth_user},
            $stored{auth_user_lookup},
            $stored{from_address},
            $stored{from_address_lookup},
            $self->{config}{database}{privacy}{identity_mode} // 'plain',
            join(',', @{ $context->{newsgroups} }),
            join(',', @{ $context->{followups} }),
            $context->{group_count},
            $context->{followup_count},
            $context->{body_size},
            $context->{header_size},
            $context->{total_size},
            $context->{trusted_profile}{id} // '',
            $result->{verdict},
            $final->{action},
            $final->{nntp_result},
            $result->{code},
            $result->{legacy},
            $result->{message},
            $final->{audit_mode} ? 1 : 0,
            $final->{would_reject} ? 1 : 0,
            $context->{tor} ? 1 : 0,
            $context->{saved_path},
            $context->elapsed_ms,
            $context->{config}{_meta}{generation} // '',
            $details,
        );

        $event_id = $database->sqlite_last_insert_rowid;

        my $hit_statement = $database->prepare(q{
            INSERT INTO rule_hits(
                event_id, rule_id, target, score, action, details
            ) VALUES(?, ?, ?, ?, ?, ?)
        });

        for my $hit (@{ $context->{rule_hits} }) {
            $hit_statement->execute(
                $event_id,
                $hit->{rule_id} // '',
                $hit->{target} // '',
                0 + ($hit->{score} // 0),
                $hit->{action} // '',
                JSON::PP->new->canonical->encode($hit),
            );
        }

        $database->commit;
        1;
    };

    if (!$stored_ok) {
        my $error = $@ || 'unknown SQLite transaction error';
        eval { $database->rollback };
        die $error;
    }

    return $event_id;
}

# Function: saved_article_add
# Purpose: Links a saved article file, digest, size, and timestamp to its event record.
# Parameters: $self, %article
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub saved_article_add {
    my ($self, %article) = @_;
    my $database = $self->connect or return;

    $database->do(
        q{
            INSERT INTO saved_articles(
                event_id, article_type, path, file_sha256, file_size, created_at
            ) VALUES(?, ?, ?, ?, ?, ?)
        },
        undef,
        $article{event_id},
        $article{article_type} // 'text',
        $article{path},
        $article{sha256},
        $article{size},
        $article{created_at},
    );

    return;
}

=head2 purge_events_before(%arguments)

Explicitly deletes event history older than C<before>.  The caller must supply
C<confirm = 1>; otherwise only the count is returned.  The operation and number
of affected rows are recorded in C<administrative_actions>.

=cut

# Function: purge_events_before
# Purpose: Counts or explicitly deletes old events and records every confirmed destructive
#          operation.
# Parameters: $self, %arguments
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub purge_events_before {
    my ($self, %arguments) = @_;

    my $before = $arguments{before};
    die "purge_events_before requires a numeric epoch\n"
        unless defined $before && $before =~ /^\d+(?:\.\d+)?$/;

    my $database = $self->connect or return 0;
    my ($count) = $database->selectrow_array(
        'SELECT COUNT(*) FROM article_events WHERE received_at < ?',
        undef,
        $before,
    );

    return $count // 0 unless $arguments{confirm};

    $database->begin_work;
    my $purged = eval {
        my $rows = $database->do(
            'DELETE FROM article_events WHERE received_at < ?',
            undef,
            $before,
        );

        $self->_record_administrative_action(
            database       => $database,
            command        => 'purge-events-before',
            operating_user => $arguments{operating_user},
            affected_rows  => $rows,
            parameters     => { before => 0 + $before },
            note           => $arguments{note},
        );

        $database->commit;
        $rows;
    };

    if ($@) {
        my $error = $@;
        eval { $database->rollback };
        die $error;
    }

    return $purged;
}

=head2 maintenance_provider_health()

Removes only stale provider-health telemetry according to its dedicated
retention.  It never deletes article, identity, rule-hit or saved-article data.

=cut

# Function: maintenance_provider_health
# Purpose: Deletes only stale provider-health telemetry, never legal article history.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub maintenance_provider_health {
    my ($self) = @_;

    my $database = $self->connect or return 0;
    my $seconds =
        $self->{config}{retention}{provider_health_seconds}
        // 604_800;

    return $database->do(
        q{
            DELETE FROM provider_health
            WHERE COALESCE(last_failure_at, last_success_at, 0) < ?
        },
        undef,
        time - $seconds,
    );
}

# Function: backup_to_file
# Purpose: Creates a consistent SQLite backup through the database backup API.
# Parameters: $self, $destination
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub backup_to_file {
    my ($self, $destination) = @_;
    my $database = $self->connect
        or die "SQLite database is unavailable\n";

    if ($database->can('sqlite_backup_to_file')) {
        $database->sqlite_backup_to_file($destination);
        return 1;
    }

    # VACUUM INTO creates a consistent database snapshot and is preferable to
    # copying the main file while WAL contains uncheckpointed transactions.
    my $quoted = $destination;
    $quoted =~ s/'/''/g;
    $database->do("VACUUM INTO '$quoted'");
    return 1;
}

# Function: _record_administrative_action
# Purpose: Writes an immutable audit row describing an explicit maintenance or purge command.
# Parameters: $self, %arguments
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _record_administrative_action {
    my ($self, %arguments) = @_;

    $arguments{database}->do(
        q{
            INSERT INTO administrative_actions(
                performed_at, operating_user, command, parameters_json,
                affected_rows, note
            ) VALUES(?, ?, ?, ?, ?, ?)
        },
        undef,
        time,
        $arguments{operating_user} // '',
        $arguments{command},
        JSON::PP->new->canonical->encode($arguments{parameters} // {}),
        $arguments{affected_rows},
        $arguments{note} // '',
    );

    return;
}

# Function: _protect_identity
# Purpose: Stores an identity as plain text, stable HMAC, or reversible authenticated ciphertext.
# Parameters: $self, $purpose, $value
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _protect_identity {
    my ($self, $purpose, $value) = @_;
    $value //= '';

    my $mode =
        $self->{config}{database}{privacy}{identity_mode}
        // 'plain';
    return $value if $mode eq 'plain';

    my $key = $self->_database_privacy_key;
    return 'h1:' . $self->{crypto}->pseudonym($value, $key, 32)
        if $mode eq 'hmac';

    return $self->{crypto}->encrypt_token(
        $value,
        $key,
        "database-$purpose",
    );
}

=head2 identity_lookup($purpose, $value)

Returns the stable indexed lookup token for a plaintext identity.  Administrative
commands use this method instead of querying protected columns directly, so
C<postfilterctl query --ip> and C<--user> work in plain, HMAC and encrypted
storage modes.

=cut

# Function: identity_lookup
# Purpose: Exposes the stable indexed identity token to trusted administrative callers.
# Parameters: $self, $purpose, $value
# Operational notes: The returned token is suitable only for equality lookup; it is not the
#                    display value stored in the public columns.
sub identity_lookup {
    my ($self, $purpose, $value) = @_;

    return $self->_identity_lookup($purpose, $value);
}

=head2 reveal_identity($purpose, $stored_value)

Returns a human-readable identity for local administrative tools.  Plain values
are returned unchanged, encrypted values are authenticated and decrypted with
the dedicated database key, and HMAC values remain pseudonyms because they are
intentionally irreversible.

=cut

# Function: reveal_identity
# Purpose: Converts a stored identity into the most readable form permitted by its storage mode.
# Parameters: $self, $purpose, $stored_value, $storage_mode
# Operational notes: Authentication failure is fatal to the caller; silently displaying corrupted
#                    ciphertext would make legal-history queries unreliable.
sub reveal_identity {
    my ($self, $purpose, $stored_value, $storage_mode) = @_;
    $stored_value //= '';

    my $mode = $storage_mode
        // $self->{config}{database}{privacy}{identity_mode}
        // 'plain';

    return $stored_value if $mode eq 'plain' || $mode eq 'hmac';
    return '' if $stored_value eq '';

    my $key = $self->_database_privacy_key;
    return $self->{crypto}->decrypt_token(
        $stored_value,
        $key,
        "database-$purpose",
    );
}

# Function: _identity_lookup
# Purpose: Creates the stable hidden HMAC lookup key used by rate limits in every privacy mode.
# Parameters: $self, $purpose, $value
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _identity_lookup {
    my ($self, $purpose, $value) = @_;
    $value //= '';

    # Lookup tokens deliberately use the dedicated secret in every storage
    # mode.  This keeps equality searches and rate-limit history stable if an
    # administrator later changes storage from plain to encrypted or HMAC.
    my $key = $self->_database_privacy_key;
    return 'h1:' . $self->{crypto}->pseudonym(
        "$purpose\0$value",
        $key,
        64,
    );
}

# Function: _database_privacy_key
# Purpose: Loads and caches the dedicated database privacy key without using any fallback secret.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub _database_privacy_key {
    my ($self) = @_;

    my $path =
        $self->{config}{database}{privacy}{key_file}
        // $self->{config}{keys}{database_privacy};

    return $self->{crypto}->load_key($path);
}

# Function: disconnect
# Purpose: Closes the process-local SQLite handle and clears it for safe reuse.
# Parameters: $self
# Operational notes: Failure behaviour is explicit in the function body and follows the caller’s
#                    configured fail-open/fail-closed policy.
sub disconnect {
    my ($self) = @_;

    if ($self->{dbh}) {
        eval { $self->{dbh}->disconnect };
        $self->{dbh} = undef;
    }

    return;
}

1;
