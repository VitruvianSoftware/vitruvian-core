-- Copyright 2026 VitruvianSoftware
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- A courier.db as milestone 3 left it: the milestone-2 baseline (schema.sql, copied verbatim below) with
-- migrations 1 and 2 applied as they shipped, so user_version is 2, plus a little dummy data. All names and text
-- are made up. TestMigrationFromMilestone3 opens this and checks that Open upgrades it to migration 3.

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

PRAGMA user_version = 2;

INSERT INTO rooms (room_id, network, name, is_direct, created_at, last_ts, last_event_id) VALUES
  ('!quiet:courier.local', 'whatsapp', 'Quiet room', 1, 1000, 20000, '$q2'),
  ('!loud:courier.local',  'telegram', 'Loud room',  0, 2000, 40000, '$l2'),
  ('!new:courier.local',   'signal',   'New room',   1, 3000, 0,     '');

INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq, redacted) VALUES
  ('$q1', '!quiet:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"first"}',  10000, '', '', 1, 0),
  ('$q2', '!quiet:courier.local', '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"second"}', 20000, '', '', 2, 0),
  ('$l1', '!loud:courier.local',  '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"hello"}',  30000, '', '', 3, 0),
  ('$l2', '!loud:courier.local',  '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"hi"}',     40000, 'sent', '', 4, 0);

-- The user muted the quiet room in milestone 3; the mute must survive the upgrade.
INSERT INTO room_prefs (room_id, muted) VALUES ('!quiet:courier.local', 1), ('!loud:courier.local', 0);
INSERT INTO local_reads (room_id, event_id, ts) VALUES ('!quiet:courier.local', '$q1', 10000);
