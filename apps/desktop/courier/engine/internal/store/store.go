// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package store is courier.db: the single source of truth that stands in for a Matrix server.
package store

import (
	"context"
	"database/sql"
	_ "embed"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"go.mau.fi/util/dbutil"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
)

//go:embed schema.sql
var schema string

type Room struct {
	ID, Network, Name, Topic, AvatarURI string
	IsDirect                            bool
	CreatedAt                           time.Time
	// LoginID is the account (bridgev2 user login) the chat belongs to, from its bridge info's fi.mau.receiver
	// (SetRoomLogin). "" is a chat every login of its network shares (a WhatsApp group), or one whose login isn't
	// known yet (every chat a store before milestone 4.4 kept).
	LoginID string
}

type Event struct {
	RoomID, EventID, Sender, Type string
	StateKey                      *string
	Content                       json.RawMessage
	TS                            time.Time
	Status, StatusReason          string
	Seq                           int64     // arrival order in this store; breaks ties between equal timestamps
	DeletedForMe                  bool      // Delete for Me: gone on this Mac, with no placeholder (also redacted)
	ExpiresAt                     time.Time // when an after_send disappearing timer takes it; zero = never
}

// Change is one entry of the change feed. Seq is set on "event" and "status" changes: it is the event's seq.
type Change struct {
	Kind, RoomID, EventID string
	Seq                   int64
}

// ChangeResync is the Kind of the change a subscriber is given after changes for it were dropped: it has missed
// something, so it must re-read everything it shows. It carries no room or event.
const ChangeResync = "resync"

type Store struct {
	db   *dbutil.Database
	seq  int64
	mu   sync.Mutex // guards seq and subs
	subs map[chan Change]*subscriber

	cfgMu        sync.RWMutex      // guards clock and networkNames
	clock        func() time.Time  // SetClock; time.Now by default
	networkNames map[string]string // SetNetworkNames: network name → display name

	typingMu sync.Mutex
	typing   map[string]map[string]*typingEntry // room ID → user ID → who is typing there, until when
	// afterFunc is time.AfterFunc, returning the timer's Stop. Tests replace it to fire typing expiries by hand.
	afterFunc func(time.Duration, func()) (stop func() bool)

	// backfillNow and backfillBudget time a backfill batch: time.Now and BackfillTimeBudget. Tests replace them so
	// that a batch runs out of time without depending on how fast the machine is.
	backfillNow    func() time.Time
	backfillBudget time.Duration
}

// subscriber is one change feed. dropped is set when a change could not be delivered to it; guarded by Store.mu.
type subscriber struct{ dropped bool }

func Open(path string) (*Store, error) {
	db, err := sqlite.Open(path)
	if err != nil {
		return nil, err
	}
	if _, err = db.Exec(context.Background(), schema); err != nil {
		db.Close()
		return nil, err
	}
	if err = migrate(context.Background(), db); err != nil {
		db.Close()
		return nil, err
	}
	s := &Store{
		db: db, subs: map[chan Change]*subscriber{}, clock: time.Now, typing: map[string]map[string]*typingEntry{},
		afterFunc:   func(d time.Duration, f func()) func() bool { return time.AfterFunc(d, f).Stop },
		backfillNow: time.Now, backfillBudget: BackfillTimeBudget,
	}
	if err = db.QueryRow(context.Background(), "SELECT COALESCE(MAX(seq),0) FROM events").Scan(&s.seq); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

// publish hands c to every subscriber without ever waiting for one. A subscriber whose buffer is full loses c and
// is marked; the next change that reaches it is preceded by one ChangeResync, however many it lost, so it never
// goes stale without knowing. The resync and that change go in together: until the buffer has room for both, the
// subscriber keeps dropping. Only publish sends on the channels, under s.mu, so len(ch) cannot grow under it.
func (s *Store) publish(c Change) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for ch, sub := range s.subs {
		if sub.dropped {
			if cap(ch)-len(ch) < 2 {
				continue // still no room for the resync and the change after it
			}
			ch <- Change{Kind: ChangeResync}
			sub.dropped = false
		}
		select {
		case ch <- c:
		default:
			sub.dropped = true
		}
	}
}

// SubscriberBuffer is how many changes a subscriber's feed holds before changes for it are dropped.
const SubscriberBuffer = 256

