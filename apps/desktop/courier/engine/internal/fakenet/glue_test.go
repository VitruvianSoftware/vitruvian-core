// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package fakenet

import (
	"context"
	"encoding/json"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"go.mau.fi/util/jsontime"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/bridgeconfig"
	"maunium.net/go/mautrix/bridgev2/commands"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/localmatrix"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func TestRemoteMessageLandsAndReplyGoesOut(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	// br.Stop closes the bridge database itself (ExternallyManagedDB is false), so bdb needs no Close here.
	bdb, err := sqlite.Open(filepath.Join(dir, "fake.db"))
	require.NoError(t, err)
	net := New()
	conn := localmatrix.New("fake", s, &media.Store{Dir: filepath.Join(dir, "media")})
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix: "!fake",
		Permissions:   bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
	}
	br := bridgev2.NewBridge("fake", bdb, zerolog.New(zerolog.NewTestWriter(t)), cfg, conn, net, func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	defer br.Stop()

	login, err := net.Login(ctx, br)
	require.NoError(t, err)

	net.Incoming(login, "chat1", "alice", "m1", "hello from the network")

	// Don't assume how bridgev2 picks the room ID: find whichever room received the message.
	var roomID id.RoomID
	require.Eventually(t, func() bool {
		// Eventually runs this off the test goroutine, so report errors with t.Error rather than FailNow.
		rooms, err := s.ListRooms(ctx)
		if err != nil {
			t.Error(err)
			return false
		}
		for _, r := range rooms {
			evs, err := s.Events(ctx, r.ID, 10)
			if err != nil {
				t.Error(err)
				return false
			}
			for _, e := range evs {
				if e.Type == event.EventMessage.Type && strings.Contains(string(e.Content), "hello from the network") {
					roomID = id.RoomID(r.ID)
					return true
				}
			}
		}
		return false
	}, 5*time.Second, 50*time.Millisecond, "remote message never reached courier.db")

	// Exactly one such message, in a room of this network, sent by the remote user's ghost.
	rooms, err := s.ListRooms(ctx)
	require.NoError(t, err)
	var matches []store.Event
	for _, r := range rooms {
		evs, err := s.Events(ctx, r.ID, 50)
		require.NoError(t, err)
		for _, e := range evs {
			if e.Type == event.EventMessage.Type && strings.Contains(string(e.Content), "hello from the network") {
				require.Equal(t, "fake", r.Network)
				matches = append(matches, e)
			}
		}
	}
	require.Len(t, matches, 1)
	require.Equal(t, string(ids.GhostMXID("fake", "alice")), matches[0].Sender)

	// The reply follows the production order: the app stores the user's event as pending, then queues it.
	reply := &event.Event{
		Type: event.EventMessage, RoomID: roomID, Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: time.Now().UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: "hi alice"}},
	}
	raw, err := json.Marshal(&reply.Content)
	require.NoError(t, err)
	inserted, err := s.InsertEvent(ctx, store.Event{
		RoomID: string(roomID), EventID: string(reply.ID), Sender: string(ids.Me),
		Type: event.EventMessage.Type, Content: raw, TS: time.Now(), Status: "pending",
	})
	require.NoError(t, err)
	require.True(t, inserted)
	br.QueueMatrixEvent(ctx, reply)
	select {
	case got := <-net.Sent:
		require.Equal(t, Sent{PortalID: "chat1", Body: "hi alice"}, got)
	case <-time.After(5 * time.Second):
		t.Fatal("reply never reached the fake network")
	}

	// The bridge reports the outcome back through SendMessageStatus; it must land on the stored event.
	require.Eventually(t, func() bool {
		e, ok, err := s.GetEvent(ctx, string(reply.ID))
		if err != nil {
			t.Error(err)
			return false
		}
		return ok && e.Status == "sent"
	}, 5*time.Second, 50*time.Millisecond, "reply status never became sent in courier.db")
}

// recvOne waits for one value on ch.
func recvOne[T any](t *testing.T, ch <-chan T, what string) T {
	t.Helper()
	select {
	case v := <-ch:
		return v
	case <-time.After(5 * time.Second):
		t.Fatalf("no %s reached the fake network", what)
	}
	var zero T
	return zero
}

