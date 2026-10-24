// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// row is the inbox row of room.
func (w world) row(t *testing.T, room string) store.InboxRow {
	t.Helper()
	rows, err := w.s.Inbox(context.Background())
	require.NoError(t, err)
	for _, r := range rows {
		if r.ID == room {
			return r
		}
	}
	t.Fatalf("room %s not in the inbox", room)
	return store.InboxRow{}
}

// logBuffer is a zerolog destination that is safe to write from the bridge's goroutines and read from the test.
type logBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *logBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

func (l *logBuffer) lines() []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return strings.Split(strings.TrimSpace(l.b.String()), "\n")
}

func TestPinReachesNetworksThatSyncPins(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")

	require.NoError(t, w.a.SetPinned(ctx, room, true))
	require.False(t, w.row(t, room).PinnedAt.IsZero(), "pinned here")
	require.Equal(t, fakenet.TagChange{PortalID: "chat1", Tags: []event.RoomTag{event.RoomTagFavourite}},
		recv(t, w.n.Tags, "the pin"), "a pin is the m.favourite tag")

	require.NoError(t, w.a.SetPinned(ctx, room, false))
	require.True(t, w.row(t, room).PinnedAt.IsZero())
	require.Equal(t, fakenet.TagChange{PortalID: "chat1", Tags: []event.RoomTag{}}, recv(t, w.n.Tags, "the unpin"),
		"an unpin is no tags at all")
	none(t, w.n.Tags, "an extra tag change")

	require.ErrorIs(t, w.a.SetPinned(ctx, "!nope:courier.local", true), store.ErrNotFound)
}

func TestPinOnANetworkWithoutPinsIsLocalOnly(t *testing.T) {
	ctx := context.Background()
	w := startWorldOn(t, "fake", fakenet.NewPlain(), true, zerolog.Nop())
	room, _ := w.chat(t, "chat1", "m1")

	require.NoError(t, w.a.SetPinned(ctx, room, true))
	require.False(t, w.row(t, room).PinnedAt.IsZero(), "pinned here all the same")
	none(t, w.n.Tags, "a pin to a network that takes none")
}

// Review Focus 5: pinning a chat while its network won't take it pins it in Courier at once, keeps it pinned and
// shows no error. The refusal is logged, by network name only.
func TestPinStaysWhenTheNetworkRefuses(t *testing.T) {
	ctx := context.Background()
	logs := &logBuffer{}
	n := fakenet.New()
	w := startWorldOn(t, "fake", n, true, zerolog.New(logs))
	room, _ := w.chat(t, "chat1", "m1")
	n.Refuse = true

	require.NoError(t, w.a.SetPinned(ctx, room, true), "a refusal is no error to the person pinning")
	require.False(t, w.row(t, room).PinnedAt.IsZero(), "and the chat stays pinned")
	none(t, w.n.Tags, "a refused pin")
	time.Sleep(100 * time.Millisecond)
	require.False(t, w.row(t, room).PinnedAt.IsZero(), "nothing puts it back afterwards")

	var warned []string
	for _, l := range logs.lines() {
		if strings.Contains(l, `"change":"pin"`) {
			warned = append(warned, l)
		}
	}
	require.Len(t, warned, 1, "one warning for the refused pin")
	require.Contains(t, warned[0], `"level":"warn"`)
	require.Contains(t, warned[0], `"bridge":"fake"`, "it names the network")
	for _, private := range []string{room, "chat1", "alice", "Fake chat", "refused"} {
		require.NotContains(t, warned[0], private, "it names nothing else")
	}

	// The network takes the next change once it is willing again; nothing retries the old one.
	n.Refuse = false
	require.NoError(t, w.a.SetPinned(ctx, room, false))
	require.Equal(t, fakenet.TagChange{PortalID: "chat1", Tags: []event.RoomTag{}}, recv(t, w.n.Tags, "the unpin"))
	none(t, w.n.Tags, "a retried pin")
}