// Feed is one subscriber's change feed. C delivers the changes. A feed that falls more than SubscriberBuffer
// changes behind loses changes; it learns that either in band (a ChangeResync before the next change it can take)
// or by asking TakeDropped once it has caught up, whichever comes first. Each drop is reported once, one way.
type Feed struct {
	C  <-chan Change
	s  *Store
	ch chan Change
}

// Feed subscribes to the change feed. Close it when done.
func (s *Store) Feed() *Feed {
	ch := make(chan Change, SubscriberBuffer)
	s.mu.Lock()
	s.subs[ch] = &subscriber{}
	s.mu.Unlock()
	return &Feed{C: ch, s: s, ch: ch}
}

// TakeDropped reports whether changes were dropped for this feed since it was last told, and clears that, but only
// when nothing is waiting in C: a reader asks once it has read everything, and then re-reads all it shows. It is
// false while changes are still queued, because the reader has not caught up yet.
func (f *Feed) TakeDropped() bool {
	f.s.mu.Lock()
	defer f.s.mu.Unlock()
	sub := f.s.subs[f.ch]
	if sub == nil || !sub.dropped || len(f.ch) > 0 {
		return false
	}
	sub.dropped = false
	return true
}

// Close ends the subscription.
func (f *Feed) Close() {
	f.s.mu.Lock()
	delete(f.s.subs, f.ch)
	f.s.mu.Unlock()
}

// Subscribe returns a buffered change feed and a cancel function. A subscriber that falls more than
// SubscriberBuffer changes behind loses changes, and is then given a ChangeResync before the next one it gets.
// A reader that must hear about a drop even if nothing changes after it uses Feed and TakeDropped.
func (s *Store) Subscribe() (<-chan Change, func()) {
	f := s.Feed()
	return f.C, f.Close
}

func b2i(b bool) int {
	if b {
		return 1
	}
	return 0
}

func (s *Store) UpsertRoom(ctx context.Context, r Room) error {
	if r.CreatedAt.IsZero() {
		r.CreatedAt = time.Now()
	}
	// The room and its search doc change together. The doc holds only the name and whether the chat is a DM (its
	// network never changes), so it is re-written only when one of those does: a network sends the same chat again
	// often, for a new topic or picture, and that leaves the doc alone (Ruling 37).
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var oldName string
		var oldDirect bool
		err := s.db.QueryRow(ctx, "SELECT name, is_direct FROM rooms WHERE room_id=$1", r.ID).Scan(&oldName, &oldDirect)
		known := err == nil
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		// The login is kept on an update: it comes from the chat's bridge info (SetRoomLogin), not from the chat.
		_, err = s.db.Exec(ctx, `INSERT INTO rooms (room_id, network, name, topic, avatar_uri, is_direct, created_at, login_id)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
			ON CONFLICT(room_id) DO UPDATE SET name=excluded.name, topic=excluded.topic, avatar_uri=excluded.avatar_uri, is_direct=excluded.is_direct`,
			r.ID, r.Network, r.Name, r.Topic, r.AvatarURI, b2i(r.IsDirect), r.CreatedAt.UnixMilli(), r.LoginID)
		if err != nil || known && oldName == r.Name && oldDirect == r.IsDirect {
			return err
		}
		return s.indexChat(ctx, r)
	})
	if err == nil {
		s.publish(Change{Kind: "room", RoomID: r.ID})
	}
	return err
}

func scanRoom(row dbutil.Scannable) (Room, error) {
	var r Room
	var direct int
	var created int64
	err := row.Scan(&r.ID, &r.Network, &r.Name, &r.Topic, &r.AvatarURI, &direct, &created, &r.LoginID)
	r.IsDirect, r.CreatedAt = direct == 1, time.UnixMilli(created)
	return r, err
}

const roomCols = "room_id, network, name, topic, avatar_uri, is_direct, created_at, login_id"