// Edits, deletions, polls, votes and disappearing-timer changes the bridge lets through (the room features say
// it may) land on their channels, as the network would get them.
func TestMessageChangesReachTheNetwork(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	bdb, err := sqlite.Open(filepath.Join(dir, "fake.db"))
	require.NoError(t, err)
	net := New()
	net.Features = &event.RoomFeatures{
		Reply: event.CapLevelFullySupported, Edit: event.CapLevelFullySupported, Delete: event.CapLevelFullySupported,
		Poll: event.CapLevelFullySupported, PollMaxOptions: 12, PollOptionMaxLength: 100,
		DisappearingTimer: &event.DisappearingTimerCapability{Types: []event.DisappearingType{event.DisappearingTypeAfterSend}},
	}
	conn := localmatrix.New("fake", s, &media.Store{Dir: filepath.Join(dir, "media")})
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix: "!fake",
		Permissions:   bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
	}
	br := bridgev2.NewBridge("fake", bdb, zerolog.New(zerolog.NewTestWriter(t)), cfg, conn, net, func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	defer br.Stop()
	login, err := net.Login(ctx, br)
	require.NoError(t, err)
	net.Incoming(login, "chat1", "alice", "m1", "hi")
	var roomID id.RoomID
	require.Eventually(t, func() bool {
		rooms, err := s.ListRooms(ctx)
		if err != nil || len(rooms) == 0 {
			return false
		}
		roomID = id.RoomID(rooms[0].ID)
		return true
	}, 5*time.Second, 20*time.Millisecond)

	try := func(typ event.Type, parsed any, mutate ...func(*event.Event)) (id.EventID, bridgev2.EventHandlingResult) {
		t.Helper()
		evt := &event.Event{
			Type: typ, RoomID: roomID, Sender: ids.Me, ID: ids.RandomEventID(),
			Timestamp: time.Now().UnixMilli(), Content: event.Content{Parsed: parsed},
		}
		for _, m := range mutate {
			m(evt)
		}
		return evt.ID, br.QueueMatrixEvent(ctx, evt)
	}
	queue := func(typ event.Type, parsed any, mutate ...func(*event.Event)) id.EventID {
		t.Helper()
		evtID, res := try(typ, parsed, mutate...)
		require.True(t, res.Success, "%s was not handled: %+v", typ.Type, res)
		return evtID
	}

	mine := queue(event.EventMessage, &event.MessageEventContent{MsgType: event.MsgText, Body: "first"})
	recvOne(t, net.Sent, "message")

	edit := &event.MessageEventContent{MsgType: event.MsgText, Body: "second"}
	edit.SetEdit(mine) // the new text goes to m.new_content; the body becomes the "* second" fallback
	queue(event.EventMessage, edit)
	require.Equal(t, Edit{PortalID: "chat1", TargetID: "out-" + string(mine), Body: "second"}, recvOne(t, net.Edits, "edit"))

	poll := queue(event.EventUnstablePollStart, &event.PollStartEventContent{PollStart: event.PollStart{
		Kind: "org.matrix.msc3381.poll.disclosed", MaxSelections: 1,
		Question: event.MSC1767Message{Text: "lunch?"},
		Answers:  []event.PollOption{{ID: "a", MSC1767Message: event.MSC1767Message{Text: "yes"}}, {ID: "b", MSC1767Message: event.MSC1767Message{Text: "no"}}},
	}})
	require.Equal(t, Poll{PortalID: "chat1", Question: "lunch?", Options: []string{"yes", "no"}, MaxSelections: 1}, recvOne(t, net.Polls, "poll"))
	queue(event.EventUnstablePollResponse, &event.PollResponseEventContent{
		RelatesTo: event.RelatesTo{Type: event.RelReference, EventID: poll},
		Response:  event.PollResponse{Answers: []string{"a"}},
	})
	require.Equal(t, Vote{PortalID: "chat1", PollID: "out-" + string(poll), Answers: []string{"a"}}, recvOne(t, net.Votes, "vote"))

	queue(event.EventRedaction, &event.RedactionEventContent{Redacts: mine}, func(e *event.Event) { e.Redacts = mine })
	require.Equal(t, Remove{PortalID: "chat1", TargetID: "out-" + string(mine)}, recvOne(t, net.Removes, "deletion"))

	empty := ""
	queue(event.StateBeeperDisappearingTimer, &event.BeeperDisappearingTimer{Type: event.DisappearingTypeAfterSend, Timer: jsontime.MS(24 * time.Hour)},
		func(e *event.Event) { e.StateKey = &empty })
	require.Equal(t, TimerChange{PortalID: "chat1", Type: event.DisappearingTypeAfterSend, Timer: 24 * time.Hour}, recvOne(t, net.Timers, "timer change"))

	// A network that refuses fails the change, and nothing reaches it. QueueMatrixEvent has returned, so the
	// bridge is not reading Refuse while it is set.
	net.Refuse = true
	again := &event.MessageEventContent{MsgType: event.MsgText, Body: "third"}
	again.SetEdit(poll)
	_, res := try(event.EventMessage, again)
	require.False(t, res.Success, "a refused edit is a failure: %+v", res)
	require.ErrorIs(t, res.Error, errRefused)
	select {
	case e := <-net.Edits:
		t.Fatalf("a refused edit reached the network: %+v", e)
	default:
	}
}

