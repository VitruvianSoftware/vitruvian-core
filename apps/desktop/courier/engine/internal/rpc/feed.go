// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

import (
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// changed is the params of a changed notification: what changed, so the app knows what to re-query.
type changed struct {
	Kind    string `json:"kind"`
	RoomID  string `json:"room_id,omitempty"`
	EventID string `json:"event_id,omitempty"`
	Network string `json:"network,omitempty"`
}

type notificationLine struct {
	JSONRPC string  `json:"jsonrpc"`
	Method  string  `json:"method"`
	Params  changed `json:"params"`
}

// notification maps one store change to what the app is told. Members and profiles change what a chat's row
// shows, so they are room changes; a profile can be in any chat, so its change names none. A reminder that fires
// is a room change too (the store publishes both), and "reminder" besides, so the app can notify. A kind this code does
// not know becomes a resync: the app re-reads everything rather than miss something.
func notification(c store.Change) changed {
	switch c.Kind {
	case "room", "member":
		return changed{Kind: "room", RoomID: c.RoomID}
	case "profile":
		return changed{Kind: "room"}
	case "event", "status", "read":
		return changed{Kind: c.Kind, RoomID: c.RoomID, EventID: c.EventID}
	case "bridge":
		return changed{Kind: "bridge", Network: c.RoomID} // the store keeps a bridge change's network in RoomID
	case "spaces": // labels, the layout, or an account's or label's space settings: no one chat
		return changed{Kind: "spaces"}
	// scheduled: a chat's scheduled messages changed (Ruling 7). receipt: a read receipt or a delivery arrived for
	// a message in the chat (protocol 5).
	case "typing", "reminder", "scheduled", "receipt":
		return changed{Kind: c.Kind, RoomID: c.RoomID}
	default: // store.ChangeResync, and anything newer than this code
		return changed{Kind: store.ChangeResync}
	}
}

// startFeed forwards feed, the connection's subscription to the store's change feed, once, after its hello's
// answer is queued (the subscription began before it). The feed waits for the writer like any sender, so a client
// that stops reading backs up into the store's buffer, and the store drops changes for it. The client hears about
// that as one resync, whichever way comes first: in band, before the next change the store can hand over, or from
// here, as soon as the feed has caught up with what was kept. It is told even if nothing changes after the drop.
func (c *conn) startFeed(feed *store.Feed) {
	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		defer feed.Close()
		forward := func(ch store.Change) bool {
			line, err := encodeLine(notificationLine{JSONRPC: "2.0", Method: "changed", Params: notification(ch)})
			return err != nil || c.send(line)
		}
		for {
			select { // first whatever is waiting
			case ch := <-feed.C:
				if !forward(ch) {
					return
				}
				continue
			default:
			}
			if feed.TakeDropped() { // caught up after a drop
				if !forward(store.Change{Kind: store.ChangeResync}) {
					return
				}
				continue
			}
			select {
			case <-c.ctx.Done():
				return
			case ch := <-feed.C:
				if !forward(ch) {
					return
				}
			}
		}
	}()
}
