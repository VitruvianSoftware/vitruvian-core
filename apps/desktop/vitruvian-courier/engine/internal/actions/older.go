// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"errors"
	"sync"
	"time"

	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/host"
)

// Loading older history. Vitruvian Courier keeps a chat's newest messages from the network and nothing more until the
// person asks: when they scroll to the top of a chat, the app calls room.loadOlder, which is LoadOlder. Nothing is
// filled in the background (host.Start leaves bridgev2's backwards queue off).

const (
	// exhaustedCooldown is how long a chat that has nothing older answers "nothing more" without asking again.
	exhaustedCooldown = 30 * time.Second
	// pendingCooldown is how long a chat whose network was asked and will answer later (WhatsApp asks the phone) is
	// not asked again: the answer arrives by itself and is backfilled when it does.
	pendingCooldown = 20 * time.Second
)

// loadOlderWait is how long LoadOlder waits for a page. A variable so a test can shorten it.
var loadOlderWait = 45 * time.Second

// LoadOlderResult is what LoadOlder did.
type LoadOlderResult struct {
	// Added is how many messages the page stored (parts of a message count each).
	Added int `json:"added"`
	// HasMore says older messages may remain: false once the network has no more, or can't give any.
	HasMore bool `json:"has_more"`
	// Loading says the page isn't in yet: another load of this chat is running, or the network was asked and will
	// answer later. The messages arrive by themselves, as new events.
	Loading bool `json:"loading"`
}

type olderState struct {
	mu       sync.Mutex
	running  map[string]bool
	cooldown map[string]olderCooldown
}

type olderCooldown struct {
	until  time.Time
	result LoadOlderResult
}

// LoadOlder loads ONE page of roomID's older history from its network (bridgev2's manual backwards backfill, which
// writes through the connector's BatchSend) and says how many messages came and whether more remain.
//
//   - One load per chat at a time: a call while one runs returns at once with Loading.
//   - A chat that has nothing older (its backfill task is done, or its network can't backfill) answers from a short
//     cooldown; one whose network will answer later (WhatsApp's phone) is Loading for a while.
//   - A network that has no backwards fetch (host.CanLoadOlder, a client that isn't a bridgev2.BackfillingNetworkAPI)
//     is HasMore false, so the app shows nothing. A network that isn't running, or a login that isn't connected, is
//     HasMore true with nothing added: nothing is known, and the next scroll asks again.
//
// An unknown chat is store.ErrNotFound. Never logs who.
func (a *Actions) LoadOlder(ctx context.Context, roomID string) (LoadOlderResult, error) {
	room, h, err := a.chatHost(ctx, roomID)
	if err != nil {
		return LoadOlderResult{}, err
	}
	if !host.CanLoadOlder(room.Network) {
		return LoadOlderResult{}, nil
	}
	if h == nil {
		return LoadOlderResult{HasMore: true}, nil
	}
	st := &a.older
	st.mu.Lock()
	if st.running[roomID] {
		st.mu.Unlock()
		return LoadOlderResult{HasMore: true, Loading: true}, nil
	}
	if c, ok := st.cooldown[roomID]; ok {
		if a.now().Before(c.until) {
			st.mu.Unlock()
			return c.result, nil
		}
		delete(st.cooldown, roomID)
	}
	if st.running == nil {
		st.running = map[string]bool{}
	}
	st.running[roomID] = true
	st.mu.Unlock()
	res, cool, err := a.loadOlder(ctx, h, roomID)
	st.mu.Lock()
	delete(st.running, roomID)
	if err == nil && cool > 0 {
		if st.cooldown == nil {
			st.cooldown = map[string]olderCooldown{}
		}
		// What stands is the answer, not the page: a call inside the cooldown added nothing.
		again := res
		again.Added = 0
		st.cooldown[roomID] = olderCooldown{until: a.now().Add(cool), result: again}
	}
	st.mu.Unlock()
	return res, err
}

// loadOlder is LoadOlder's work for a chat nobody else is loading. cool is how long the answer stands.
func (a *Actions) loadOlder(ctx context.Context, h *host.Host, roomID string) (res LoadOlderResult, cool time.Duration, err error) {
	portal, login := a.portalAndLogin(ctx, roomID)
	if portal == nil || login == nil {
		return LoadOlderResult{HasMore: true}, 0, nil // the chat's login isn't connected: nothing is known
	}
	if _, ok := login.Client.(bridgev2.BackfillingNetworkAPI); !ok {
		return LoadOlderResult{}, exhaustedCooldown, nil
	}
	db := h.Bridge.DB
	task, err := db.BackfillTask.GetNextForPortal(ctx, portal.PortalKey, true)
	if err != nil {
		return LoadOlderResult{}, 0, err
	}
	if task == nil || task.IsDone || task.UserLoginID == "" {
		return LoadOlderResult{}, exhaustedCooldown, nil
	}
	before, err := db.Message.CountMessagesInPortal(ctx, portal.PortalKey)
	if err != nil {
		return LoadOlderResult{}, 0, err
	}
	done := make(chan error, 1) // buffered: a page the network answers after we stopped waiting still has a place to go
	bg := portal.Log.WithContext(h.Bridge.BackgroundCtx)
	mt := &bridgev2.ManualBackfill{Source: login, Portal: portal, DoneCallback: func(e error) {
		select {
		case done <- e:
		default:
		}
		// A network that answers later (WhatsApp's phone) calls this when its answer is in: the chat may be asked for
		// the next page again, without waiting out the cooldown of the pending one.
		a.older.mu.Lock()
		delete(a.older.cooldown, roomID)
		a.older.mu.Unlock()
	}}
	returned := make(chan struct{})
	go func() { defer close(returned); mt.Do(bg) }()
	select {
	case <-returned:
	case <-time.After(loadOlderWait):
		return LoadOlderResult{HasMore: true, Loading: true}, pendingCooldown, nil
	case <-ctx.Done():
		return LoadOlderResult{HasMore: true, Loading: true}, 0, ctx.Err()
	}
	// Do calls the callback when the page is done. A network that answers later (WhatsApp's phone: the request is
	// sent and Do returns) leaves it for when the answer comes, which is what Loading says.
	var doneErr error
	select {
	case doneErr = <-done:
	default:
		return LoadOlderResult{HasMore: true, Loading: true}, pendingCooldown, nil
	}
	task, terr := db.BackfillTask.GetNextForPortal(ctx, portal.PortalKey, true)
	after, cerr := db.Message.CountMessagesInPortal(ctx, portal.PortalKey)
	if err = errors.Join(terr, cerr); err != nil {
		return LoadOlderResult{}, 0, err
	}
	res = LoadOlderResult{Added: max(after-before, 0), HasMore: task != nil && !task.IsDone}
	if doneErr != nil && res.HasMore {
		return LoadOlderResult{}, 0, doneErr
	}
	if !res.HasMore {
		return res, exhaustedCooldown, nil
	}
	return res, 0, nil
}