// Review Focus 5's "offline": a linked network whose login isn't connected. The change stays here at once; it
// is not held for the bridge's reconnect wait (15 s per chat), which a change to many chats would multiply.
func TestPinWhileOfflineIsLocalAndDoesNotWait(t *testing.T) {
	ctx := context.Background()
	logs := &logBuffer{}
	n := fakenet.New()
	n.LoginDelay = time.Hour // linked, never connected during the test
	w := startWorldOn(t, "fake", n, true, zerolog.New(logs))
	room, _ := w.chat(t, "chat1", "m1")

	start := time.Now()
	require.NoError(t, w.a.SetPinned(ctx, room, true))
	require.NoError(t, w.a.SetMuted(ctx, room, true))
	require.Less(t, time.Since(start), 2*time.Second, "nothing waits for the network to come back")
	require.False(t, w.row(t, room).PinnedAt.IsZero())
	require.True(t, w.row(t, room).Muted)
	none(t, w.n.Tags, "a pin while offline")
	none(t, w.n.Mutes, "a mute while offline")
	warns := 0
	for _, l := range logs.lines() {
		if strings.Contains(l, `"change":`) {
			require.Contains(t, l, `"level":"warn"`)
			require.NotContains(t, l, room)
			warns++
		}
	}
	require.Equal(t, 2, warns, "each change that didn't reach the network is logged once")
}

func TestMuteReachesTheNetwork(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")

	require.NoError(t, w.a.SetMuted(ctx, room, true))
	require.True(t, w.row(t, room).Muted)
	require.Equal(t, fakenet.MuteChange{PortalID: "chat1", MutedUntil: -1}, recv(t, w.n.Mutes, "the mute"), "muted for ever")

	require.NoError(t, w.a.SetMuted(ctx, room, false))
	require.False(t, w.row(t, room).Muted)
	require.Equal(t, fakenet.MuteChange{PortalID: "chat1", MutedUntil: 0}, recv(t, w.n.Mutes, "the unmute"))

	require.ErrorIs(t, w.a.SetMuted(ctx, "!nope:courier.local", true), store.ErrNotFound)
	none(t, w.n.Mutes, "a mute of an unknown chat")
}

// An unread mark stays on this Mac: nothing is queued to the network, even one whose client takes marks (the fake
// one does, as WhatsApp's does), because WhatsApp's bridge inverts the flag (see SyncsOf). Reading the chat
// clears the mark and a fired reminder, here only.
func TestMarkUnreadStaysOnThisMacAndMarkReadClearsIt(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")

	changed, err := w.a.SetMarkedUnread(ctx, []string{room}, true)
	require.NoError(t, err)
	require.Equal(t, []string{room}, changed)
	require.True(t, w.row(t, room).MarkedUnread)
	none(t, w.n.Unreads, "an unread mark")

	changed, err = w.a.SetMarkedUnread(ctx, []string{room}, true)
	require.NoError(t, err)
	require.Empty(t, changed)

	require.NoError(t, w.a.MarkRead(ctx, room))
	require.False(t, w.row(t, room).MarkedUnread, "reading the chat clears the mark")
	recv(t, w.n.Receipts, "the read receipt")
	none(t, w.n.Unreads, "the cleared mark")

	changed, err = w.a.SetMarkedUnread(ctx, []string{room}, true)
	require.NoError(t, err)
	require.Equal(t, []string{room}, changed)
	changed, err = w.a.SetMarkedUnread(ctx, []string{room}, false)
	require.NoError(t, err)
	require.Equal(t, []string{room}, changed)
	require.False(t, w.row(t, room).MarkedUnread)
	none(t, w.n.Unreads, "an explicit clear of the mark")

	t.Run("a fired reminder marks unread here only, and reading clears it", func(t *testing.T) {
		now := time.Now()
		require.NoError(t, w.s.SetReminder(ctx, []string{room}, now.Add(time.Minute), "always"))
		w.s.SetClock(func() time.Time { return now.Add(2 * time.Minute) })
		fired, err := w.s.FireDueReminders(ctx)
		w.s.SetClock(time.Now)
		require.NoError(t, err)
		require.Equal(t, []string{room}, fired)
		require.True(t, w.row(t, room).MarkedUnread)
		require.NotNil(t, w.row(t, room).Reminder)

		require.NoError(t, w.a.MarkRead(ctx, room))
		row := w.row(t, room)
		require.False(t, row.MarkedUnread)
		require.Nil(t, row.Reminder, "reading the chat is what the fired reminder was waiting for")
		none(t, w.n.Unreads, "a reminder's mark, set or cleared")
	})
	t.Run("a reminder still to come is left alone", func(t *testing.T) {
		require.NoError(t, w.s.SetReminder(ctx, []string{room}, time.Now().Add(time.Hour), "always"))
		require.NoError(t, w.a.MarkRead(ctx, room))
		require.NotNil(t, w.row(t, room).Reminder)
	})
	t.Run("an unknown chat changes none", func(t *testing.T) {
		_, err := w.a.SetMarkedUnread(ctx, []string{room, "!nope:courier.local"}, true)
		require.ErrorIs(t, err, store.ErrNotFound)
		require.False(t, w.row(t, room).MarkedUnread)
	})
}