// SetRoomLogin records the login (account) roomID belongs to; "" is a chat every login shares. It publishes
// nothing: it changes nothing a person sees by itself (the row's account tag is read with the chat). An unknown chat
// is ErrNotFound.
func (s *Store) SetRoomLogin(ctx context.Context, roomID, loginID string) error {
	res, err := s.db.Exec(ctx, "UPDATE rooms SET login_id=$2 WHERE room_id=$1", roomID, loginID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) GetRoom(ctx context.Context, roomID string) (Room, bool, error) {
	r, err := scanRoom(s.db.QueryRow(ctx, "SELECT "+roomCols+" FROM rooms WHERE room_id=$1", roomID))
	if errors.Is(err, sql.ErrNoRows) {
		return Room{}, false, nil
	}
	return r, err == nil, err
}

func (s *Store) ListRooms(ctx context.Context) ([]Room, error) {
	rows, err := s.db.Query(ctx, "SELECT "+roomCols+" FROM rooms ORDER BY created_at DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Room
	for rows.Next() {
		r, err := scanRoom(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// DeleteRoom forgets a chat and everything in it. Its messages, its name and its members go with it, and so does
// their search text: the triggers of migration 4 take out the docs of its messages and its name, and the doc of
// everyone who was in it is re-written without the names and the network only this chat knew.
func (s *Store) DeleteRoom(ctx context.Context, roomID string) error {
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		people, err := s.memberIDs(ctx, roomID)
		if err != nil {
			return err
		}
		if _, err = s.db.Exec(ctx, "DELETE FROM rooms WHERE room_id=$1", roomID); err != nil {
			return err
		}
		for _, userID := range people {
			if err = s.indexPerson(ctx, userID); err != nil {
				return err
			}
		}
		return nil
	})
	if err == nil {
		s.publish(Change{Kind: "room", RoomID: roomID})
	}
	return err
}

// memberIDs lists the user IDs of a chat's member rows.
func (s *Store) memberIDs(ctx context.Context, roomID string) ([]string, error) {
	rows, err := s.db.Query(ctx, "SELECT user_id FROM members WHERE room_id=$1", roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var u string
		if err := rows.Scan(&u); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

func (s *Store) SetMember(ctx context.Context, roomID, userID string, content json.RawMessage) error {
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		_, err := s.db.Exec(ctx, `INSERT INTO members (room_id, user_id, content) VALUES ($1,$2,$3)
			ON CONFLICT(room_id, user_id) DO UPDATE SET content=excluded.content`, roomID, userID, string(content))
		if err != nil {
			return err
		}
		return s.indexPerson(ctx, userID)
	})
	if err == nil {
		s.publish(Change{Kind: "member", RoomID: roomID})
	}
	return err
}

func (s *Store) Members(ctx context.Context, roomID string) (map[string]json.RawMessage, error) {
	rows, err := s.db.Query(ctx, "SELECT user_id, content FROM members WHERE room_id=$1", roomID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]json.RawMessage{}
	for rows.Next() {
		var u, c string
		if err := rows.Scan(&u, &c); err != nil {
			return nil, err
		}
		out[u] = json.RawMessage(c)
	}
	return out, rows.Err()
}

func (s *Store) DeleteMember(ctx context.Context, roomID, userID string) error {
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		if _, err := s.db.Exec(ctx, "DELETE FROM members WHERE room_id=$1 AND user_id=$2", roomID, userID); err != nil {
			return err
		}
		return s.indexPerson(ctx, userID)
	})
	if err == nil {
		s.publish(Change{Kind: "member", RoomID: roomID})
	}
	return err
}

// SetProfile records a user's global display name and avatar. A nil argument leaves that field unchanged;
// a pointer to an empty string clears it.
func (s *Store) SetProfile(ctx context.Context, userID string, displayName, avatarURI *string) error {
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		_, err := s.db.Exec(ctx, `INSERT INTO profiles (user_id, display_name, avatar_uri) VALUES ($1, COALESCE($2,''), COALESCE($3,''))
			ON CONFLICT(user_id) DO UPDATE SET display_name=COALESCE($2, display_name), avatar_uri=COALESCE($3, avatar_uri)`,
			userID, displayName, avatarURI)
		if err != nil {
			return err
		}
		return s.indexPerson(ctx, userID)
	})
	if err == nil {
		s.publish(Change{Kind: "profile"})
	}
	return err
}

func (s *Store) GetProfile(ctx context.Context, userID string) (displayName, avatarURI string, ok bool, err error) {
	err = s.db.QueryRow(ctx, "SELECT display_name, avatar_uri FROM profiles WHERE user_id=$1", userID).Scan(&displayName, &avatarURI)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", false, nil
	}
	return displayName, avatarURI, err == nil, err
}

// SetState stores a room's state event and reports whether that changed anything: storing the content already
// held under the same type and key writes nothing and is false.
func (s *Store) SetState(ctx context.Context, roomID, evType, stateKey string, content json.RawMessage) (bool, error) {
	res, err := s.db.Exec(ctx, `INSERT INTO state (room_id, type, state_key, content) VALUES ($1,$2,$3,$4)
		ON CONFLICT(room_id, type, state_key) DO UPDATE SET content=excluded.content WHERE content IS NOT excluded.content`,
		roomID, evType, stateKey, string(content))
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	return n > 0, err
}

