-- Add text/binary classification to long-term event history.
--
-- Existing rows receive text during migration. New events store text or binary
-- explicitly, allowing reports,
-- rate counters, debugging and legal queries to keep the two worlds separate.

ALTER TABLE article_events
    ADD COLUMN article_type TEXT NOT NULL DEFAULT 'text';

ALTER TABLE saved_articles
    ADD COLUMN article_type TEXT NOT NULL DEFAULT 'text';

CREATE INDEX IF NOT EXISTS article_events_type_time_idx
    ON article_events(article_type, received_at);

CREATE INDEX IF NOT EXISTS saved_articles_type_time_idx
    ON saved_articles(article_type, created_at);

INSERT INTO schema_migrations(version, applied_at)
VALUES(4, strftime('%s', 'now'));
