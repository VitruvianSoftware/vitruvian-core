-- Copyright 2026 VitruvianSoftware
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- A courier.db as milestone 4.1 left it: the milestone-2 baseline (schema.sql, copied verbatim below) with
-- migrations 1, 2 and 3 applied as they shipped, so user_version is 3, plus dummy data on two networks. All names
-- and text are made up. TestMigrationFromMilestone4_1 opens this and checks that Open upgrades it to migration 4.

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

PRAGMA user_version = 3;

INSERT INTO rooms (room_id, network, name, is_direct, created_at, last_ts, last_event_id, request) VALUES
  ('!garden:courier.local', 'whatsapp', 'Garden club', 0, 1000, 205000, '$g14', 0),
  ('!pat:courier.local',    'whatsapp', 'Pat Example', 1, 2000, 150000, '$p4', 0),
  ('!trip:courier.local',   'telegram', 'Trip planning', 0, 3000, 180000, '$t5', 0);

INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq, redacted) VALUES
  ('$g1',  '!garden:courier.local', '@ghost1:courier.local', 'm.room.name', '', '{"name":"Garden club"}', 10000, '', '', 1, 0),
  ('$g2',  '!garden:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"tomatoes are ripe"}', 20000, '', '', 2, 0),
  ('$g3',  '!garden:courier.local', '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.image","body":"the new raised bed","url":"mxc://courier.local/bed"}', 30000, '', '', 3, 0),
  ('$g4',  '!garden:courier.local', '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"> <@ghost2:courier.local> the new raised bed\n\nlooks great","m.relates_to":{"m.in_reply_to":{"event_id":"$g3"}}}', 40000, 'sent', '', 4, 0),
  ('$g5',  '!garden:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"water at noon"}', 50000, '', '', 5, 0),
  ('$g6',  '!garden:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"* water at five","m.new_content":{"msgtype":"m.text","body":"water at five"},"m.relates_to":{"rel_type":"m.replace","event_id":"$g5"}}', 60000, '', '', 6, 0),
  ('$g7',  '!garden:courier.local', '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"wrong chat sorry"}', 70000, '', '', 7, 1),
  ('$g8',  '!garden:courier.local', '@ghost2:courier.local', 'm.room.redaction', NULL, '{"redacts":"$g7"}', 80000, '', '', 8, 0),
  ('$g9',  '!garden:courier.local', '@me:courier.local',     'm.reaction', NULL, '{"m.relates_to":{"rel_type":"m.annotation","event_id":"$g2","key":"+1"}}', 90000, 'sent', '', 9, 0),
  ('$g10', '!garden:courier.local', '@ghost1:courier.local', 'm.room.encrypted', NULL, '{"algorithm":"m.megolm.v1.aes-sha2","ciphertext":"AAAA"}', 100000, '', '', 10, 0),
  ('$g11', '!garden:courier.local', '@ghost2:courier.local', 'm.sticker', NULL, '{"body":"waving cat","url":"mxc://courier.local/cat"}', 110000, '', '', 11, 0),
  ('$g12', '!garden:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.notice","body":"see https://example.com/seeds"}', 200000, '', '', 12, 0),
  ('$p1',  '!pat:courier.local',    '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"are you free saturday"}', 120000, '', '', 13, 0),
  ('$p2',  '!pat:courier.local',    '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"yes after lunch"}', 130000, 'sent', '', 14, 0),
  ('$p3',  '!pat:courier.local',    '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.file","body":"directions.pdf","url":"mxc://courier.local/pdf"}', 140000, '', '', 15, 0),
  ('$p4',  '!pat:courier.local',    '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"東京タワーで会いましょう"}', 150000, '', '', 16, 0),
  ('$t1',  '!trip:courier.local',   '@ghost3:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"train leaves at seven"}', 150500, '', '', 17, 0),
  ('$t2',  '!trip:courier.local',   '@ghost3:courier.local', 'm.room.message', NULL, '{"msgtype":"m.video","body":"platform.mp4","url":"mxc://courier.local/vid"}', 160000, '', '', 18, 0),
  ('$t3',  '!trip:courier.local',   '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.audio","body":"voice note","url":"mxc://courier.local/ogg"}', 170000, 'sent', '', 19, 0),
  ('$t4',  '!trip:courier.local',   '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.emote","body":"waves goodbye"}', 175000, 'failed', 'network down', 20, 0),
  ('$t5',  '!trip:courier.local',   '@ghost3:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"see you there"}', 180000, '', '', 21, 0),
  -- A redaction that arrived before its message: 4.1 never marked the message, so it is still the chat's latest.
  ('$g13', '!garden:courier.local', '@ghost1:courier.local', 'm.room.redaction', NULL, '{"redacts":"$g14"}', 210000, '', '', 22, 0),
  ('$g14', '!garden:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"posted by mistake"}', 205000, '', '', 23, 0);

INSERT INTO profiles (user_id, display_name) VALUES ('@ghost1:courier.local', 'Pat Example'), ('@ghost3:courier.local', 'Lee Sample');
INSERT INTO members (room_id, user_id, content) VALUES
  ('!garden:courier.local', '@ghost1:courier.local', '{"membership":"join","displayname":"Pat in garden"}'),
  ('!garden:courier.local', '@ghost2:courier.local', '{"membership":"join","displayname":"Robin Placeholder"}'),
  ('!garden:courier.local', '@me:courier.local',     '{"membership":"join"}'),
  ('!pat:courier.local',    '@ghost1:courier.local', '{"membership":"join"}'),
  ('!trip:courier.local',   '@ghost3:courier.local', '{"membership":"join"}');
INSERT INTO room_prefs (room_id, muted, archived_at) VALUES ('!trip:courier.local', 1, 0), ('!pat:courier.local', 0, 190000);
INSERT INTO local_reads (room_id, event_id, ts) VALUES ('!garden:courier.local', '$g5', 50000);