// RoomChanged tells subscribers a chat changed in a way the store keeps no column for (what the chat can do, from
// its stored state): it publishes a "room" change, and the app reads the chat again.
func (s *Store) RoomChanged(roomID string) {
	s.publish(Change{Kind: "room", RoomID: roomID})
}

func (s *Store) GetState(ctx context.Context, roomID, evType, stateKey string) (json.RawMessage, bool, error) {
	var c string
	err := s.db.QueryRow(ctx, "SELECT content FROM state WHERE room_id=$1 AND type=$2 AND state_key=$3", roomID, evType, stateKey).Scan(&c)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, nil
	}
	return json.RawMessage(c), err == nil, err
}

func (s *Store) InsertEvent(ctx context.Context, e Event) (bool, error) {
	seq := s.nextSeq()
	var inserted, cameBack bool
	// The event, the room's last_ts / last_event_id, its coming back from the archive and the search index change
	// together or not at all.
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var err error
		inserted, cameBack, err = s.insertEvent(ctx, e, seq)
		return err
	})
	if err != nil {
		return false, err
	}
	s.publishInserted(e, seq, inserted, cameBack)
	return inserted, nil
}

// nextSeq hands out the next arrival order.
func (s *Store) nextSeq() int64 {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.seq++
	return s.seq
}

// publishInserted publishes what InsertEvent publishes once insertEvent's transaction has committed.
func (s *Store) publishInserted(e Event, seq int64, inserted, cameBack bool) {
	if inserted {
		s.publish(Change{Kind: "event", RoomID: e.RoomID, EventID: e.EventID, Seq: seq})
	}
	if cameBack {
		s.publish(Change{Kind: "room", RoomID: e.RoomID})
	}
}

// insertEvent is InsertEvent's work inside the caller's transaction, so that the outbox can insert a message and
// change its own rows in one transaction: the event, the room's last_ts / last_event_id, its coming back from the
// archive and the search index. It publishes nothing; the caller runs publishInserted after the commit.
func (s *Store) insertEvent(ctx context.Context, e Event, seq int64) (inserted, cameBack bool, err error) {
	// A bridge's note of a timer change I just made here, which my own note already tells (Ruling 40): one note.
	if echo, err := s.echoesLocalNote(ctx, e); err != nil || echo {
		return false, false, err
	}
	e.TS = s.clampTS(e.TS) // a bridge's time can be any number: what the app subtracts must not overflow
	res, err := s.db.Exec(ctx, `INSERT INTO events (event_id, room_id, sender, type, state_key, content, ts, status, status_reason, seq, expires_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT(event_id) DO NOTHING`,
		e.EventID, e.RoomID, e.Sender, e.Type, e.StateKey, string(e.Content), e.TS.UnixMilli(), e.Status, e.StatusReason, seq,
		afterSendExpiry(e.Content, e.TS))
	if err != nil {
		return false, false, err
	}
	n, _ := res.RowsAffected()
	inserted = n == 1
	// A redaction of e that came first deletes it now, before anything else looks at it, so a deleted message
	// never moves the chat, brings it back from the archive or cancels a pending auto-archive (Ruling 36). A
	// deleted redaction still deletes its own target, as one deleted after it arrived would have.
	var deleted bool
	if inserted {
		if deleted, err = s.redactedEarlier(ctx, e); err != nil {
			return false, false, err
		}
	}
	switch {
	case !inserted, deleted && isMessageLike(e.Type, e.Content):
	case isMessageLike(e.Type, e.Content):
		var prevLastTS int64
		if err = s.db.QueryRow(ctx, "SELECT COALESCE((SELECT last_ts FROM rooms WHERE room_id=$1), 0)", e.RoomID).Scan(&prevLastTS); err != nil {
			return false, false, err
		}
		// Only a message newer than the current newest moves the room: a backfilled older one must not.
		_, err = s.db.Exec(ctx, "UPDATE rooms SET last_ts=$2, last_event_id=$3 WHERE room_id=$1 AND $2 >= last_ts",
			e.RoomID, e.TS.UnixMilli(), e.EventID)
		// Newer than every message the chat had: a new message, not a backfilled one (nor one from the same
		// millisecond as the newest).
		newest := e.TS.UnixMilli() > prevLastTS
		switch {
		case err != nil:
		case e.Sender != string(ids.Me):
			// The record that a call ended (was declined, dropped) is no news, nor is a timer change (Ruling 42): neither
			// brings the chat back or stops its auto-archive.
			if !isCallRecord(e) && !isTimerNote(e) {
				cameBack, err = s.newMessageFromOthers(ctx, e.RoomID, e.TS, newest)
			}
		case newest && e.Status != "queued" && e.Status != StatusWaiting && !isTimerNote(e):
			// My reply: with an enabled after_reply rule the chat is archived that long after it. A message held for
			// undo send, or waiting for its network, isn't one yet; its claim schedules it (releaseHeld), so Undo leaves
			// nothing behind. A note that I changed the timer isn't a reply (Ruling 40).
			err = s.scheduleArchive(ctx, e.RoomID, trigAfterReply, e.TS.UnixMilli())
		}
	case e.Type == "m.room.redaction" && e.Status != "failed":
		_, err = s.redact(ctx, e.RoomID, e.Content)
	}
	if err == nil && inserted {
		err = s.indexEvent(ctx, e)
	}
	if err != nil {
		return false, false, err
	}
	return inserted, cameBack, nil
}