// SetLoggedIn flips the client's IsLoggedIn at once and sends the login's state through bridgev2, which reaches the
// store as that login's state and a "bridge" change. LoginAs adds a second login beside Login's, with its own state.
func TestSetLoggedInFlipsTheClientAndSendsTheState(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	bdb, err := sqlite.Open(filepath.Join(dir, "fake.db"))
	require.NoError(t, err)
	net := New()
	conn := localmatrix.New("fake", s, &media.Store{Dir: filepath.Join(dir, "media")})
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix: "!fake",
		Permissions:   bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
	}
	br := bridgev2.NewBridge("fake", bdb, zerolog.Nop(), cfg, conn, net, func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	defer br.Stop()
	a, err := net.Login(ctx, br)
	require.NoError(t, err)
	b, err := net.LoginAs(ctx, br, "second", "Work")
	require.NoError(t, err)
	require.Equal(t, "second", string(b.ID))
	require.True(t, a.Client.IsLoggedIn())
	require.True(t, b.Client.IsLoggedIn())

	feed := s.Feed()
	defer feed.Close()
	state := func(loginID string) string {
		states, err := s.LoginStates(ctx, "fake")
		require.NoError(t, err)
		for _, l := range states {
			if l.LoginID == loginID {
				var st struct {
					StateEvent string `json:"state_event"`
				}
				require.NoError(t, json.Unmarshal(l.State, &st))
				return st.StateEvent
			}
		}
		return ""
	}
	awaitBridge := func(loginID, want string) {
		t.Helper()
		timeout := time.After(5 * time.Second)
		for state(loginID) != want {
			select {
			case <-feed.C:
			case <-timeout:
				t.Fatalf("login %s never said %s", loginID, want)
			}
		}
	}

	net.SetLoggedIn(b, false)
	require.False(t, b.Client.IsLoggedIn(), "at once, before the state goes out")
	require.True(t, a.Client.IsLoggedIn(), "the other login is left alone")
	awaitBridge("second", "TRANSIENT_DISCONNECT")

	net.SetLoggedIn(b, true)
	require.True(t, b.Client.IsLoggedIn())
	awaitBridge("second", "CONNECTED")
}

