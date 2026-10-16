-- Copyright 2026 VitruvianSoftware
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- A courier.db as milestone 2 left it: the milestone-2 schema.sql (copied verbatim below, so this is a
-- genuine pre-migration database; user_version is still 0) plus a little dummy data. All names and text
-- are made up. TestMigrationFromMilestone2 opens this and checks that Open upgrades it.

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

INSERT INTO rooms (room_id, network, name, is_direct, created_at) VALUES
  ('!old:courier.local',   'whatsapp', 'Old room',   1, 1000),
  ('!busy:courier.local',  'telegram', 'Busy room',  0, 2000),
  ('!empty:courier.local', 'signal',   'Empty room', 1, 3000);

INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq) VALUES
  ('$o1', '!old:courier.local',  '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"first old"}',   10000, '', '', 1),
  ('$o2', '!old:courier.local',  '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"second old"}',  20000, '', '', 2),
  ('$b1', '!busy:courier.local', '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"hello"}',        30000, '', '', 3),
  ('$b2', '!busy:courier.local', '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"hi back"}',      40000, 'sent', '', 4),
  ('$b3', '!busy:courier.local', '@ghost2:courier.local', 'm.reaction',     NULL, '{"m.relates_to":{"event_id":"$b2","key":"x"}}', 50000, '', '', 5),
  ('$b4', '!busy:courier.local', '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.image","body":"pic.jpg"}',     60000, '', '', 6),
  ('$b5', '!busy:courier.local', '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"still sending"}', 70000, 'pending', '', 7);

INSERT INTO reads (room_id, event_id, ts) VALUES ('!busy:courier.local', '$b2', 40000);