// newMessageFromOthers is what a new message (message-like, not an edit) from someone else does to where its chat
// is, inside InsertEvent's transaction. It reports whether the chat came back from the archive.
//
// Inferred (inventory 01 §18): an archived chat comes back on a new message; low priority and hidden chats don't,
// so only archived_at is touched.
// Inferred: only a message from someone else brings an archived chat back (InsertEvent never calls this for mine),
// and only one sent after the chat was archived, so a backfilled older message leaves it where it is.
//
// newest says the message is newer than every message the chat had before it (strictly: one in the same
// millisecond as the newest doesn't count). Only such a message, the other person writing back, cancels a pending
// auto-archive (archive_due); a backfilled older one leaves it pending.
func (s *Store) newMessageFromOthers(ctx context.Context, roomID string, ts time.Time, newest bool) (bool, error) {
	if newest {
		if _, err := s.db.Exec(ctx, "DELETE FROM archive_due WHERE room_id=$1", roomID); err != nil {
			return false, err
		}
	}
	var archivedAt int64
	if err := s.db.QueryRow(ctx, "SELECT COALESCE((SELECT archived_at FROM room_prefs WHERE room_id=$1), 0)", roomID).Scan(&archivedAt); err != nil {
		return false, err
	}
	if archivedAt == 0 || ts.UnixMilli() <= archivedAt {
		return false, nil // not archived, or older than the archive: a backfill, not a new message
	}
	_, err := s.db.Exec(ctx, "UPDATE room_prefs SET archived_at=0 WHERE room_id=$1", roomID)
	return err == nil, err
}

// redactionTarget is the event a redaction's content deletes: content.redacts, "" when there is none.
func redactionTarget(content json.RawMessage) string {
	var c struct {
		Redacts string `json:"redacts"`
	}
	if json.Unmarshal(content, &c) != nil {
		return ""
	}
	return c.Redacts
}

// redact marks the event a redaction deletes, so it is no longer unread or the chat's latest message, and no longer
// searchable (the events_unindex_redacted trigger takes its doc out). If it was the latest, the chat goes back to
// the newest message that is left (or to none), as DeleteEvent does. If it was an edit, its message is re-indexed
// with the edit before it. A redaction of something we do not have, or with no target, changes nothing; found
// reports whether the target is here.
func (s *Store) redact(ctx context.Context, roomID string, content json.RawMessage) (found bool, err error) {
	target := redactionTarget(content)
	if target == "" {
		return false, nil
	}
	gone, err := scanEvent(s.db.QueryRow(ctx, "UPDATE events SET redacted=1 WHERE event_id=$1 AND room_id=$2 RETURNING "+eventCols,
		target, roomID))
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if _, err = s.db.Exec(ctx, backfillLastEventSQL+" WHERE room_id=$1 AND last_event_id=$2", roomID, target); err != nil {
		return false, err
	}
	if isEdit(gone.Content) {
		return true, s.applyEdit(ctx, gone)
	}
	return true, nil
}

