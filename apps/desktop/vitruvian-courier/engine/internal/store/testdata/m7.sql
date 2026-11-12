-- Copyright 2026 VitruvianSoftware
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- A courier.db as milestone 4.3 (and the call-notice change) left it: the milestone-2 baseline (schema.sql, copied
-- verbatim below) with the schema of migrations 1 to 6 as they shipped, so user_version is 6, plus dummy data on two
-- networks. WhatsApp has chats of two accounts (Pat's with one, Kim's with the other) and a group, Slack one channel;
-- the store of 4.3 kept no account per chat. Three messages of mine went out, one is held for undo send (queued, with
-- its undo row) and one is scheduled. Each network has its bridge state, WhatsApp's from a login (remote_id) and
-- Slack's the bridge's own. Two chats are marked unread. All names and text are made up. The search tables are empty
-- and search_state covers every row, as if 4.3 had upgraded this data and quit before its backfill ran.
-- TestMigrationFromMilestone4_3 opens this and checks that Open upgrades it to migration 7.

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

-- Migration 1, as it shipped (its backfill left out: the rows below carry their last message).
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

-- Migration 5, as it shipped (its one-off updates of rows left out: the rows below need none).
ALTER TABLE events ADD COLUMN deleted_for_me INTEGER NOT NULL DEFAULT 0; -- set with redacted = 1: gone here, no placeholder
ALTER TABLE events ADD COLUMN expires_at INTEGER;                         -- after_send disappearing: ts + timer; NULL = never
CREATE INDEX events_expiry ON events(expires_at) WHERE expires_at IS NOT NULL AND redacted = 0;
CREATE INDEX events_refs ON events((CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".event_id') END), ts)
  WHERE type IN ('org.matrix.msc3381.poll.response', 'org.matrix.msc3381.poll.end');
CREATE INDEX events_threads ON events(room_id, (CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".event_id') END), ts DESC, seq DESC)
  WHERE type IN ('m.room.message', 'm.sticker') AND (CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".rel_type') = 'm.thread' END);
CREATE INDEX events_reactions ON events((CASE WHEN json_valid(content) THEN json_extract(content, '$."m.relates_to".event_id') END), ts) WHERE type = 'm.reaction';
CREATE INDEX events_timer_notes ON events(room_id, seq) WHERE type = 'm.room.message' AND (CASE WHEN json_valid(content) THEN json_extract(content, '$."com.beeper.action_message".type') END) = 'disappearing_timer';
CREATE TABLE outbox (outbox_id INTEGER PRIMARY KEY,
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,
  kind TEXT NOT NULL,                    -- undo | later
  event_id TEXT NOT NULL UNIQUE,         -- undo: the queued events row; later: the ID it will be sent as
  type TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '',   -- later only
  due_at INTEGER NOT NULL, set_at INTEGER NOT NULL,
  condition TEXT NOT NULL DEFAULT 'always',                          -- later: if_no_reply | always
  state TEXT NOT NULL DEFAULT 'waiting');                            -- waiting | canceled | missed
CREATE INDEX outbox_due ON outbox(state, due_at);
CREATE INDEX outbox_room ON outbox(room_id, kind);
CREATE TABLE bookmarks (event_id TEXT PRIMARY KEY REFERENCES events(event_id) ON DELETE CASCADE,
  room_id TEXT NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE, created_at INTEGER NOT NULL);
CREATE INDEX bookmarks_new ON bookmarks(created_at DESC);

-- Migration 6 changes no schema (it re-reads call notices; there are none below).
PRAGMA user_version = 6;

INSERT INTO rooms (room_id, network, name, is_direct, created_at, last_ts, last_event_id, request) VALUES
  ('!pat:courier.local',    'whatsapp', 'Pat Example',  1, 1790000000000, 1790812804000, '$p4', 0),
  ('!kim:courier.local',    'whatsapp', 'Kim Sample',   1, 1790000001000, 1790812812000, '$k3', 0),
  ('!family:courier.local', 'whatsapp', 'Family',       0, 1790000002000, 1790812824000, '$f5', 0),
  ('!team:courier.local',   'slack',    'Release team', 0, 1790000003000, 1790812836000, '$s7', 0);

INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq) VALUES
  ('$p1', '!pat:courier.local',    '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"still on for lunch"}', 1790812801000, '', '', 1),
  ('$p2', '!pat:courier.local',    '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"yes, noon works"}', 1790812802000, 'sent', '', 2),
  ('$p3', '!pat:courier.local',    '@ghost1:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"great"}', 1790812803000, '', '', 3),
  ('$p4', '!pat:courier.local',    '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"see you there"}', 1790812804000, 'sent', '', 4),
  ('$k1', '!kim:courier.local',    '@ghost4:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"did the parcel arrive"}', 1790812810000, '', '', 5),
  ('$k2', '!kim:courier.local',    '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"it did, thanks"}', 1790812811000, 'sent', '', 6),
  -- Held for undo send: queued, with its undo row below, its window ending five seconds after it.
  ('$k3', '!kim:courier.local',    '@me:courier.local',     'm.room.message', NULL, '{"msgtype":"m.text","body":"one more thing","fi.courier.source":{"text":"one more thing","entities":[]}}', 1790812812000, 'queued', '', 7),
  ('$f0', '!family:courier.local', '@ghost5:courier.local', 'm.room.name', '', '{"name":"Family"}', 1790812819000, '', '', 8),
  ('$f1', '!family:courier.local', '@ghost5:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"dinner on sunday"}', 1790812820000, '', '', 9),
  ('$f2', '!family:courier.local', '@ghost6:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"count me in"}', 1790812821000, '', '', 10),
  ('$f3', '!family:courier.local', '@ghost5:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"bring dessert"}', 1790812822000, '', '', 11),
  ('$f4', '!family:courier.local', '@ghost6:courier.local', 'm.reaction', NULL, '{"m.relates_to":{"rel_type":"m.annotation","event_id":"$f3","key":"+1"}}', 1790812823000, '', '', 12),
  ('$f5', '!family:courier.local', '@ghost6:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"what time"}', 1790812824000, '', '', 13),
  ('$s1', '!team:courier.local',   '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"release notes draft"}', 1790812830000, '', '', 14),
  ('$s2', '!team:courier.local',   '@ghost3:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"looks good"}', 1790812831000, '', '', 15),
  ('$s3', '!team:courier.local',   '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"shipping friday"}', 1790812832000, '', '', 16),
  ('$s4', '!team:courier.local',   '@ghost3:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"standup moved"}', 1790812833000, '', '', 17),
  ('$s5', '!team:courier.local',   '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"tests are green"}', 1790812834000, '', '', 18),
  ('$s6', '!team:courier.local',   '@ghost2:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"merge it"}', 1790812835000, '', '', 19),
  ('$s7', '!team:courier.local',   '@ghost3:courier.local', 'm.room.message', NULL, '{"msgtype":"m.text","body":"done"}', 1790812836000, '', '', 20);

-- The held message's undo row, and a scheduled message for the channel.
INSERT INTO outbox (room_id, kind, event_id, type, content, due_at, set_at, condition, state) VALUES
  ('!kim:courier.local',  'undo',  '$k3',     '',               '', 1790812817000, 1790812812000, 'always', 'waiting'),
  ('!team:courier.local', 'later', '$later1', 'm.room.message', '{"msgtype":"m.text","body":"weekly reminder","fi.courier.source":{"text":"weekly reminder","entities":[]}}',
    1790899200000, 1790812840000, 'always', 'waiting');

INSERT INTO profiles (user_id, display_name) VALUES
  ('@ghost1:courier.local', 'Pat Example'), ('@ghost4:courier.local', 'Kim Sample'), ('@ghost2:courier.local', 'Sam Placeholder');
INSERT INTO members (room_id, user_id, content) VALUES
  ('!pat:courier.local',    '@ghost1:courier.local', '{"membership":"join"}'),
  ('!kim:courier.local',    '@ghost4:courier.local', '{"membership":"join"}'),
  ('!family:courier.local', '@ghost5:courier.local', '{"membership":"join","displayname":"Robin Example"}'),
  ('!family:courier.local', '@ghost6:courier.local', '{"membership":"join","displayname":"Ari Sample"}'),
  ('!family:courier.local', '@me:courier.local',     '{"membership":"join"}'),
  ('!team:courier.local',   '@ghost2:courier.local', '{"membership":"join","displayname":"Sam Placeholder"}'),
  ('!team:courier.local',   '@ghost3:courier.local', '{"membership":"join","displayname":"Lee Sample"}'),
  ('!team:courier.local',   '@me:courier.local',     '{"membership":"join"}');

-- I read the family chat up to $f2 on my phone, and the channel up to $s3 here.
INSERT INTO reads (room_id, event_id, ts) VALUES ('!family:courier.local', '$f2', 1790812821000);
INSERT INTO local_reads (room_id, event_id, ts) VALUES ('!team:courier.local', '$s3', 1790812832000);
INSERT INTO room_prefs (room_id, muted, marked_unread) VALUES
  ('!pat:courier.local', 0, 1), ('!family:courier.local', 0, 1), ('!team:courier.local', 1, 0);

-- One state per network: WhatsApp's from its login (bridgev2 stamps remote_id), Slack's the bridge's own.
INSERT INTO bridge_state (network, state) VALUES
  ('whatsapp', '{"state_event":"CONNECTED","timestamp":1790812900,"ttl":3600,"remote_id":"login-a","remote_name":"Test Account"}'),
  ('slack',    '{"state_event":"UNCONFIGURED","timestamp":1790812900,"ttl":3600}');

-- Migration 4's backfill cursors, over every row above.
INSERT INTO search_state VALUES ('backfill_until', (SELECT COALESCE(MAX(rowid), 0) FROM events)), ('backfill_after', 0),
  ('chats_until', (SELECT COALESCE(MAX(rowid), 0) FROM rooms)), ('chats_after', 0),
  ('profiles_until', (SELECT COALESCE(MAX(rowid), 0) FROM profiles)), ('profiles_after', 0),
  ('members_until', (SELECT COALESCE(MAX(rowid), 0) FROM members)), ('members_after', 0);
