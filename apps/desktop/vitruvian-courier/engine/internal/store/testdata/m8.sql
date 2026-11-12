-- Copyright 2026 VitruvianSoftware
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- A courier.db as milestone 4.4 left it: the milestone-2 baseline (schema.sql, copied verbatim below) with the
-- schema of migrations 1 to 7 as they shipped, so user_version is 7, plus a room !r1:courier.local, profile
-- @u1:courier.local, room_prefs row, and receipts/deliveries/login_state rows from 4.4. All names and text are
-- made up. TestMigrationFromMilestone4_4 opens this and checks that Open upgrades it to migration 8.

CREATE TABLE IF NOT EXISTS rooms (
  room_id TEXT PRIMARY KEY, network TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', topic TEXT NOT NULL DEFAULT '',
  avatar_uri TEXT NOT NULL DEFAULT '', is_direct INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS members (
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, user_id TEXT NOT NULL, content TEXT NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
CREATE TABLE IF NOT EXISTS state (
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, type TEXT NOT NULL, state_key TEXT NOT NULL, content TEXT NOT NULL,
  PRIMARY KEY (room_id, type, state_key)
);
CREATE TABLE IF NOT EXISTS events (
  event_id TEXT PRIMARY KEY, room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, sender TEXT NOT NULL,
  type TEXT NOT NULL, state_key TEXT, content TEXT NOT NULL, ts INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT '', status_reason TEXT NOT NULL DEFAULT '', seq INTEGER NOT NULL
);
DROP INDEX IF EXISTS events_room_seq;
CREATE INDEX IF NOT EXISTS events_room_ts ON events(room_id, ts DESC, seq DESC);
CREATE TABLE IF NOT EXISTS reads (room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE, event_id TEXT NOT NULL, ts INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS bridge_state (network TEXT PRIMARY KEY, state TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS profiles (
  user_id TEXT PRIMARY KEY, display_name TEXT NOT NULL DEFAULT '', avatar_uri TEXT NOT NULL DEFAULT ''
);

-- Migration 1, as it shipped.
ALTER TABLE rooms ADD COLUMN last_ts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE rooms ADD COLUMN last_event_id TEXT NOT NULL DEFAULT '';
CREATE TABLE room_prefs (
  room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE,
  muted INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE local_reads (
  room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  ts INTEGER NOT NULL
);
CREATE INDEX rooms_last_ts ON rooms(last_ts DESC, created_at DESC);

-- Migration 2, as it shipped.
ALTER TABLE events ADD COLUMN redacted INTEGER NOT NULL DEFAULT 0;

-- Migration 3, as it shipped.
ALTER TABLE rooms ADD COLUMN request INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN pinned_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN archived_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN low_priority INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN marked_unread INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN draft TEXT NOT NULL DEFAULT '';
CREATE INDEX room_prefs_place ON room_prefs(hidden, low_priority, archived_at);
CREATE TABLE labels (label_id INTEGER PRIMARY KEY, title TEXT NOT NULL, color INTEGER NOT NULL, icon TEXT NOT NULL,
  muted INTEGER NOT NULL DEFAULT 0, show_in_inbox TEXT NOT NULL DEFAULT 'all', created_at INTEGER NOT NULL);
CREATE TABLE room_labels (room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,
  label_id INTEGER NOT NULL REFERENCES labels(label_id) ON DELETE CASCADE, PRIMARY KEY (room_id, label_id));
CREATE INDEX room_labels_label ON room_labels(label_id);
CREATE TABLE account_prefs (network TEXT PRIMARY KEY, muted INTEGER NOT NULL DEFAULT 0, show_in_inbox TEXT NOT NULL DEFAULT 'all');
CREATE TABLE space_layout (space_id TEXT PRIMARY KEY, position INTEGER NOT NULL, hidden INTEGER NOT NULL DEFAULT 0);
CREATE TABLE reminders (room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE, due_at INTEGER NOT NULL,
  condition TEXT NOT NULL, set_at INTEGER NOT NULL, fired_at INTEGER NOT NULL DEFAULT 0);
CREATE INDEX reminders_due ON reminders(fired_at, due_at);
CREATE TABLE auto_archive_rules (rule_id INTEGER PRIMARY KEY, scope TEXT NOT NULL, trigger TEXT NOT NULL,
  chat_type TEXT NOT NULL DEFAULT 'all', duration_ms INTEGER NOT NULL, enabled INTEGER NOT NULL DEFAULT 1);
CREATE TABLE archive_due (room_id TEXT PRIMARY KEY REFERENCES rooms(room_id) ON DELETE CASCADE, due_at INTEGER NOT NULL,
  rule_id INTEGER NOT NULL REFERENCES auto_archive_rules(rule_id) ON DELETE CASCADE);

-- Migration 4, as it shipped.
ALTER TABLE events ADD COLUMN doc_id INTEGER;
CREATE UNIQUE INDEX events_doc ON events(doc_id) WHERE doc_id IS NOT NULL;
CREATE INDEX events_edits ON events((CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".event_id') END), ts) WHERE type = 'm.room.message' AND (CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".rel_type') END) = 'm.replace';
CREATE INDEX members_user ON members(user_id);
CREATE INDEX events_redacts ON events((CASE WHEN json_valid(content) THEN json_extract(content, '$.redacts') END)) WHERE type = 'm.room.redaction';
CREATE VIRTUAL TABLE search_messages USING fts5(body, scope, content='', contentless_delete=1, tokenize="unicode61 remove_diacritics 2 categories 'L* N* Co M*'");
CREATE TABLE chat_docs (doc_id INTEGER PRIMARY KEY, room_id TEXT NOT NULL UNIQUE REFERENCES rooms(room_id) ON DELETE CASCADE);
CREATE VIRTUAL TABLE search_chats USING fts5(name, scope, content='', contentless_delete=1, tokenize="unicode61 remove_diacritics 2 categories 'L* N* Co M*'");
CREATE TABLE people_docs (doc_id INTEGER PRIMARY KEY, user_id TEXT NOT NULL UNIQUE);
CREATE VIRTUAL TABLE search_people USING fts5(name, scope, content='', contentless_delete=1, tokenize="unicode61 remove_diacritics 2 categories 'L* N* Co M*'");
CREATE TABLE search_state (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
CREATE TRIGGER events_unindex AFTER DELETE ON events WHEN old.doc_id IS NOT NULL
  BEGIN DELETE FROM search_messages WHERE rowid = old.doc_id; END;
CREATE TRIGGER events_unindex_redacted AFTER UPDATE OF redacted ON events WHEN new.redacted = 1 AND old.doc_id IS NOT NULL
  BEGIN DELETE FROM search_messages WHERE rowid = old.doc_id; UPDATE events SET doc_id = NULL WHERE event_id = new.event_id; END;
CREATE TRIGGER chat_docs_unindex AFTER DELETE ON chat_docs BEGIN DELETE FROM search_chats WHERE rowid = old.doc_id; END;
CREATE TRIGGER people_docs_unindex AFTER DELETE ON people_docs BEGIN DELETE FROM search_people WHERE rowid = old.doc_id; END;

-- Migration 5, as it shipped.
ALTER TABLE events ADD COLUMN deleted_for_me INTEGER NOT NULL DEFAULT 0;
ALTER TABLE events ADD COLUMN expires_at INTEGER;
CREATE INDEX events_expiry ON events(expires_at) WHERE expires_at IS NOT NULL AND redacted = 0;
CREATE INDEX events_refs ON events((CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".event_id') END), ts)
  WHERE type IN ('org.matrix.msc3381.poll.response', 'org.matrix.msc3381.poll.end');
CREATE INDEX events_threads ON events(room_id, (CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".event_id') END), ts DESC, seq DESC)
  WHERE type IN ('m.room.message', 'm.sticker') AND (CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".rel_type') = 'm.thread' END);
CREATE INDEX events_reactions ON events((CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".event_id') END), ts) WHERE type = 'm.reaction';
CREATE INDEX events_timer_notes ON events(room_id, seq) WHERE type = 'm.room.message' AND (CASE WHEN json_valid(content) THEN json_extract(content, '$."com.beeper.action_message".type') END) = 'disappearing_timer';
CREATE TABLE outbox (outbox_id INTEGER PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  event_id TEXT NOT NULL UNIQUE,
  type TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '',
  due_at INTEGER NOT NULL, set_at INTEGER NOT NULL,
  condition TEXT NOT NULL DEFAULT 'always',
  state TEXT NOT NULL DEFAULT 'waiting');
CREATE INDEX outbox_due ON outbox(state, due_at);
CREATE INDEX outbox_room ON outbox(room_id, kind);
CREATE TABLE bookmarks (event_id TEXT PRIMARY KEY REFERENCES events(event_id) ON DELETE CASCADE,
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, created_at INTEGER NOT NULL);
CREATE INDEX bookmarks_new ON bookmarks(created_at DESC);

-- Migration 7, as it shipped.
CREATE TABLE receipts (room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, user_id TEXT NOT NULL,
  event_id TEXT NOT NULL, ts INTEGER NOT NULL, PRIMARY KEY (room_id, user_id));
CREATE TABLE deliveries (event_id TEXT NOT NULL REFERENCES events(event_id) ON DELETE CASCADE, user_id TEXT NOT NULL,
  ts INTEGER NOT NULL, PRIMARY KEY (event_id, user_id));
ALTER TABLE room_prefs ADD COLUMN unread_from_ts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE room_prefs ADD COLUMN unread_from_seq INTEGER NOT NULL DEFAULT 0;
ALTER TABLE rooms ADD COLUMN login_id TEXT NOT NULL DEFAULT '';
CREATE TABLE login_state (network TEXT NOT NULL, login_id TEXT NOT NULL, state TEXT NOT NULL,
  PRIMARY KEY (network, login_id));

PRAGMA user_version = 7;

INSERT INTO rooms (room_id, network, name, topic, avatar_uri, is_direct, created_at, last_ts, last_event_id, request, login_id) VALUES
  ('!r1:courier.local', 'whatsapp', 'Alice Example', '', 'mxc://courier.local/alice', 1, 1790000000000, 1790812802000, '$e2', 0, 'login-a');

INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq) VALUES
  ('$e1', '!r1:courier.local', '@u1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"morning"}', 1790812801000, '', '', 1),
  ('$e2', '!r1:courier.local', '@me:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"hello there"}', 1790812802000, 'sent', '', 2);

INSERT INTO profiles (user_id, display_name, avatar_uri) VALUES
  ('@u1:courier.local', 'Alice Example', 'mxc://courier.local/alice');

INSERT INTO members (room_id, user_id, content) VALUES
  ('!r1:courier.local', '@u1:courier.local', '{"membership":"join","displayname":"Alice Example"}'),
  ('!r1:courier.local', '@me:courier.local', '{"membership":"join"}');

INSERT INTO room_prefs (room_id, muted, marked_unread) VALUES
  ('!r1:courier.local', 0, 1);

INSERT INTO receipts (room_id, user_id, event_id, ts) VALUES
  ('!r1:courier.local', '@u1:courier.local', '$e2', 1790812803000);

INSERT INTO deliveries (event_id, user_id, ts) VALUES
  ('$e2', '@u1:courier.local', 1790812802500);

INSERT INTO login_state (network, login_id, state) VALUES
  ('whatsapp', 'login-a', '{"state_event":"CONNECTED","timestamp":1790812900,"ttl":3600,"remote_id":"login-a","remote_name":"Test Account"}');

INSERT INTO search_state VALUES ('backfill_until', (SELECT COALESCE(MAX(rowid), 0) FROM events)), ('backfill_after', 0),
  ('chats_until', (SELECT COALESCE(MAX(rowid), 0) FROM rooms)), ('chats_after', 0),
  ('profiles_until', (SELECT COALESCE(MAX(rowid), 0) FROM profiles)), ('profiles_after', 0),
  ('members_until', (SELECT COALESCE(MAX(rowid), 0) FROM members)), ('members_after', 0);
