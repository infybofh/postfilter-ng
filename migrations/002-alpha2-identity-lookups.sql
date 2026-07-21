-- Upgrade reference for databases created by 2026.07.1-alpha1.
--
-- This file is applied after 001-initial.sql by packaging tools that execute
-- the readable SQL migrations directly.  Postfilter::Database performs the same
-- upgrade programmatically and inspects PRAGMA table_info before ALTER TABLE so
-- an interrupted or partially upgraded database remains recoverable.

ALTER TABLE article_events ADD COLUMN client_ip_lookup TEXT;
ALTER TABLE article_events ADD COLUMN client_domain_lookup TEXT;
ALTER TABLE article_events ADD COLUMN auth_user_lookup TEXT;
ALTER TABLE article_events ADD COLUMN from_address_lookup TEXT;

DROP INDEX IF EXISTS article_events_ip_time_idx;
DROP INDEX IF EXISTS article_events_domain_time_idx;
DROP INDEX IF EXISTS article_events_user_time_idx;

CREATE INDEX article_events_ip_time_idx
    ON article_events(client_ip_lookup, received_at);
CREATE INDEX article_events_domain_time_idx
    ON article_events(client_domain_lookup, received_at);
CREATE INDEX article_events_user_time_idx
    ON article_events(auth_user_lookup, received_at);
CREATE INDEX article_events_from_lookup_time_idx
    ON article_events(from_address_lookup, received_at);

CREATE TABLE IF NOT EXISTS administrative_actions(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    performed_at REAL NOT NULL,
    operating_user TEXT,
    command TEXT NOT NULL,
    parameters_json TEXT,
    affected_rows INTEGER,
    note TEXT
);

INSERT INTO schema_migrations(version, applied_at)
VALUES(2, strftime('%s', 'now'));
