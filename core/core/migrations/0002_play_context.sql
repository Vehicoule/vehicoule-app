-- The album, playlist or artist a play was started from (home shortcuts).
ALTER TABLE plays ADD COLUMN context_id BLOB REFERENCES items(id);
CREATE INDEX plays_context ON plays(context_id, started_at DESC) WHERE context_id IS NOT NULL;
-- Membership lookups of the library's "latest play" sort.
CREATE INDEX music_tracks_album ON music_tracks(album_id) WHERE album_id IS NOT NULL;
CREATE INDEX music_track_artists_artist ON music_track_artists(artist_id);