func TestAcceptRequestOnlyWhereSupported(t *testing.T) {
	ctx := context.Background()
	request := true
	t.Run("supported", func(t *testing.T) {
		w := startWorld(t, "fake", true)
		w.n.SetChat("chat1", fakenet.Chat{MessageRequest: &request})
		room, _ := w.chat(t, "chat1", "m1")
		require.True(t, w.row(t, room).Request, "fixture: the bridge says the chat is a request")

		require.NoError(t, w.a.AcceptRequest(ctx, room))
		require.False(t, w.row(t, room).Request)
		require.Equal(t, fakenet.Accept{PortalID: "chat1"}, recv(t, w.n.Accepts, "the accept"))
		time.Sleep(100 * time.Millisecond)
		require.False(t, w.row(t, room).Request, "the bridge's own info agrees afterwards")
	})
	t.Run("refused", func(t *testing.T) {
		w := startWorld(t, "fake", true)
		w.n.SetChat("chat1", fakenet.Chat{MessageRequest: &request})
		room, _ := w.chat(t, "chat1", "m1")
		w.n.Refuse = true
		require.NoError(t, w.a.AcceptRequest(ctx, room))
		require.False(t, w.row(t, room).Request, "accepted here all the same")
		none(t, w.n.Accepts, "a refused accept")

		// The bridge never heard of the accept, so the next time it resends the chat's bridge info (on any change
		// of name, avatar, ...) that still says "message request". That must not undo the accept made here.
		h, ok := w.eng.Host("fake")
		require.True(t, ok)
		_, err := h.Bridge.Bot.SendState(ctx, id.RoomID(room), event.StateBridge, "fake://chat1",
			&event.Content{Parsed: &event.BridgeEventContent{Channel: event.BridgeInfoSection{ID: "chat1", MessageRequest: true}}},
			time.Now())
		require.NoError(t, err)
		require.False(t, w.row(t, room).Request, "a resent request flag doesn't undo an accept")
	})
	t.Run("not supported", func(t *testing.T) {
		w := startWorldOn(t, "fake", fakenet.NewPlain(), true, zerolog.Nop())
		w.n.SetChat("chat1", fakenet.Chat{MessageRequest: &request})
		room, _ := w.chat(t, "chat1", "m1")
		require.True(t, w.row(t, room).Request)

		require.ErrorIs(t, w.a.AcceptRequest(ctx, room), ErrNotSupported)
		require.True(t, w.row(t, room).Request, "nothing changes")
		none(t, w.n.Accepts, "an accept to a network that takes none")
	})
	t.Run("unknown chat", func(t *testing.T) {
		w := startWorld(t, "fake", true)
		require.ErrorIs(t, w.a.AcceptRequest(ctx, "!nope:courier.local"), store.ErrNotFound)
	})
}

func TestSyncsFollowTheClient(t *testing.T) {
	require.Equal(t, []string{"pin", "mute", "accept_request"}, startWorld(t, "fake", true).a.Syncs("fake"),
		"never unread, though the fake client takes it: unread marks stay on this Mac")
	require.Empty(t, startWorldOn(t, "fake", fakenet.NewPlain(), true, zerolog.Nop()).a.Syncs("fake"))
	unlinked := startWorld(t, "fake", false)
	require.Empty(t, unlinked.a.Syncs("fake"), "no login, no client to ask")
	require.Empty(t, unlinked.a.Syncs("telegram"), "a network that isn't running")
}

// A change to a chat on a network that isn't running stays here, without an error.
func TestChatStateOnANetworkThatIsNotRunning(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!tg:courier.local", Network: "telegram", Name: "Elsewhere"}))
	require.NoError(t, w.a.SetPinned(ctx, "!tg:courier.local", true))
	require.NoError(t, w.a.SetMuted(ctx, "!tg:courier.local", true))
	_, err := w.a.SetMarkedUnread(ctx, []string{"!tg:courier.local"}, true)
	require.NoError(t, err)
	row := w.row(t, "!tg:courier.local")
	require.False(t, row.PinnedAt.IsZero())
	require.True(t, row.Muted)
	require.True(t, row.MarkedUnread)
	require.ErrorIs(t, w.a.AcceptRequest(ctx, "!tg:courier.local"), ErrNotSupported)
}