// redactedEarlier deals with a redaction of e that arrived before e did, inside InsertEvent's transaction, just
// after e is written: e is marked deleted as an in-order redaction marks it, and deleted reports it. InsertEvent
// then does nothing else a new event does (a deleted message is never the chat's latest, so it doesn't move the
// chat, bring it back from the archive or cancel a pending auto-archive), so it isn't unread, the chat's latest or
// searchable (indexEvent passes over a deleted message, and CurrentText over a deleted edit). The timeline hides it
// by the redaction event, as it does whatever the order.
func (s *Store) redactedEarlier(ctx context.Context, e Event) (deleted bool, err error) {
	res, err := s.db.Exec(ctx, earlierRedactionSQL, e.EventID, e.RoomID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

// FailInterruptedSends turns every message still pending from an earlier run into a failed one, with
// ReasonMayHaveBeenSent. Run it once at engine start, before anything is served: a pending row then is one
// whose send the last engine never heard back about, so it may or may not have gone. Nothing is sent again
// unasked; the person can Retry or Delete it. A held message still queued (its window hadn't ended, or it ended
// while the engine was down) was never handed over, so it is left for the outbox (ClaimDue), and so is a message
// still waiting for its network (ClaimWaiting): neither is pending.
//
// Each failure keeps SetStatus's rules, in one transaction (Ruling 4): a failed edit no longer counts, and a
// failed unsend of mine puts its message back, so neither looks done while the network may never have had it. It
// returns how many rows it changed, and publishes nothing (no one is subscribed yet).
func (s *Store) FailInterruptedSends(ctx context.Context) (int64, error) {
	var failed []Event
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var err error
		failed, err = s.queryEvents(ctx, "UPDATE events SET status='failed', status_reason=$1 WHERE status='pending' RETURNING "+eventCols,
			ReasonMayHaveBeenSent)
		if err != nil {
			return err
		}
		// Every interrupted send is failed before any is put back: unredact then sees an interrupted second unsend
		// of the same message as failed too, as it would have after two SetStatus calls.
		for _, e := range failed {
			if _, err = s.statusChanged(ctx, e, "pending"); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return 0, err
	}
	return int64(len(failed)), nil
}

// ReasonMayHaveBeenSent is the status_reason of a message whose send was cut off by the engine stopping: the
// network may have taken it. The app shows its own wording for it.
const ReasonMayHaveBeenSent = "may have been sent"

// isMessageLike reports whether an event can be a room's latest message: a message, sticker, encrypted placeholder
// or poll (its start) that is not an edit of an earlier message. (SQL twin: messageLikeTypes with notEditSQL.)
func isMessageLike(typ string, content json.RawMessage) bool {
	switch typ {
	case "m.room.message", "m.sticker", "m.room.encrypted", pollStartType:
		return !isEdit(content)
	}
	return false
}

// isEdit reports whether content replaces an earlier message (m.relates_to.rel_type = m.replace). Content that
// is not JSON is not an edit. (SQL twin: notEditSQL.)
func isEdit(content json.RawMessage) bool {
	var c struct {
		RelatesTo struct {
			RelType string `json:"rel_type"`
		} `json:"m.relates_to"`
	}
	return json.Unmarshal(content, &c) == nil && c.RelatesTo.RelType == "m.replace"
}

const eventCols = "room_id, event_id, sender, type, state_key, content, ts, status, status_reason, seq, deleted_for_me, expires_at"

// eventRow is where a row of eventCols is scanned to: dest, in eventCols' order, then event.
type eventRow struct {
	e       Event
	content string
	ts      int64
	expires sql.NullInt64
}

func (r *eventRow) dest() []any {
	return []any{
		&r.e.RoomID, &r.e.EventID, &r.e.Sender, &r.e.Type, &r.e.StateKey, &r.content, &r.ts, &r.e.Status,
		&r.e.StatusReason, &r.e.Seq, &r.e.DeletedForMe, &r.expires,
	}
}

func (r *eventRow) event() Event {
	e := r.e
	e.Content, e.TS = json.RawMessage(r.content), time.UnixMilli(r.ts)
	if r.expires.Valid {
		e.ExpiresAt = time.UnixMilli(r.expires.Int64)
	}
	return e
}

func scanEvent(row dbutil.Scannable) (Event, error) {
	var r eventRow
	err := row.Scan(r.dest()...)
	return r.event(), err
}

func (s *Store) GetEvent(ctx context.Context, eventID string) (Event, bool, error) {
	e, err := scanEvent(s.db.QueryRow(ctx, "SELECT "+eventCols+" FROM events WHERE event_id=$1", eventID))
	if errors.Is(err, sql.ErrNoRows) {
		return Event{}, false, nil
	}
	return e, err == nil, err
}

func (s *Store) Events(ctx context.Context, roomID string, limit int) ([]Event, error) {
	rows, err := s.db.Query(ctx, "SELECT "+eventCols+" FROM events WHERE room_id=$1 ORDER BY ts DESC, seq DESC LIMIT $2", roomID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Event
	for rows.Next() {
		e, err := scanEvent(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// SetStatus records how a message I sent is doing (pending, sent or failed, with the network's reason), and keeps
// what it changed true, in the same transaction: a change the network refuses never looks done on this Mac.
//
//   - An edit that fails no longer counts (currentEditSQL), so its message is re-indexed with the newest edit that
//     hasn't failed; one that stops being failed (a Retry puts it back to pending) counts again.
//   - My unsend (my redaction) that fails puts its message back (unredact), and the chat gets a "room" change; one
//     that stops being failed deletes it again (redact).
//
// The change feed gets a "status" change for the event. An unknown event is sql.ErrNoRows.
func (s *Store) SetStatus(ctx context.Context, eventID, status, reason string) error {
	var e Event
	var roomChanged bool
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var was string
		if err := s.db.QueryRow(ctx, "SELECT status FROM events WHERE event_id=$1", eventID).Scan(&was); err != nil {
			return err
		}
		var err error
		e, err = scanEvent(s.db.QueryRow(ctx, "UPDATE events SET status=$2, status_reason=$3 WHERE event_id=$1 RETURNING "+eventCols,
			eventID, status, reason))
		if err != nil {
			return err
		}
		roomChanged, err = s.statusChanged(ctx, e, was)
		return err
	})
	if err != nil {
		return err
	}
	s.publish(Change{Kind: "status", RoomID: e.RoomID, EventID: eventID, Seq: e.Seq})
	if roomChanged {
		s.publish(Change{Kind: "room", RoomID: e.RoomID})
	}
	return nil
}

// statusChanged keeps true what event e's change of status (from was to e.Status) changed, inside the transaction
// that wrote it: SetStatus's rules, which FailInterruptedSends keeps too. Going into or out of failed, an edit
// re-indexes its message (currentEditSQL counts only edits that haven't failed), and my unsend puts its message back
// (unredact) or deletes it again (redact). roomChanged reports whether the chat's message came back or went.
func (s *Store) statusChanged(ctx context.Context, e Event, was string) (roomChanged bool, err error) {
	failed, wasFailed := e.Status == "failed", was == "failed"
	switch {
	case failed == wasFailed:
	case isEdit(e.Content):
		err = s.applyEdit(ctx, e)
	case e.Type == "m.room.redaction" && e.Sender == string(ids.Me) && failed:
		roomChanged, err = s.unredact(ctx, e.RoomID, redactionTarget(e.Content))
	case e.Type == "m.room.redaction" && e.Sender == string(ids.Me):
		roomChanged, err = s.redact(ctx, e.RoomID, e.Content)
	}
	return roomChanged, err
}

// DeleteEvent forgets one event. If it was the chat's latest message, the chat goes back to the newest message
// that is left (or to none), so the inbox does not keep pointing at something that is gone. Its search doc goes
// with it (the events_unindex trigger), and if it was an edit its message is re-indexed with the edit before it.
// The change feed gets a "status" change for it, which tells a client to re-read that chat. An unknown event is
// not an error.
func (s *Store) DeleteEvent(ctx context.Context, eventID string) error {
	var roomID string
	var seq int64
	found := false
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		gone, err := scanEvent(s.db.QueryRow(ctx, "DELETE FROM events WHERE event_id=$1 RETURNING "+eventCols, eventID))
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		found, roomID, seq = true, gone.RoomID, gone.Seq
		if _, err = s.db.Exec(ctx, backfillLastEventSQL+" WHERE room_id=$1 AND last_event_id=$2", roomID, eventID); err != nil {
			return err
		}
		if isEdit(gone.Content) {
			return s.applyEdit(ctx, gone)
		}
		return nil
	})
	if err == nil && found {
		s.publish(Change{Kind: "status", RoomID: roomID, EventID: eventID, Seq: seq})
	}
	return err
}

// SetRead records that I read roomID up to eventID on another device, as the network reports it. It is only ever
// my own read: other people's receipts are SetReceipt's. The marker keeps the target event's own (ts, seq), not
// the time of the receipt, so a later receipt for an older message does not mark newer ones read; for an event
// we do not have, receiptTS stands in. Like the local marker it only moves forward.
//
// A read that moves the marker to or past the message the chat is marked unread from (SetUnreadFrom) clears that
// mark, in the same transaction, and publishes a "room" change for it (Ruling 6): I have read that message since.
func (s *Store) SetRead(ctx context.Context, roomID, eventID string, receiptTS time.Time) error {
	cleared := false
	_, err := s.advanceMarkerThen(ctx, "reads", roomID, eventID, receiptTS, func(ctx context.Context, ts, seq int64) error {
		res, err := s.db.Exec(ctx, `UPDATE room_prefs SET unread_from_ts=0, unread_from_seq=0
			WHERE room_id=$1 AND unread_from_ts > 0 AND (unread_from_ts, unread_from_seq) <= ($2, $3)`, roomID, ts, seq)
		if err != nil {
			return err
		}
		n, _ := res.RowsAffected()
		cleared = n > 0
		return nil
	})
	if err == nil && cleared {
		s.publish(Change{Kind: "room", RoomID: roomID})
	}
	return err
}

// LoginState is one login's bridge state, as the bridge sent it (status.BridgeState). LoginID "" is the bridge's
// own state, which belongs to no login (UNCONFIGURED before any account is linked).
type LoginState struct {
	LoginID string
	State   json.RawMessage
}

// SetLoginState keeps a login's latest bridge state, under its network and its login ID (the state's remote_id; ""
// for the bridge's own), and publishes a "bridge" change for the network. Each login keeps its own: one login's
// state never replaces another's (Review Focus 5).
//
// The row is replaced, not updated in place, so that it takes a new rowid: the newest write of a network is then the
// row with the highest rowid, which is what BridgeState reads until its callers move to LoginStates (Ruling C1).
func (s *Store) SetLoginState(ctx context.Context, network, loginID string, state json.RawMessage) error {
	_, err := s.db.Exec(ctx, `INSERT OR REPLACE INTO login_state (network, login_id, state) VALUES ($1,$2,$3)`,
		network, loginID, string(state))
	if err == nil {
		s.NetworkChanged(network)
	}
	return err
}

// LoginStates lists a network's login states: the bridge's own ("") first, then by login ID.
func (s *Store) LoginStates(ctx context.Context, network string) ([]LoginState, error) {
	rows, err := s.db.Query(ctx, "SELECT login_id, state FROM login_state WHERE network=$1 ORDER BY login_id", network)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []LoginState
	for rows.Next() {
		var l LoginState
		var st string
		if err := rows.Scan(&l.LoginID, &st); err != nil {
			return nil, err
		}
		l.State = json.RawMessage(st)
		out = append(out, l)
	}
	return out, rows.Err()
}

// NetworkChanged tells subscribers something about a network's accounts changed that the store keeps no row for (a
// network starting, say): it publishes a "bridge" change for it, and the app reads the accounts again.
func (s *Store) NetworkChanged(network string) {
	s.publish(Change{Kind: "bridge", RoomID: network})
}

// SpacesChanged tells subscribers the spaces may have changed for a reason the store keeps no row for (a network's
// bridge coming up, which gives its account a space): it publishes a "spaces" change, and the app reads them again.
func (s *Store) SpacesChanged() {
	s.publish(Change{Kind: "spaces"})
}

// SetBridgeState keeps a bridge state as its login's (its remote_id, or "" when it has none): SetLoginState for a
// caller that hasn't moved to it yet.
//
// It is transitional: Ruling C1 keeps it, and BridgeState, as thin wrappers over login_state until Task 5, so that
// every task's engine builds; the callers move to SetLoginState and LoginStates in Tasks 2, 4 and 5.
func (s *Store) SetBridgeState(ctx context.Context, network string, state json.RawMessage) error {
	var st struct {
		RemoteID string `json:"remote_id"`
	}
	_ = json.Unmarshal(state, &st) // a state that can't be read is the bridge's own
	return s.SetLoginState(ctx, network, st.RemoteID, state)
}

// BridgeState is the network's bridge state written last, of any login: what the single bridge_state row of 4.3
// said, so its callers keep their behaviour with one login. ok is false when the network has none.
//
// It is transitional, as SetBridgeState is; LoginStates is the per-login answer.
func (s *Store) BridgeState(ctx context.Context, network string) (json.RawMessage, bool, error) {
	var c string
	err := s.db.QueryRow(ctx, "SELECT state FROM login_state WHERE network=$1 ORDER BY rowid DESC LIMIT 1", network).Scan(&c)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, nil
	}
	return json.RawMessage(c), err == nil, err
}
