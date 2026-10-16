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
// shows, so they are room changes; a profile can be in any chat, so its change names none. A kind this code does
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
	default: // store.ChangeResync, and anything newer than this code
		return changed{Kind: store.ChangeResync}
	}
}

// startFeed subscribes the connection to the store's change feed, once, after its hello. The feed waits for the
// writer like any sender, so a client that stops reading backs up into the store's buffer; the store then drops
// changes for it and, before the next one it can take, hands it a resync, which goes out like any other.
func (c *conn) startFeed() {
	changes, unsubscribe := c.d.Store.Subscribe()
	c.wg.Add(1)
	go func() {
		defer c.wg.Done()
		defer unsubscribe()
		for {
			select {
			case <-c.ctx.Done():
				return
			case ch := <-changes:
				line, err := encodeLine(notificationLine{JSONRPC: "2.0", Method: "changed", Params: notification(ch)})
				if err != nil {
					continue
				}
				if !c.send(line) {
					return
				}
			}
		}
	}()
}
