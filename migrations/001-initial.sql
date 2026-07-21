-- Postfilter-NG initial SQLite schema.
--
-- This file is the readable SQL counterpart of Postfilter::Database::migrate.
-- The Perl code executes the same statements so installation does not need the
-- sqlite3 command-line program.  Article events and rule hits deliberately have
-- no expiry column or automatic deletion trigger: they replace legal.log and
-- are retained until an administrator performs an explicit audited purge.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations(
    version INTEGER PRIMARY KEY,
    applied_at INTEGER NOT NULL
);

CREATE TABLE article_events(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    received_at REAL NOT NULL,
    message_id TEXT,
    message_id_hash TEXT,
    article_digest TEXT,
    client_ip TEXT,
    client_domain TEXT,
    auth_user TEXT,
    from_address TEXT,
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
);

CREATE INDEX article_events_received_idx
    ON article_events(received_at);
CREATE INDEX article_events_ip_time_idx
    ON article_events(client_ip, received_at);
CREATE INDEX article_events_domain_time_idx
    ON article_events(client_domain, received_at);
CREATE INDEX article_events_user_time_idx
    ON article_events(auth_user, received_at);
CREATE INDEX article_events_digest_time_idx
    ON article_events(article_digest, received_at);
CREATE INDEX article_events_reason_time_idx
    ON article_events(reason_code, received_at);
CREATE INDEX article_events_message_id_idx
    ON article_events(message_id);

CREATE TABLE rule_hits(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER NOT NULL,
    rule_id TEXT NOT NULL,
    target TEXT,
    score REAL DEFAULT 0,
    action TEXT,
    details TEXT,
    FOREIGN KEY(event_id) REFERENCES article_events(id) ON DELETE CASCADE
);
CREATE INDEX rule_hits_rule_idx ON rule_hits(rule_id, event_id);

CREATE TABLE saved_articles(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER,
    path TEXT NOT NULL UNIQUE,
    file_sha256 TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    created_at REAL NOT NULL,
    FOREIGN KEY(event_id) REFERENCES article_events(id) ON DELETE SET NULL
);

CREATE TABLE local_distribution(
    message_id TEXT PRIMARY KEY,
    created_at REAL NOT NULL
);
CREATE INDEX local_distribution_time_idx
    ON local_distribution(created_at);

CREATE TABLE provider_health(
    provider_id TEXT PRIMARY KEY,
    provider_type TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'healthy',
    failures INTEGER NOT NULL DEFAULT 0,
    last_failure_at REAL,
    cooldown_until REAL,
    last_error TEXT,
    last_success_at REAL
);

CREATE TABLE configuration_generations(
    generation TEXT PRIMARY KEY,
    loaded_at REAL NOT NULL,
    origin TEXT,
    warnings INTEGER NOT NULL DEFAULT 0
);


INSERT INTO schema_migrations(version, applied_at)
VALUES(1, strftime('%s', 'now'));
