// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

// Batch send: how bridgev2 writes a backfill (portalbackfill.go sendBatch) once the connector reports BatchSending.
//
// A Matrix server has no way to put events before a room's first one, which is why bridgev2 only runs its backwards
// backfill queue where batch sending exists (Beeper's server). Vitruvian Courier's store is not a Matrix server: it
// puts an event in a chat's timeline by the event's own time (ts, seq), so an old event written now simply lands
// before the newer ones. That makes BatchSend an ordinary insert, and with it the backfill queue
// (host.go: Backfill.Queue) can fetch older and older pages of a chat from its network.

import (
	"context"
	"encoding/json"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// storedEvent is the store row for an event a bridge sends (Intent.SendMessage, BatchSend): the content with the
// annotations the app relies on, and Slack's join notice turned into the membership change it is. senderName is the
// sender's display name, "" to look it up.
func (c *Connector) storedEvent(ctx context.Context, roomID id.RoomID, evtID id.EventID, sender id.UserID, evtType event.Type,
	content *event.Content, ts time.Time, senderName string,
) (store.Event, error) {
	raw, err := json.Marshal(content)
	if err != nil {
		return store.Event{}, err
	}
	// A call notice is stored with Vitruvian Courier's reading of it, which only its network's bridge can say.
	raw = store.AnnotateCallNote(c.network, evtType.Type, raw)
	ev := store.Event{
		RoomID: string(roomID), EventID: string(evtID), Sender: string(sender),
		Type: evtType.Type, Content: raw, TS: ts, Status: "sent",
	}
	// Slack's "X has joined the channel" is a membership change, not a message: stored as one, it shows as the
	// centered membership line and is never unread or a preview.
	if senderName == "" {
		if prof, found, _ := c.store.GetProfile(ctx, string(sender)); found {
			senderName = prof.DisplayName
		}
	}
	if membership, ok := store.MembershipNote(c.network, evtType.Type, raw, string(sender), senderName); ok {
		sk := string(sender)
		ev.Type, ev.StateKey = event.StateMember.Type, &sk
		ev.Content, _ = json.Marshal(map[string]any{"membership": membership, "state_key": sk, "target_user_id": sk})
	}
	return ev, nil
}

// BatchSend stores a backfill's events, which bridgev2 hands over in chronological order (extras[i] describes
// req.Events[i]; both are empty or equal in length).
//
// Placement. An event's place in the chat is its own time, so there is nothing to "put before" the existing events:
// a page of older history (a backwards backfill: req.Forward false) is written like any other and sorts before the
// first message. req.Forward and req.ForwardIfNoMessages say where Matrix should put the batch and need no action.
//
// Idempotence. The IDs are the deterministic ones bridgev2 made (GenerateDeterministicEventID), and the store skips
// an event it has, so running a batch again, or one that overlaps a page already stored, adds nothing. A batch is one
// transaction: it is stored whole or not at all.
//
// Unread and notifications. Backfilled events keep their original time. The app notifies only for an event newer than
// its own start and no older than two minutes (NotificationPolicy.shouldNotify), so history never notifies, and
// req.SendNotification has nothing to switch on here. Unread is by position after the read marker, so:
//   - a forward batch (new chat, or catching up) is read exactly when bridgev2 says so (req.MarkReadBy): the marker moves to
//     its newest message, as bridgev2's one-by-one backfill did through MarkRead;
//   - a backwards batch is history by definition and is always read through: the marker moves to its newest event, which
//     is a no-op when the chat has been read past it and otherwise leaves only the chat's own newer messages unread. A
//     year of old messages must never turn into a year of unread.
//
// A message of mine that the network says arrived already read gets its receipt, as Intent.SendMessage does.
func (c *Connector) BatchSend(ctx context.Context, roomID id.RoomID, req *mautrix.ReqBeeperBatchSend, extras []*bridgev2.MatrixSendExtra) (*mautrix.RespBeeperBatchSend, error) {
	resp := &mautrix.RespBeeperBatchSend{}
	if req == nil || len(req.Events) == 0 {
		return resp, nil
	}
	forward := req.Forward
	if !forward && req.ForwardIfNoMessages {
		empty, err := c.store.RoomHasNoMessages(ctx, string(roomID))
		if err != nil {
			return nil, err
		}
		forward = empty
	}
	names := map[id.UserID]string{} // a sender's display name, looked up once per batch
	rows := make([]store.Event, 0, len(req.Events))
	for i, evt := range req.Events {
		if evt == nil {
			continue
		}
		var extra *bridgev2.MatrixSendExtra
		if i < len(extras) {
			extra = extras[i]
		}
		ts := time.UnixMilli(evt.Timestamp)
		evtID := evt.ID
		if extra != nil && extra.MessageMeta != nil && evtID == "" {
			m := extra.MessageMeta
			evtID = ids.EventID(roomID, m.Room, m.ID, m.PartID)
		}
		if evtID == "" {
			evtID = ids.RandomEventID() // not reached through bridgev2, which always names its events
		}
		name, ok := names[evt.Sender]
		if !ok {
			if prof, found, _ := c.store.GetProfile(ctx, string(evt.Sender)); found {
				name = prof.DisplayName
			}
			names[evt.Sender] = name
		}
		row, err := c.storedEvent(ctx, roomID, evtID, evt.Sender, evt.Type, &evt.Content, ts, name)
		if err != nil {
			return nil, err
		}
		rows = append(rows, row)
	}
	if _, err := c.store.InsertEvents(ctx, rows); err != nil {
		return nil, err
	}
	// Everything below is best effort and repeatable: the events are stored, and a failure is logged, not returned,
	// so bridgev2 does not retry a batch that already landed.
	c.afterBatch(ctx, roomID, req, extras, rows, forward)
	for _, row := range rows {
		resp.EventIDs = append(resp.EventIDs, id.EventID(row.EventID))
	}
	return resp, nil
}

// afterBatch does what follows a stored batch: the reads messages of mine arrived with, and the read marker.
func (c *Connector) afterBatch(ctx context.Context, roomID id.RoomID, req *mautrix.ReqBeeperBatchSend,
	extras []*bridgev2.MatrixSendExtra, rows []store.Event, forward bool,
) {
	// extras and rows are index-aligned only when no event was nil: match them through the event ID instead.
	meta := make(map[string]*bridgev2.MatrixSendExtra, len(extras))
	for i, e := range req.Events {
		if e != nil && i < len(extras) && extras[i] != nil {
			meta[string(e.ID)] = extras[i]
		}
	}
	var newest *store.Event
	for i := range rows {
		row := &rows[i]
		if row.Type == event.EventReaction.Type {
			continue
		}
		if x := meta[row.EventID]; x != nil && x.MessageMeta != nil && arrivedRead(c.network, x.MessageMeta.Metadata) &&
			newIntent(c, id.UserID(row.Sender), false).isMine(ctx) {
			c.readOnArrival(ctx, string(roomID), row.EventID)
		}
		if newest == nil || row.TS.UnixMilli() >= newest.TS.UnixMilli() {
			newest = row
		}
	}
	if newest == nil || (forward && !c.isMeUser(ctx, req.MarkReadBy)) {
		return
	}
	if err := c.store.SetRead(ctx, string(roomID), newest.EventID, newest.TS); err != nil {
		c.log.Warn().Err(err).Str("network", c.network).Msg("failed to mark a backfilled chat read")
	}
}

// isMeUser reports whether user is me (my Matrix ID, or my own network user's ghost).
func (c *Connector) isMeUser(ctx context.Context, user id.UserID) bool {
	if user == "" {
		return false
	}
	if user == ids.Me {
		return true
	}
	ghost, ok := ids.ParseGhostMXID(c.network, user)
	return ok && c.isMe(ctx, ghost)
}
