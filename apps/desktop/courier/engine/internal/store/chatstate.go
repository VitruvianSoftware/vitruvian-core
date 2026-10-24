// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"time"
	"unicode/utf8"
)

// ErrPinned is SetArchived's answer when every chat it was asked to archive is pinned.
var ErrPinned = errors.New("a pinned chat can't be archived")

// ErrNote is SetUnreadFrom's answer for a note (a timer change, a call): a system line, not a message to read again.
// Ruling P2: Mark as Unread is refused on a note, by the engine as by the app (which hides it there); the actions
// layer answers it as not supported.
var ErrNote = errors.New("a note can't be marked unread")

// maxDraftChars is the longest draft kept, in characters.
const maxDraftChars = 16384

// Reminder is a chat's reminder: bring it back to my attention at DueAt. Condition is "if_no_reply" (only if I
// haven't sent a message since SetAt) or "always". FiredAt is zero until it has fired. Task 3 sets and fires them.
type Reminder struct {
	RoomID, Condition     string
	DueAt, SetAt, FiredAt time.Time
}

// SetClock replaces the store's clock, for tests. The default is time.Now.
func (s *Store) SetClock(now func() time.Time) {
	s.cfgMu.Lock()
	s.clock = now
	s.cfgMu.Unlock()
}

func (s *Store) now() time.Time {
	s.cfgMu.RLock()
	defer s.cfgMu.RUnlock()
	return s.clock()
}

// Now is the store's clock (time.Now unless SetClock replaced it), so the actions that check a message's age go by
// the same time as the store's own rules.
func (s *Store) Now() time.Time { return s.now() }

// SetNetworkNames tells the store each network's display name ("whatsapp" → "WhatsApp"), for the titles of
// account spaces and a row's MutedByName. The store can't import the network list itself (that package imports
// the store), so the engine hands it over at start. A network missing from names shows its own name.
func (s *Store) SetNetworkNames(names map[string]string) {
	cp := make(map[string]string, len(names))
	for k, v := range names {
		cp[k] = v
	}
	s.cfgMu.Lock()
	s.networkNames = cp
	s.cfgMu.Unlock()
}

func (s *Store) networkName(network string) string {
	s.cfgMu.RLock()
	defer s.cfgMu.RUnlock()
	if n := s.networkNames[network]; n != "" {
		return n
	}
	return network
}

// msTime is a stored Unix-millisecond time, with 0 meaning "none" (the zero time).
func msTime(ms int64) time.Time {
	if ms == 0 {
		return time.Time{}
	}
	return time.UnixMilli(ms)
}

// prefs is a chat's room_prefs row: the user's own settings for it. A chat without a row has the zero prefs.
type prefs struct {
	muted, lowPriority, hidden, markedUnread bool
	pinnedAt, archivedAt                     int64 // Unix ms; 0 = not pinned / not archived
	draft                                    string
	unreadFromTS, unreadFromSeq              int64 // Mark as Unread from a message: its (ts, seq); 0 = off
}

// readPrefs reads roomID's prefs, inside the caller's transaction. An unknown room is ErrNotFound.
func (s *Store) readPrefs(ctx context.Context, roomID string) (prefs, error) {
	var p prefs
	var muted, low, hidden, unread int
	err := s.db.QueryRow(ctx, `SELECT COALESCE(p.muted, 0), COALESCE(p.pinned_at, 0), COALESCE(p.archived_at, 0),
		COALESCE(p.low_priority, 0), COALESCE(p.hidden, 0), COALESCE(p.marked_unread, 0), COALESCE(p.draft, ''),
		COALESCE(p.unread_from_ts, 0), COALESCE(p.unread_from_seq, 0)
		FROM rooms r LEFT JOIN room_prefs p ON p.room_id = r.room_id WHERE r.room_id = $1`, roomID).
		Scan(&muted, &p.pinnedAt, &p.archivedAt, &low, &hidden, &unread, &p.draft, &p.unreadFromTS, &p.unreadFromSeq)
	if errors.Is(err, sql.ErrNoRows) {
		return prefs{}, ErrNotFound
	}
	p.muted, p.lowPriority, p.hidden, p.markedUnread = muted == 1, low == 1, hidden == 1, unread == 1
	return p, err
}