// A chat change made while the network is down stays here at once and reaches the network when its login is back
// (the loop's SendWaiting tells it), once, as it stands then: a pin undone while down sends the unpin only.
func TestChatChangesWhileOfflineReachTheNetworkWhenItConnects(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	w.down()
	require.NoError(t, w.a.SetPinned(ctx, room, true))
	require.NoError(t, w.a.SetPinned(ctx, room, false))
	require.NoError(t, w.a.SetMuted(ctx, room, true))
	none(t, w.n.Tags, "a pin while down")
	none(t, w.n.Mutes, "a mute while down")

	w.a.SendWaiting(ctx, "fake")
	none(t, w.n.Tags, "a pin while still down")

	w.up()
	w.a.SendWaiting(ctx, "fake")
	require.Equal(t, fakenet.TagChange{PortalID: "chat1", Tags: []event.RoomTag{}}, recv(t, w.n.Tags, "the unpin"))
	require.Equal(t, fakenet.MuteChange{PortalID: "chat1", MutedUntil: -1}, recv(t, w.n.Mutes, "the mute"))
	w.a.SendWaiting(ctx, "fake")
	none(t, w.n.Tags, "the change told twice")
	none(t, w.n.Mutes, "the change told twice")

	// A change told while connected isn't told again later.
	require.NoError(t, w.a.SetPinned(ctx, room, true))
	recv(t, w.n.Tags, "the pin")
	w.a.SendWaiting(ctx, "fake")
	none(t, w.n.Tags, "the pin told twice")
}

// Task 2's carry: a chat change made while the network is still starting (pin, read) stays here at once and reaches
// the network once it runs and its login is in.
func TestChatChangesWhileStartingReachTheNetworkOnceItRuns(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	starting, up := w.restart(t, "fake")
	require.NoError(t, starting.a.SetPinned(ctx, room, true))
	require.NoError(t, starting.a.SetMuted(ctx, room, true))
	require.ErrorIs(t, starting.a.MarkRead(ctx, room), engine.ErrStarting, "read here; the network can't be told yet")
	require.Zero(t, starting.unread(t, room))
	none(t, w.n.Tags, "a pin while starting")

	running := up()
	running.a.SendWaiting(ctx, "fake")
	require.Equal(t, fakenet.TagChange{PortalID: "chat1", Tags: []event.RoomTag{event.RoomTagFavourite}}, recv(t, w.n.Tags, "the pin"))
	require.Equal(t, fakenet.MuteChange{PortalID: "chat1", MutedUntil: -1}, recv(t, w.n.Mutes, "the mute"))
	require.Equal(t, fakenet.Receipt{PortalID: "chat1", MessageID: "m1"}, recv(t, w.n.Receipts, "the receipt"))
	running.a.SendWaiting(ctx, "fake")
	none(t, w.n.Tags, "the pin told twice")
	none(t, w.n.Receipts, "the receipt told twice")
}

// A direct tell made while a retell is under way wins: a kept change taken for retelling, then superseded by a newer
// change of its chat told directly, is never told after it (review fix round 1).
func TestADirectChangeDuringARetellWins(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	h, ok := w.eng.Host("fake")
	require.True(t, ok)
	w.down()
	require.NoError(t, w.a.SetPinned(ctx, room, true)) // kept
	w.n.SetLoggedIn(w.login, true)

	kept := w.a.untold.take("fake")                     // the retell has taken it...
	require.NoError(t, w.a.SetPinned(ctx, room, false)) // ...when the unpin is told directly
	require.Equal(t, fakenet.TagChange{PortalID: "chat1", Tags: []event.RoomTag{}}, recv(t, w.n.Tags, "the unpin"))
	w.a.retellKept(ctx, h, kept)
	none(t, w.n.Tags, "the superseded pin, after the unpin")

	// A newer change kept while the older was taken supersedes it too, and is told itself next time.
	w.down()
	require.NoError(t, w.a.SetMuted(ctx, room, true))
	w.n.SetLoggedIn(w.login, true)
	kept = w.a.untold.take("fake")
	w.down()
	require.NoError(t, w.a.SetMuted(ctx, room, false)) // kept, newer
	w.n.SetLoggedIn(w.login, true)
	w.a.retellKept(ctx, h, kept)
	none(t, w.n.Mutes, "the superseded mute")
	w.a.SendWaiting(ctx, "fake")
	require.Equal(t, fakenet.MuteChange{PortalID: "chat1", MutedUntil: 0}, recv(t, w.n.Mutes, "the unmute"))
}

