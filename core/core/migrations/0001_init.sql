-- ids: UUIDv7 BLOB(16). Wall times: unix ms. updated_at: HLC.
CREATE TABLE items (
  id BLOB PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL,
  merged_into BLOB REFERENCES items(id),
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE INDEX items_merged ON items(merged_into) WHERE merged_into IS NOT NULL;

CREATE TABLE music_tracks (item_id BLOB PRIMARY KEY REFERENCES items(id),
  album_id BLOB REFERENCES items(id), duration_ms INTEGER, isrc TEXT, explicit INTEGER NOT NULL DEFAULT 0);
CREATE INDEX music_tracks_isrc ON music_tracks(isrc) WHERE isrc IS NOT NULL;
CREATE TABLE music_track_artists (track_id BLOB NOT NULL REFERENCES items(id),
  artist_id BLOB NOT NULL REFERENCES items(id), position INTEGER NOT NULL, PRIMARY KEY (track_id, position));
CREATE TABLE music_albums (item_id BLOB PRIMARY KEY REFERENCES items(id), year INTEGER, track_count INTEGER);
CREATE TABLE music_album_artists (album_id BLOB NOT NULL REFERENCES items(id),
  artist_id BLOB NOT NULL REFERENCES items(id), position INTEGER NOT NULL, PRIMARY KEY (album_id, position));
CREATE TABLE music_album_tracks (album_id BLOB NOT NULL REFERENCES items(id),
  track_id BLOB NOT NULL REFERENCES items(id), position INTEGER NOT NULL, PRIMARY KEY (album_id, position));
CREATE TABLE music_artists (item_id BLOB PRIMARY KEY REFERENCES items(id));
-- Provider playlists (editorial cache). User playlists live in `playlists`.
CREATE TABLE music_playlists (item_id BLOB PRIMARY KEY REFERENCES items(id),
  owner TEXT, description TEXT, track_count INTEGER);
CREATE TABLE music_playlist_tracks (playlist_id BLOB NOT NULL REFERENCES items(id),
  track_id BLOB NOT NULL REFERENCES items(id), position INTEGER NOT NULL, PRIMARY KEY (playlist_id, position));
CREATE TABLE artwork (item_id BLOB NOT NULL REFERENCES items(id), provider TEXT NOT NULL,
  url TEXT NOT NULL, width INTEGER, PRIMARY KEY (item_id, provider, url));

CREATE TABLE external_refs (item_id BLOB NOT NULL REFERENCES items(id), provider TEXT NOT NULL,
  external_id TEXT NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (item_id, provider, external_id));
CREATE INDEX external_refs_lookup ON external_refs(provider, external_id);

CREATE TABLE likes (item_id BLOB PRIMARY KEY REFERENCES items(id), liked_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE TABLE playlists (item_id BLOB PRIMARY KEY REFERENCES items(id), description TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE TABLE playlist_items (id BLOB PRIMARY KEY, playlist_id BLOB NOT NULL REFERENCES items(id),
  item_id BLOB NOT NULL REFERENCES items(id), order_key TEXT NOT NULL, added_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE INDEX playlist_items_order ON playlist_items(playlist_id, order_key, id);
CREATE TABLE plays (id BLOB PRIMARY KEY, item_id BLOB NOT NULL REFERENCES items(id),
  started_at INTEGER NOT NULL, listened_ms INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL,
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE INDEX plays_recent ON plays(started_at DESC);
CREATE TABLE downloads (item_id BLOB PRIMARY KEY REFERENCES items(id), state TEXT NOT NULL,
  path TEXT, quality TEXT NOT NULL, mime TEXT, loudness_db REAL, bytes_total INTEGER,
  bytes_done INTEGER NOT NULL DEFAULT 0, error TEXT, created_at INTEGER NOT NULL, finished_at INTEGER);
CREATE TABLE queue_state (id INTEGER PRIMARY KEY CHECK (id = 1), state TEXT NOT NULL);
CREATE TABLE lyrics (item_id BLOB PRIMARY KEY REFERENCES items(id), provider TEXT NOT NULL,
  plain TEXT, synced TEXT, fetched_at INTEGER NOT NULL);
CREATE TABLE plugin_kv (plugin_id TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY (plugin_id, key));
CREATE TABLE search_history (query TEXT PRIMARY KEY, used_at INTEGER NOT NULL);
CREATE TABLE http_cache (key BLOB PRIMARY KEY, plugin_id TEXT NOT NULL, status INTEGER NOT NULL,
  url TEXT NOT NULL, headers TEXT NOT NULL, body BLOB NOT NULL, stored_at INTEGER NOT NULL, expires_at INTEGER NOT NULL);
CREATE TABLE settings_device (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE settings_shared (key TEXT PRIMARY KEY, value TEXT NOT NULL,
  updated_at INTEGER NOT NULL, device_id BLOB NOT NULL, deleted_at INTEGER);
CREATE TABLE feeds (url TEXT PRIMARY KEY, name TEXT NOT NULL, public_keys TEXT NOT NULL,
  official INTEGER NOT NULL, last_sequence INTEGER, fetched_at INTEGER, feed BLOB);
CREATE TABLE plugins (id TEXT PRIMARY KEY, feed_url TEXT NOT NULL REFERENCES feeds(url),
  version TEXT NOT NULL, manifest BLOB NOT NULL, wasm_sha256 TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1, installed_at INTEGER NOT NULL);
CREATE TABLE capability_order (capability TEXT NOT NULL, plugin_id TEXT NOT NULL,
  position INTEGER NOT NULL, PRIMARY KEY (capability, plugin_id));
CREATE VIRTUAL TABLE library_fts USING fts5(item_id UNINDEXED, title, subtitle,
  tokenize = 'trigram remove_diacritics 1');