// writePrefs upserts roomID's whole prefs row, as SetMuted does, inside the caller's transaction.
func (s *Store) writePrefs(ctx context.Context, roomID string, p prefs) error {
	_, err := s.db.Exec(ctx, `INSERT INTO room_prefs (room_id, muted, pinned_at, archived_at, low_priority, hidden, marked_unread, draft,
		  unread_from_ts, unread_from_seq)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
		ON CONFLICT(room_id) DO UPDATE SET muted=excluded.muted, pinned_at=excluded.pinned_at, archived_at=excluded.archived_at,
		  low_priority=excluded.low_priority, hidden=excluded.hidden, marked_unread=excluded.marked_unread, draft=excluded.draft,
		  unread_from_ts=excluded.unread_from_ts, unread_from_seq=excluded.unread_from_seq`,
		roomID, b2i(p.muted), p.pinnedAt, p.archivedAt, b2i(p.lowPriority), b2i(p.hidden), b2i(p.markedUnread), p.draft,
		p.unreadFromTS, p.unreadFromSeq)
	return err
}

// distinct is ids without repeats, in first-seen order.
func distinct(ids []string) []string {
	seen := make(map[string]bool, len(ids))
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	return out
}

// changePrefs applies change to the prefs of each chat in roomIDs (repeats ignored), all in one transaction, and
// writes back the ones it changed. change reports whether it changed p. An unknown chat is ErrNotFound and
// changes none of them. It returns the chats that changed, in the order given, and publishes a "room" change for
// each.
func (s *Store) changePrefs(ctx context.Context, roomIDs []string, change func(ctx context.Context, p *prefs) (bool, error)) ([]string, error) {
	return s.changePrefsThen(ctx, roomIDs, change, nil)
}

