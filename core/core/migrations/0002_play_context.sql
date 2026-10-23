-- The album, playlist or artist a play was started from (home shortcuts).
ALTER TABLE plays ADD COLUMN context_id BLOB REFERENCES items(id);
CREATE INDEX plays_context ON plays(context_id, started_at DESC) WHERE context_id IS NOT NULL;