// The fake network's receipts and typing go through bridgev2 the way a real bridge's do: a remote read receipt reaches
// the store as that person's receipt (Intent.MarkRead), a delivery as a delivery (SendMessageStatus with DeliveredTo,
// one-to-one chats only: surprise 2), my own read from another device as my read, and the typing bridgev2 hands the
// network (HandleMatrixTyping) lands on Typings.
func TestFakenetReceiptsAndTypingLookLikeABridges(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	bdb, err := sqlite.Open(filepath.Join(dir, "fake.db"))
	require.NoError(t, err)
	net := New()
	direct := true
	net.SetChat("dm", Chat{Direct: &direct})
	conn := localmatrix.New("fake", s, &media.Store{Dir: filepath.Join(dir, "media")})
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix: "!fake",
		Permissions:   bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
	}
	br := bridgev2.NewBridge("fake", bdb, zerolog.New(zerolog.NewTestWriter(t)), cfg, conn, net, func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	defer br.Stop()
	login, err := net.Login(ctx, br)
	require.NoError(t, err)

	// roomWith waits for the room holding the message body, and returns it.
	roomWith := func(body string) id.RoomID {
		t.Helper()
		var room id.RoomID
		require.Eventually(t, func() bool {
			rooms, err := s.ListRooms(ctx)
			if err != nil {
				return false
			}
			for _, r := range rooms {
				evs, err := s.Events(ctx, r.ID, 10)
				if err != nil {
					return false
				}
				for _, e := range evs {
					if strings.Contains(string(e.Content), body) {
						room = id.RoomID(r.ID)
						return true
					}
				}
			}
			return false
		}, 5*time.Second, 20*time.Millisecond, "%q never arrived", body)
		return room
	}
	// send has me send body to room, through bridgev2, and returns my stored message once it is sent.
	send := func(room id.RoomID, body string) store.Event {
		t.Helper()
		evt := &event.Event{
			Type: event.EventMessage, RoomID: room, Sender: ids.Me, ID: ids.RandomEventID(),
			Timestamp: time.Now().UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: body}},
		}
		raw, err := json.Marshal(&evt.Content)
		require.NoError(t, err)
		_, err = s.InsertEvent(ctx, store.Event{
			RoomID: string(room), EventID: string(evt.ID), Sender: string(ids.Me),
			Type: event.EventMessage.Type, Content: raw, TS: time.Now(), Status: "pending",
		})
		require.NoError(t, err)
		br.QueueMatrixEvent(ctx, evt)
		recvOne(t, net.Sent, "my message")
		var e store.Event
		require.Eventually(t, func() bool {
			var ok bool
			e, ok, err = s.GetEvent(ctx, string(evt.ID))
			return err == nil && ok && e.Status == "sent"
		}, 5*time.Second, 20*time.Millisecond)
		return e
	}
	receipts := func(room id.RoomID, e store.Event) store.Receipts {
		got, err := s.ReceiptsFor(ctx, string(room), []store.Event{e})
		require.NoError(t, err)
		return got[e.EventID]
	}
	alice := string(ids.GhostMXID("fake", "alice"))

	net.Incoming(login, "dm", "alice", "m1", "hello from alice")
	dm := roomWith("hello from alice")
	mine := send(dm, "hi alice")
	remoteID := "out-" + mine.EventID // the ID the fake network gives a message it took

	net.Receipt(login, "dm", "alice", []string{remoteID}, true)
	require.Eventually(t, func() bool { return slices.Equal(receipts(dm, mine).DeliveredTo, []string{alice}) },
		5*time.Second, 20*time.Millisecond, "the delivery never reached the store")
	require.Equal(t, "sent", mine.Status)

	net.Receipt(login, "dm", "alice", []string{remoteID}, false)
	require.Eventually(t, func() bool {
		r := receipts(dm, mine).ReadBy
		return len(r) == 1 && r[0].UserID == alice
	}, 5*time.Second, 20*time.Millisecond, "the read receipt never reached the store")

	// My own read on another device ("me" is the network's own user) is my read: alice's message stops being unread.
	unread := func(room id.RoomID) int {
		rows, err := s.Inbox(ctx)
		require.NoError(t, err)
		for _, r := range rows {
			if r.ID == string(room) {
				return r.Unread
			}
		}
		return -1
	}
	require.Equal(t, 1, unread(dm))
	net.Receipt(login, "dm", "me", []string{"m1"}, false)
	require.Eventually(t, func() bool { return unread(dm) == 0 }, 5*time.Second, 20*time.Millisecond)

	// Surprise 2: bridgev2 drops a delivery outside a one-to-one chat. The read receipt queued after it lands, so the
	// delivery has been handled by then.
	net.Incoming(login, "group", "alice", "g1", "hello group")
	group := roomWith("hello group")
	inGroup := send(group, "hi all")
	net.Receipt(login, "group", "alice", []string{"out-" + inGroup.EventID}, true)
	net.Receipt(login, "group", "alice", []string{"out-" + inGroup.EventID}, false)
	require.Eventually(t, func() bool { return len(receipts(group, inGroup).ReadBy) == 1 }, 5*time.Second, 20*time.Millisecond)
	require.Empty(t, receipts(group, inGroup).DeliveredTo, "no delivery in a group")

	// Typing: what bridgev2 hands the network.
	typing := func(on bool) {
		t.Helper()
		users := []id.UserID{}
		if on {
			users = []id.UserID{ids.Me}
		}
		res := br.QueueMatrixEvent(ctx, &event.Event{
			Type: event.EphemeralEventTyping, RoomID: dm,
			Content: event.Content{Parsed: &event.TypingEventContent{UserIDs: users}},
			Mautrix: event.MautrixInfo{EventSource: event.SourceEphemeral},
		})
		require.True(t, res.Success, "%+v", res)
	}
	typing(true)
	require.Equal(t, TypingChange{PortalID: "dm", Typing: true}, recvOne(t, net.Typings, "the typing start"))
	typing(true)
	typing(false)
	require.Equal(t, TypingChange{PortalID: "dm", Typing: false}, recvOne(t, net.Typings, "the typing stop"),
		"bridgev2 sends a start once per change: the second start went nowhere")
}

// B7: a delivery reaching a hold never waits on Holding: with its buffer full, the signal is dropped rather than
// leaving the bridge's goroutine stuck, so a test that holds more deliveries than it sized Holding for fails at its
// own wait instead of hanging.
func TestReachingAHoldNeverBlocksOnAFullHolding(t *testing.T) {
	n := New()
	n.Holding = make(chan struct{}, 1)
	done := make(chan struct{})
	go func() {
		n.reachedHold()
		n.reachedHold() // past the buffer
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("reaching a hold waited on a full Holding")
	}
	require.Len(t, n.Holding, 1)
}
