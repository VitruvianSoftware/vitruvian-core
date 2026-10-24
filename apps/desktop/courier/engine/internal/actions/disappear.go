// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"time"

	"go.mau.fi/util/jsontime"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
)

// SetDisappearing sets a chat's disappearing-message timer: typ "after_send" or "after_read" with a timer the chat
// offers (Features.Disappearing), or typ "" (and no timer) to turn it off. A chat whose network has no timer is
// ErrNotSupported; a type or length it doesn't offer ErrBadValue.
//
// Unlike a pin or a mute, the timer is the network's: the change is sent and waited on, and only once the network
// takes it is it stored here (the chat's com.beeper.disappearing_timer state, which Send reads) and the chat
// published as changed. A network that refuses it changes nothing, and is ErrNetworkRefused with the bridge's
// reason.
//
// A change the network took also leaves a note in the chat, as one made on the phone does (Ruling 40): no pinned
// bridge sends one for a change made here (see store.InsertTimerNote), so the engine writes it, mine, in the
// bridge's shape, and never sends it. A timer the chat already had changes nothing and leaves none.
func (a *Actions) SetDisappearing(ctx context.Context, roomID, typ string, timer time.Duration) error {
	h, err := a.eng.HostForRoom(ctx, roomID)
	if err != nil {
		return err
	}
	f, err := a.Features(ctx, roomID)
	if err != nil {
		return err
	}
	if f.Disappearing == nil {
		return ErrNotSupported
	}
	content := &event.BeeperDisappearingTimer{Type: event.DisappearingType(typ), Timer: jsontime.MS(timer)}
	switch {
	case typ == "" && timer == 0:
	case typ != f.Disappearing.Type || !slices.Contains(f.Disappearing.Timers, timer):
		return ErrBadValue
	}
	if err = a.waitLogin(ctx, h); err != nil {
		return err
	}
	empty := ""
	// What arrived before the change was sent: a bridge's note of the same change arriving after this is the
	// network telling it, and then it is the only note.
	afterSeq := a.s.LastSeq()
	ts := a.now()
	res := h.Bridge.QueueMatrixEvent(ctx, &event.Event{
		Type: event.StateBeeperDisappearingTimer, RoomID: id.RoomID(roomID), Sender: ids.Me, ID: ids.RandomEventID(),
		StateKey: &empty, Timestamp: ts.UnixMilli(), Content: event.Content{Parsed: content},
	})
	// A timer the chat already has is "ignored" with no error: nothing to change, and nothing went wrong.
	if !res.Success || res.Error != nil {
		if res.Error != nil {
			return fmt.Errorf("%w: %w", ErrNetworkRefused, res.Error)
		}
		return ErrNetworkRefused
	}
	raw, err := json.Marshal(content)
	if err != nil {
		return err
	}
	changed, err := a.s.SetState(ctx, roomID, event.StateBeeperDisappearingTimer.Type, "", raw)
	if err != nil {
		return err
	}
	if changed {
		a.s.RoomChanged(roomID)
	}
	if res.Ignored {
		return nil
	}
	_, err = a.s.InsertTimerNote(ctx, roomID, string(ids.RandomEventID()), typ, timer, ts, afterSeq)
	return err
}