// twoNetworks runs two fake networks, "fake" and "other", in one engine over one store, each linked, with one chat
// each. It returns the actions, both networks and the two chats.
func twoNetworks(t *testing.T) (a *Actions, fake, other *fakenet.Network, fakeRoom, otherRoom string) {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	m := &media.Store{Dir: filepath.Join(dir, "media")}
	fake, other = fakenet.New(), fakenet.New()
	eng, errs := engine.Start(ctx, dir, s, m, []engine.Spec{
		{Name: "fake", Connector: func() (bridgev2.NetworkConnector, error) { return fake, nil }},
		{Name: "other", Connector: func() (bridgev2.NetworkConnector, error) { return other, nil }},
	}, zerolog.Nop())
	require.Empty(t, errs)
	t.Cleanup(eng.Stop)
	rooms := map[string]string{}
	for name, n := range map[string]*fakenet.Network{"fake": fake, "other": other} {
		h, ok := eng.Host(name)
		require.True(t, ok)
		login, err := n.Login(ctx, h.Bridge)
		require.NoError(t, err)
		n.Incoming(login, "chat-"+name, "alice", "m-"+name, "hi")
	}
	require.Eventually(t, func() bool { // setup only: the bridges make the chats behind us
		list, err := s.ListRooms(ctx)
		if err != nil {
			return false
		}
		for _, r := range list {
			rooms[r.Network] = r.ID
		}
		return rooms["fake"] != "" && rooms["other"] != ""
	}, 5*time.Second, 20*time.Millisecond, "the bridges never made the chats")
	return New(eng, s, m), fake, other, rooms["fake"], rooms["other"]
}

// A chat change held up mid-delivery on one network holds up no other network's: each network tells its own changes
// one at a time, not every network's together (review fix round 2).
func TestABlockedTellOnOneNetworkDoesntHoldUpAnother(t *testing.T) {
	ctx := context.Background()
	a, fake, other, fakeRoom, otherRoom := twoNetworks(t)
	fake.Holding = make(chan struct{}, 4)
	fake.HoldChanges = make(chan struct{})
	var once sync.Once
	release := func() { once.Do(func() { close(fake.HoldChanges) }) }
	t.Cleanup(release) // before the engine stops: the held tell must end
	pinned := make(chan error, 1)
	go func() { pinned <- a.SetPinned(ctx, fakeRoom, true) }()
	awaitHolding(t, fake, "the pin on fake")

	done := make(chan error, 1)
	go func() { done <- a.SetPinned(ctx, otherRoom, true) }()
	select {
	case err := <-done:
		require.NoError(t, err)
	case <-time.After(5 * time.Second): // a deadlock guard, not a measure
		t.Fatal("a pin on other waited for fake's held pin")
	}
	require.Equal(t, fakenet.TagChange{PortalID: "chat-other", Tags: []event.RoomTag{event.RoomTagFavourite}}, recv(t, other.Tags, "other's pin"))
	release()
	require.NoError(t, <-pinned)
	require.Equal(t, fakenet.TagChange{PortalID: "chat-fake", Tags: []event.RoomTag{event.RoomTagFavourite}}, recv(t, fake.Tags, "fake's pin"))
}

// A direct tell that waited for its network's tell lock while a newer change of its chat was kept (the login dropped
// meanwhile) is superseded: it isn't told, and doesn't throw the newer kept one away. Here a pin waits, the login
// drops, an unpin is kept, and then the pin gets the lock: the network is never pinned, and hears the unpin once the
// login is back (review fix round 2).
func TestADirectTellThatWaitedNeverUndoesANewerKeptChange(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	h, ok := w.eng.Host("fake")
	require.True(t, ok)
	key := untoldKey{room: room, change: syncPin}
	pin := &event.Event{
		Type: event.AccountDataRoomTags, RoomID: id.RoomID(room), Sender: "@me:courier.local",
		Content: event.Content{Parsed: &event.TagEventContent{Tags: event.Tags{event.RoomTagFavourite: {}}}},
	}
	pinGen := w.a.untold.stamp() // the pin has passed its login check and waits for the lock...

	w.down()
	require.NoError(t, w.a.SetPinned(ctx, room, false)) // ...when the login drops and an unpin is kept
	w.n.SetLoggedIn(w.login, true)
	w.a.tellNow(ctx, h, key, syncPin, pin, pinGen) // the pin gets the lock
	none(t, w.n.Tags, "the older pin, over the newer kept unpin")

	w.a.SendWaiting(ctx, "fake")
	require.Equal(t, fakenet.TagChange{PortalID: "chat1", Tags: []event.RoomTag{}}, recv(t, w.n.Tags, "the kept unpin"))
}
