-- Record the privacy mode used for each event identity.
--
-- The active database privacy mode can change over a multi-year archive.  A
-- per-row mode allows postfilterctl and the HTML report to decode old encrypted
-- values correctly after such a change. Existing rows without per-event mode
-- metadata receive the plain storage mode.

ALTER TABLE article_events
    ADD COLUMN identity_storage_mode TEXT NOT NULL DEFAULT 'plain';

INSERT INTO schema_migrations(version, applied_at)
VALUES(3, strftime('%s', 'now'));