// changePrefsThen is changePrefs that also runs then, when it isn't nil, on the chats that changed, in the same
// transaction.
func (s *Store) changePrefsThen(ctx context.Context, roomIDs []string, change func(ctx context.Context, p *prefs) (bool, error),
	then func(ctx context.Context, changed []string) error,
) ([]string, error) {
	var changed []string
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		changed = nil
		for _, id := range distinct(roomIDs) {
			p, err := s.readPrefs(ctx, id)
			if err != nil {
				return err
			}
			did, err := change(ctx, &p)
			if err != nil {
				return err
			}
			if !did {
				continue
			}
			if err = s.writePrefs(ctx, id, p); err != nil {
				return err
			}
			changed = append(changed, id)
		}
		if then != nil && len(changed) > 0 {
			return then(ctx, changed)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	for _, id := range changed {
		s.publish(Change{Kind: "room", RoomID: id})
	}
	return changed, nil
}

// setFlag is the shared body of the bool setters: pick chooses the field.
func (s *Store) setFlag(ctx context.Context, roomIDs []string, on bool, pick func(*prefs) *bool) ([]string, error) {
	return s.changePrefs(ctx, roomIDs, func(_ context.Context, p *prefs) (bool, error) {
		f := pick(p)
		if *f == on {
			return false, nil
		}
		*f = on
		return true, nil
	})
}

// SetPinned pins or unpins a chat. Pinning also brings it back from the archive: a pinned chat is never
// archived. Pin order is pinned_at, which is kept strictly increasing so that chats pinned within one
// millisecond still keep the order they were pinned in.
func (s *Store) SetPinned(ctx context.Context, roomID string, pinned bool) error {
	_, err := s.changePrefs(ctx, []string{roomID}, func(ctx context.Context, p *prefs) (bool, error) {
		if !pinned {
			if p.pinnedAt == 0 {
				return false, nil
			}
			p.pinnedAt = 0
			return true, nil
		}
		if p.pinnedAt != 0 {
			return false, nil
		}
		var latest int64
		if err := s.db.QueryRow(ctx, "SELECT COALESCE(MAX(pinned_at), 0) FROM room_prefs").Scan(&latest); err != nil {
			return false, err
		}
		p.pinnedAt = max(s.now().UnixMilli(), latest+1)
		p.archivedAt = 0
		return true, nil
	})
	return err
}

// SetArchived archives or unarchives chats, and returns the ones that changed. A pinned chat is never archived:
// it is left out of changed, and when every chat named is pinned the answer is ErrPinned. Unarchiving drops the
// chats' pending auto-archives.
func (s *Store) SetArchived(ctx context.Context, roomIDs []string, archived bool) (changed []string, err error) {
	asked, pinned := 0, 0
	// Ruling 38a: a chat unarchived by hand stays where it was put. An auto-archive scheduled before (after my
	// reply or read) is dropped with the unarchive, so it doesn't archive the chat again when it comes due.
	var dropPending func(ctx context.Context, changed []string) error
	if !archived {
		dropPending = func(ctx context.Context, changed []string) error {
			list, _ := json.Marshal(changed)
			_, err := s.db.Exec(ctx, "DELETE FROM archive_due WHERE room_id IN (SELECT value FROM json_each($1))", string(list))
			return err
		}
	}
	changed, err = s.changePrefsThen(ctx, roomIDs, func(_ context.Context, p *prefs) (bool, error) {
		asked++
		switch {
		case !archived:
			if p.archivedAt == 0 {
				return false, nil
			}
			p.archivedAt = 0
		case p.pinnedAt != 0:
			pinned++
			return false, nil
		case p.archivedAt != 0:
			return false, nil
		default:
			p.archivedAt = s.now().UnixMilli()
		}
		return true, nil
	}, dropPending)
	if err == nil && asked > 0 && pinned == asked {
		return nil, ErrPinned
	}
	return changed, err
}

// SetLowPriority moves chats to or from Low priority, and returns the ones that changed. A new message leaves a
// low-priority chat where it is.
func (s *Store) SetLowPriority(ctx context.Context, roomIDs []string, on bool) ([]string, error) {
	return s.setFlag(ctx, roomIDs, on, func(p *prefs) *bool { return &p.lowPriority })
}

// SetHidden hides or shows chats, and returns the ones that changed. A new message leaves a hidden chat hidden.
func (s *Store) SetHidden(ctx context.Context, roomIDs []string, on bool) ([]string, error) {
	return s.setFlag(ctx, roomIDs, on, func(p *prefs) *bool { return &p.hidden })
}

// SetMarkedUnread marks chats unread (or clears the mark), and returns the ones that changed. Clearing it also clears
// a mark from a message (SetUnreadFrom), in the same write: reading a chat (MarkRead) clears both.
func (s *Store) SetMarkedUnread(ctx context.Context, roomIDs []string, on bool) ([]string, error) {
	if on {
		return s.setFlag(ctx, roomIDs, on, func(p *prefs) *bool { return &p.markedUnread })
	}
	return s.changePrefs(ctx, roomIDs, func(_ context.Context, p *prefs) (bool, error) {
		if !p.markedUnread && p.unreadFromTS == 0 {
			return false, nil
		}
		p.markedUnread, p.unreadFromTS, p.unreadFromSeq = false, 0, 0
		return true, nil
	})
}

// SetUnreadFrom marks roomID unread from eventID on (Mark as Unread from a message, on this Mac only): its unread
// count runs from that message, by its (ts, seq), whatever the read markers say, until the chat is read
// (SetMarkedUnread false). A message of mine is allowed (only other people's messages count), a note is ErrNote, and
// an event that isn't in this chat is ErrNotFound. It publishes a "room" change when the mark moved.
func (s *Store) SetUnreadFrom(ctx context.Context, roomID, eventID string) error {
	e, ok, err := s.GetEvent(ctx, eventID)
	if err != nil {
		return err
	}
	if !ok || e.RoomID != roomID {
		return ErrNotFound
	}
	if isTimerNote(e) || isCallNote(e) {
		return ErrNote
	}
	_, err = s.changePrefs(ctx, []string{roomID}, func(_ context.Context, p *prefs) (bool, error) {
		ts := e.TS.UnixMilli()
		if p.unreadFromTS == ts && p.unreadFromSeq == e.Seq {
			return false, nil
		}
		p.unreadFromTS, p.unreadFromSeq = ts, e.Seq
		return true, nil
	})
	return err
}

// directRoomSQL is the one-to-one chat of network $1 with person $3 for login $2: a direct chat of the network that
// has them as a member and is the login's own or shared by every login (""), the login's own first, then the one with
// the newest message.
const directRoomSQL = `SELECT r.room_id FROM rooms r
WHERE r.network = $1 AND r.is_direct = 1 AND r.login_id IN ($2, '')
  AND EXISTS (SELECT 1 FROM members m WHERE m.room_id = r.room_id AND m.user_id = $3)
ORDER BY r.login_id = $2 DESC, r.last_ts DESC, r.created_at DESC
LIMIT 1`

// DirectRoomWith finds the one-to-one chat Courier already has with userID on network for loginID (Reply
// Privately): the login's own, else one every login shares, newest first. ok is false when there is none; never
// another login's chat, a group or another network's.
func (s *Store) DirectRoomWith(ctx context.Context, network, loginID, userID string) (roomID string, ok bool, err error) {
	err = s.db.QueryRow(ctx, directRoomSQL, network, loginID, userID).Scan(&roomID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	return roomID, err == nil, err
}

// SetDraft keeps the unsent text of a chat's composer; "" clears it. A draft longer than 16,384 characters is
// ErrBadValue.
func (s *Store) SetDraft(ctx context.Context, roomID, text string) error {
	if utf8.RuneCountInString(text) > maxDraftChars {
		return ErrBadValue
	}
	_, err := s.changePrefs(ctx, []string{roomID}, func(_ context.Context, p *prefs) (bool, error) {
		if p.draft == text {
			return false, nil
		}
		p.draft = text
		return true, nil
	})
	return err
}

// SetRequest records whether a chat is a message request (someone new writing first) waiting for me to accept it.
func (s *Store) SetRequest(ctx context.Context, roomID string, request bool) error {
	changed := false
	err := s.db.DoTxn(ctx, nil, func(ctx context.Context) error {
		var cur int
		err := s.db.QueryRow(ctx, "SELECT request FROM rooms WHERE room_id=$1", roomID).Scan(&cur)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil || cur == b2i(request) {
			return err
		}
		_, err = s.db.Exec(ctx, "UPDATE rooms SET request=$2 WHERE room_id=$1", roomID, b2i(request))
		changed = err == nil
		return err
	})
	if err == nil && changed {
		s.publish(Change{Kind: "room", RoomID: roomID})
	}
	return err
}

// ApplyNetworkTag takes in a tag a network reports for a chat. m.favourite is a pin; m.lowpriority is Courier's
// archive (a network's "low priority" is what it shows as archived), except that a pinned chat stays pinned and
// unarchived. Every other tag is ignored.
func (s *Store) ApplyNetworkTag(ctx context.Context, roomID, tag string, on bool) error {
	switch tag {
	case "m.favourite":
		return s.SetPinned(ctx, roomID, on)
	case "m.lowpriority":
		_, err := s.SetArchived(ctx, []string{roomID}, on)
		if errors.Is(err, ErrPinned) {
			return nil // the pin wins
		}
		return err
	}
	return nil
}

// ApplyNetworkMute takes in a network's mute for a chat: muted while until is after now. (Networks say "forever"
// with a far-future time and "not muted" with a past one.)
func (s *Store) ApplyNetworkMute(ctx context.Context, roomID string, until time.Time) error {
	muted := until.After(s.now())
	_, err := s.setFlag(ctx, []string{roomID}, muted, func(p *prefs) *bool { return &p.muted })
	return err
}
