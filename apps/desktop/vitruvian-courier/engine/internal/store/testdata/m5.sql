-- Copyright 2026 VitruvianSoftware
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- A courier.db as milestone 4.2 left it: the milestone-2 baseline (schema.sql, copied verbatim below) with the
-- schema of migrations 1 to 4 as they shipped, so user_version is 4, plus dummy data on two networks. All names and
-- text are made up. The search tables are empty and search_state covers every row, as if 4.2 upgraded this data and
-- quit before its backfill ran. TestMigrationFromMilestone4_2 opens this and checks that Open upgrades it to
-- migration 5.

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
ALTER TABLE room_prefs ADD COLUMN pinned_at INTEGER NOT NULL DEFAULT 0;     -- 0 = not pinned; pin order is pinned_at
ALTER TABLE room_prefs ADD COLUMN archived_at INTEGER NOT NULL DEFAULT 0;   -- 0 = not archived
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


-- Migration 4, as it shipped (its one-off repair of earlier redactions left out: the rows below need none).
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

PRAGMA user_version = 4;

INSERT INTO rooms (room_id, network, name, is_direct, created_at, last_ts, last_event_id, request) VALUES
  ('!pat:courier.local',  'whatsapp', 'Pat Example',  1, 1790000000000, 1792540900000, '$a10', 0),
  ('!team:courier.local', 'slack',    'Release team', 0, 1790000001000, 1790812824000, '$s5', 0);

INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq, redacted) VALUES
  ('$a0',  '!pat:courier.local', '@ghost1:courier.local', 'm.room.name', '', '{"name":"Pat Example"}', 1790812800000, '', '', 1, 0),
  ('$a1',  '!pat:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"the market opens at nine"}', 1790812801000, '', '', 2, 0),
  -- A text message and my edit of it that went out.
  ('$a2',  '!pat:courier.local', '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"meet at noon"}', 1790812802000, 'sent', '', 3, 0),
  ('$a3',  '!pat:courier.local', '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"* meet at five","m.new_content":{"msgtype":"m.text","body":"meet at five"},"m.relates_to":{"rel_type":"m.replace","event_id":"$a2"}}', 1790812803000, 'sent', '', 4, 0),
  -- A message and my edit of it that the network refused.
  ('$a4',  '!pat:courier.local', '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"see you soon"}', 1790812804000, 'sent', '', 5, 0),
  ('$a5',  '!pat:courier.local', '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"* see you later","m.new_content":{"msgtype":"m.text","body":"see you later"},"m.relates_to":{"rel_type":"m.replace","event_id":"$a4"}}', 1790812805000, 'failed', 'refused', 6, 0),
  -- A deleted message and its redaction.
  ('$a6',  '!pat:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"wrong photo"}', 1790812806000, '', '', 7, 1),
  ('$a7',  '!pat:courier.local', '@ghost1:courier.local', 'm.room.redaction', NULL, '{"redacts":"$a6"}', 1790812807000, '', '', 8, 0),
  -- Disappearing after sending, 24 hours: long past its time.
  ('$a8',  '!pat:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"gone by tomorrow","com.beeper.disappearing_timer":{"type":"after_send","timer":86400000}}', 1790812808000, '', '', 9, 0),
  -- A poll (extensible events shape) with two votes from one person: the newer one counts.
  ('$a11', '!pat:courier.local', '@ghost1:courier.local', 'org.matrix.msc3381.poll.start', NULL, '{"org.matrix.msc1767.text":"Lunch where?\n1. tacos\n2. noodles","org.matrix.msc3381.poll.start":{"kind":"org.matrix.msc3381.poll.disclosed","max_selections":1,"question":{"org.matrix.msc1767.text":"Lunch where?"},"answers":[{"id":"a","org.matrix.msc1767.text":"tacos"},{"id":"b","org.matrix.msc1767.text":"noodles"}]}}', 1790812809000, '', '', 10, 0),
  ('$a12', '!pat:courier.local', '@ghost1:courier.local', 'org.matrix.msc3381.poll.response', NULL, '{"org.matrix.msc3381.poll.response":{"answers":["a"]},"m.relates_to":{"rel_type":"m.reference","event_id":"$a11"}}', 1790812810000, '', '', 11, 0),
  ('$a13', '!pat:courier.local', '@ghost1:courier.local', 'org.matrix.msc3381.poll.response', NULL, '{"org.matrix.msc3381.poll.response":{"answers":["b"]},"m.relates_to":{"rel_type":"m.reference","event_id":"$a11"}}', 1790812811000, '', '', 12, 0),
  -- Disappearing after sending, 90 days: its time is still to come.
  ('$a9',  '!pat:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"here for a season","com.beeper.disappearing_timer":{"type":"after_send","timer":7776000000}}', 1792540800000, '', '', 13, 0),
  -- Disappearing after reading: no time of its own.
  ('$a10', '!pat:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"read me once","com.beeper.disappearing_timer":{"type":"after_read","timer":30000}}', 1792540900000, '', '', 14, 0),
  -- A Slack thread: its root, two replies in the thread and one also sent to the channel.
  ('$s1',  '!team:courier.local', '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"release notes draft"}', 1790812820000, '', '', 15, 0),
  ('$s2',  '!team:courier.local', '@ghost3:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"looks good","m.relates_to":{"rel_type":"m.thread","event_id":"$s1","is_falling_back":true,"m.in_reply_to":{"event_id":"$s1"}}}', 1790812821000, '', '', 16, 0),
  ('$s3',  '!team:courier.local', '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"shipping friday","m.relates_to":{"rel_type":"m.thread","event_id":"$s1","is_falling_back":true,"m.in_reply_to":{"event_id":"$s1"}}}', 1790812822000, 'sent', '', 17, 0),
  ('$s4',  '!team:courier.local', '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"posted to the channel too","com.beeper.broadcast_outside_thread":true,"m.relates_to":{"rel_type":"m.thread","event_id":"$s1","is_falling_back":true,"m.in_reply_to":{"event_id":"$s1"}}}', 1790812823000, '', '', 18, 0),
  ('$s5',  '!team:courier.local', '@ghost3:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"standup moved"}', 1790812824000, '', '', 19, 0),
  ('$s6',  '!team:courier.local', '@ghost2:courier.local', 'm.reaction', NULL, '{"m.relates_to":{"rel_type":"m.annotation","event_id":"$s1","key":"+1"}}', 1790812825000, '', '', 20, 0);

INSERT INTO profiles (user_id, display_name) VALUES ('@ghost1:courier.local', 'Pat Example'), ('@ghost2:courier.local', 'Sam Placeholder');
INSERT INTO members (room_id, user_id, content) VALUES
  ('!pat:courier.local',  '@ghost1:courier.local', '{"membership":"join"}'),
  ('!team:courier.local', '@ghost2:courier.local', '{"membership":"join","displayname":"Sam Placeholder"}'),
  ('!team:courier.local', '@ghost3:courier.local', '{"membership":"join","displayname":"Lee Sample"}'),
  ('!team:courier.local', '@me:courier.local',     '{"membership":"join"}');
INSERT INTO room_prefs (room_id, muted) VALUES ('!team:courier.local', 1);

-- Migration 4's backfill cursors, over every row above.
INSERT INTO search_state VALUES ('backfill_until', (SELECT COALESCE(MAX(rowid), 0) FROM events)), ('backfill_after', 0),
  ('chats_until', (SELECT COALESCE(MAX(rowid), 0) FROM rooms)), ('chats_after', 0),
  ('profiles_until', (SELECT COALESCE(MAX(rowid), 0) FROM profiles)), ('profiles_after', 0),
  ('members_until', (SELECT COALESCE(MAX(rowid), 0) FROM members)), ('members_after', 0);
