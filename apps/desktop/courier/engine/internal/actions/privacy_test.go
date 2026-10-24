// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/logscrub"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// messageWith waits for the bridge to store a message with body in it, and returns it.
func (w world) messageWith(t *testing.T, body string) store.Event {
	t.Helper()
	room := w.roomWith(t, body)
	evs, err := w.s.Events(context.Background(), room.ID, 50)
	require.NoError(t, err)
	for _, e := range evs {
		if bytes.Contains(e.Content, []byte(body)) {
			return e
		}
	}
	t.Fatalf("no message with %q", body)
	return store.Event{}
}

// ghost is the Matrix ID of the fake network's person uid, as the chat's members list them.
func (w world) ghost(t *testing.T, uid string) string {
	t.Helper()
	return string(ids.GhostMXID(w.name(t), networkid.UserID(uid)))
}

// directWorld is a world whose logins start one-to-one chats via, with a group alice and bob write in. The group's
// member list has alice and dave, who never writes, but not bob, as a large Telegram group's lists only some.
func directWorld(t *testing.T, via fakenet.StartChats, log zerolog.Logger) (world, store.Room) {
	t.Helper()
	n := fakenet.New()
	n.StartChats = via
	n.SetChat("group-q7", fakenet.Chat{Members: []string{"alice-q7", "dave-q7"}})
	w := startWorldOn(t, "fake", n, true, log)
	w.n.Incoming(w.login, "group-q7", "alice-q7", "g1", "alice-q7 in the group")
	w.n.Incoming(w.login, "group-q7", "bob-q7", "g2", "bob-q7 in the group")
	group := w.roomWith(t, "alice-q7 in the group")
	require.Equal(t, group.ID, w.roomWith(t, "bob-q7 in the group").ID)
	require.False(t, group.IsDirect, "fixture: a group")
	return w, group
}

// directWith has the network deliver a message in the one-to-one chat chatID of login with uid, and returns the chat.
func (w world) directWith(t *testing.T, login *bridgev2.UserLogin, chatID, uid, body string) store.Room {
	t.Helper()
	direct := true
	w.n.SetChat(chatID, fakenet.Chat{Direct: &direct, Members: []string{uid}})
	w.n.Incoming(login, chatID, uid, "d-"+body, body)
	r := w.roomWith(t, body)
	require.True(t, r.IsDirect, "fixture: a one-to-one chat")
	require.Equal(t, string(login.ID), r.LoginID)
	return r
}

// Mark as Unread from a message stays on this Mac: nothing reaches the network, and the chat's unread count runs
// from that message on. A message of mine is allowed; a note (a timer change) is refused (Ruling P2); a message not
// in the chat is not found. SetUnreadFromEvent finds the chat from the message (C18).
func TestUnreadFromIsNeverSent(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	w.n.Incoming(w.login, "chat1", "alice-q7", "m1", "first")
	w.n.Incoming(w.login, "chat1", "alice-q7", "m2", "second")
	w.n.Incoming(w.login, "chat1", "alice-q7", "m3", "third")
	first, second, third := w.messageWith(t, "first"), w.messageWith(t, "second"), w.messageWith(t, "third")
	room := first.RoomID
	require.NoError(t, w.a.MarkRead(ctx, room))
	recv(t, w.n.Receipts, "the read receipt")
	require.Equal(t, 0, w.unread(t, room))

	require.NoError(t, w.a.SetUnreadFrom(ctx, room, second.EventID))
	require.Equal(t, 2, w.unread(t, room), "the second message and the third")
	got, err := w.a.SetUnreadFromEvent(ctx, third.EventID)
	require.NoError(t, err)
	require.Equal(t, room, got)
	require.Equal(t, 1, w.unread(t, room))
	mine := w.insertMine(t, room, "m.room.message", `{"msgtype":"m.text","body":"mine"}`, "sent", time.Now())
	require.NoError(t, w.a.SetUnreadFrom(ctx, room, mine), "a message of mine is allowed")
	require.Equal(t, 0, w.unread(t, room), "only other people's messages count")

	note := w.insertFrom(t, room, w.ghost(t, "alice-q7"), "m.room.message", `{"msgtype":"m.notice","body":"timer",
		"com.beeper.action_message":{"type":"disappearing_timer","timer":86400000,"timer_type":"after_send","implicit":false}}`,
		time.Now())
	require.ErrorIs(t, w.a.SetUnreadFrom(ctx, room, note), ErrNotSupported, "a note")
	got, err = w.a.SetUnreadFromEvent(ctx, note)
	require.ErrorIs(t, err, ErrNotSupported)
	require.Empty(t, got, "no chat with an error")
	require.ErrorIs(t, w.a.SetUnreadFrom(ctx, room, "$nope"), store.ErrNotFound)
	_, err = w.a.SetUnreadFromEvent(ctx, "$nope")
	require.ErrorIs(t, err, store.ErrNotFound)
	other, _ := w.secondChat(t, "chat2", "b1", room)
	require.ErrorIs(t, w.a.SetUnreadFrom(ctx, other, second.EventID), store.ErrNotFound, "a message of another chat")

	none(t, w.n.Receipts, "a receipt")
	none(t, w.n.Unreads, "an unread mark")
}

// Reply Privately answers Courier's own one-to-one chat with the person first, without the network: on the group's
// login, even while it is down. A group every account shares looks under the login actually in it (C15), never "".
func TestDirectChatFindsCourierOwnChatFirst(t *testing.T) {
	ctx := context.Background()
	w, group := directWorld(t, fakenet.ViaGhost, zerolog.Nop())
	dm := w.directWith(t, w.login, "alice-q7-dm", "alice-q7", "just alice-q7 and me")

	got, err := w.a.DirectChat(ctx, group.ID, w.ghost(t, "alice-q7"))
	require.NoError(t, err)
	require.Equal(t, dm.ID, got)
	w.down()
	got, err = w.a.DirectChat(ctx, group.ID, w.ghost(t, "alice-q7"))
	require.NoError(t, err)
	require.Equal(t, dm.ID, got, "an existing chat needs no network")
	w.up()

	// A group only my second account is in: its one-to-one chat with alice, not my first account's.
	b := w.work(t)
	w.n.IncomingShared(b, "shared-q7", "alice-q7", "s1", "alice-q7 in the shared group")
	shared := w.roomWith(t, "alice-q7 in the shared group")
	require.Empty(t, shared.LoginID, "fixture: a shared chat")
	bDM := w.directWith(t, b, "alice-q7-dm", "alice-q7", "alice-q7 and my second account")
	require.NotEqual(t, dm.ID, bDM.ID)
	got, err = w.a.DirectChat(ctx, shared.ID, w.ghost(t, "alice-q7"))
	require.NoError(t, err)
	require.Equal(t, bDM.ID, got, "the login in the shared group")
	w.n.SetLoggedIn(b, false)
	got, err = w.a.DirectChat(ctx, shared.ID, w.ghost(t, "alice-q7"))
	require.NoError(t, err)
	require.Equal(t, bDM.ID, got, "and while that login is down")

	none(t, w.n.ChatStarts, "a chat start")
}

// With no one-to-one chat yet, the bridge makes one, the way each network does (Global Constraints' Reply Privately
// row), through the group's login: the chat is in the store, one-to-one, with the person and its login, and asking
// again answers it without a second start.
func TestDirectChatCreatesOneThroughTheBridge(t *testing.T) {
	for _, via := range []fakenet.StartChats{fakenet.ViaGhost, fakenet.ViaIdentifier} {
		t.Run(map[fakenet.StartChats]string{fakenet.ViaGhost: "ghost", fakenet.ViaIdentifier: "identifier"}[via], func(t *testing.T) {
			ctx := context.Background()
			w, group := directWorld(t, via, zerolog.Nop())
			alice := w.ghost(t, "alice-q7")

			got, err := w.a.DirectChat(ctx, group.ID, alice)
			require.NoError(t, err)
			require.Equal(t, fakenet.ChatStart{LoginID: "fake-login", UserID: "alice-q7", Via: via}, recv(t, w.n.ChatStarts, "the chat start"))
			room, ok, err := w.s.GetRoom(ctx, got)
			require.NoError(t, err)
			require.True(t, ok, "the chat is in the store")
			require.True(t, room.IsDirect)
			require.Equal(t, "fake", room.Network)
			require.Equal(t, "fake-login", room.LoginID)
			members, err := w.s.Members(ctx, got)
			require.NoError(t, err)
			require.Contains(t, members, alice)
			require.Contains(t, members, string(ids.Me))

			again, err := w.a.DirectChat(ctx, group.ID, alice)
			require.NoError(t, err)
			require.Equal(t, got, again)
			none(t, w.n.ChatStarts, "a second chat start")

			// A member who never wrote, and someone who writes but isn't on the member list.
			for _, who := range []string{"dave-q7", "bob-q7"} {
				_, err = w.a.DirectChat(ctx, group.ID, w.ghost(t, who))
				require.NoError(t, err, who)
				require.Equal(t, fakenet.ChatStart{LoginID: "fake-login", UserID: who, Via: via}, recv(t, w.n.ChatStarts, who+"'s chat start"))
			}

			// A shared group goes through the login that is in it.
			b := w.work(t)
			w.n.IncomingShared(b, "shared-q7", "bob-q7", "s1", "bob-q7 in the shared group")
			shared := w.roomWith(t, "bob-q7 in the shared group")
			bobs, err := w.a.DirectChat(ctx, shared.ID, w.ghost(t, "bob-q7"))
			require.NoError(t, err)
			require.Equal(t, fakenet.ChatStart{LoginID: "second", UserID: "bob-q7", Via: via}, recv(t, w.n.ChatStarts, "B's chat start"))
			room, ok, err = w.s.GetRoom(ctx, bobs)
			require.NoError(t, err)
			require.True(t, ok)
			require.Equal(t, "second", room.LoginID)
		})
	}
}

// Each refusal says why: a person who isn't a member of the chat (or isn't a person of the network) and an unknown
// chat are not found; a one-to-one chat has no Reply Privately; a login that doesn't come in time is not connected; a
// network that starts no chats can't, and one that says no refused. Nothing is made in any of them.
func TestDirectChatRefusalsNameTheReason(t *testing.T) {
	ctx := context.Background()
	w, group := directWorld(t, fakenet.ViaGhost, zerolog.Nop())
	rooms := func() int {
		t.Helper()
		rs, err := w.s.ListRooms(ctx)
		require.NoError(t, err)
		return len(rs)
	}
	before := rooms()

	for name, who := range map[string]string{
		"not a member":           w.ghost(t, "zed-q7"),
		"me":                     string(ids.Me),
		"another network's":      string(ids.GhostMXID("other", "alice-q7")),
		"not a Matrix ID at all": "alice-q7",
	} {
		_, err := w.a.DirectChat(ctx, group.ID, who)
		require.ErrorIs(t, err, store.ErrNotFound, name)
	}
	_, err := w.a.DirectChat(ctx, "!nope:courier.local", w.ghost(t, "alice-q7"))
	require.ErrorIs(t, err, store.ErrNotFound, "an unknown chat")
	dm := w.directWith(t, w.login, "carol-q7-dm", "carol-q7", "just carol-q7 and me")
	before++
	_, err = w.a.DirectChat(ctx, dm.ID, w.ghost(t, "carol-q7"))
	require.ErrorIs(t, err, ErrNotSupported, "a one-to-one chat")

	lt := newLoginTimer()
	w.a.after = lt.After
	w.a.LoginWait = time.Minute
	w.down()
	answered := make(chan error, 1)
	go func() {
		_, err := w.a.DirectChat(ctx, group.ID, w.ghost(t, "alice-q7"))
		answered <- err
	}()
	lt.awaitWait(t, time.Minute)
	lt.fire(time.Minute)
	require.ErrorIs(t, <-answered, ErrNotConnected)
	w.up()

	w.n.Refuse = true
	_, err = w.a.DirectChat(ctx, group.ID, w.ghost(t, "alice-q7"))
	require.ErrorIs(t, err, ErrNetworkRefused)
	w.n.Refuse = false
	none(t, w.n.ChatStarts, "a chat start")
	require.Equal(t, before, rooms(), "nothing was made")

	plain, plainGroup := directWorld(t, fakenet.NoChatStarts, zerolog.Nop())
	_, err = plain.a.DirectChat(ctx, plainGroup.ID, plain.ghost(t, "alice-q7"))
	require.ErrorIs(t, err, ErrNotSupported, "a network that starts no chats")
}

// Reply Privately logs no one: not the person, the chats, nor the account, whether the chat is made, refused or
// can't be.
func TestDirectChatNeverLogsWho(t *testing.T) {
	ctx := context.Background()
	logs := &syncBuffer{}
	// The engine's logger, as cmd/courier-engine makes it, but at debug: through the log writer.
	w, group := directWorld(t, fakenet.ViaGhost, zerolog.New(logscrub.New(logs)).Level(zerolog.DebugLevel))
	alice := w.ghost(t, "alice-q7")

	made, err := w.a.DirectChat(ctx, group.ID, alice)
	require.NoError(t, err)
	recv(t, w.n.ChatStarts, "the chat start")
	w.n.Refuse = true
	_, err = w.a.DirectChat(ctx, group.ID, w.ghost(t, "bob-q7"))
	require.ErrorIs(t, err, ErrNetworkRefused)
	w.n.Refuse = false
	_, err = w.a.DirectChat(ctx, group.ID, w.ghost(t, "zed-q7"))
	require.ErrorIs(t, err, store.ErrNotFound)

	out := logs.String()
	require.Contains(t, out, "a one-to-one chat couldn't be started", "fixture: the refusal was logged")
	who := []string{
		alice, w.ghost(t, "bob-q7"), w.ghost(t, "zed-q7"), "alice-q7", "bob-q7", "zed-q7", "group-q7", group.ID, made,
		fakenet.DirectChatID("alice-q7"), string(w.login.ID),
	}
	for _, s := range who {
		j, _ := json.Marshal(s)
		require.NotContains(t, out, s, "the log names who")
		require.NotContains(t, out, string(j[1:len(j)-1]), "the log names who")
	}
}

// settled waits until the stored state of login id is want (its bridge state reached the store).
func (w world) settled(t *testing.T, id, want string) {
	t.Helper()
	feed, cancel := w.s.Subscribe()
	defer cancel()
	for w.stateOf(t, id) != want {
		select {
		case <-feed:
		case <-time.After(5 * time.Second): // a deadlock guard, not a measure
			t.Fatalf("login %s never became %s", id, want)
		}
	}
}

// While the network starts there is no bridge to say which account a shared group (a WhatsApp group: no login_id) is
// in. With one account on the network, the store knows it is that one, so its one-to-one chat opens. With two, it
// can't know, and never takes the first (Review Focus 5): the answer is the network's (starting).
func TestDirectChatWhileStartingUsesTheOnlyAccount(t *testing.T) {
	ctx := context.Background()
	t.Run("one account", func(t *testing.T) {
		w := startWorld(t, "fake", true)
		w.n.IncomingShared(w.login, "shared-q7", "alice-q7", "s1", "alice-q7 in the shared group")
		shared := w.roomWith(t, "alice-q7 in the shared group")
		require.Empty(t, shared.LoginID, "fixture: a shared chat")
		dm := w.directWith(t, w.login, "alice-q7-dm", "alice-q7", "just alice-q7 and me")
		alice := w.ghost(t, "alice-q7")
		w.up()
		w.settled(t, "fake-login", "CONNECTED")

		starting, _ := w.restart(t, "fake")
		got, err := starting.a.DirectChat(ctx, shared.ID, alice)
		require.NoError(t, err)
		require.Equal(t, dm.ID, got)
	})
	t.Run("two accounts", func(t *testing.T) {
		w := startWorld(t, "fake", true)
		b := w.work(t)
		w.n.IncomingShared(b, "shared-q7", "alice-q7", "s1", "alice-q7 in the shared group")
		shared := w.roomWith(t, "alice-q7 in the shared group")
		w.directWith(t, w.login, "alice-q7-dm", "alice-q7", "just alice-q7 and me")
		alice := w.ghost(t, "alice-q7")
		w.up()
		w.n.SetLoggedIn(b, true)
		w.settled(t, "fake-login", "CONNECTED")
		w.settled(t, "second", "CONNECTED")

		starting, _ := w.restart(t, "fake")
		_, err := starting.a.DirectChat(ctx, shared.ID, alice)
		require.ErrorIs(t, err, engine.ErrStarting, "never the first account's chat")
	})
}

// A network that can't reach the person says so with an error, not a nil answer: Google Messages without the
// ghost's phone number (mautrix-gmessages pkg/connector/startchat.go:85-87, v0.2609.0), an invalid number (:101-104,
// M_INVALID_PARAM), or a person another login has to reach (bridgev2.ErrResolveIdentifierTryNext: :82-84, and
// Telegram's startchat.go:83). Each is ErrNotSupported and logs no warning; any other failure of the network is
// ErrNetworkRefused, with one. A chat the bridge can't make once the network has answered is ErrNetworkRefused too.
func TestDirectChatUnreachablePersonIsNotSupported(t *testing.T) {
	ctx := context.Background()
	logs := &syncBuffer{}
	w, group := directWorld(t, fakenet.ViaIdentifier, zerolog.New(logscrub.New(logs)).Level(zerolog.WarnLevel))
	alice := w.ghost(t, "alice-q7")
	for name, err := range map[string]error{
		"no phone number": fmt.Errorf("phone number of ghost %s not known", "alice-q7"),
		"invalid number":  bridgev2.WrapRespErrManual(errors.New("not a number"), mautrix.MInvalidParam.ErrCode, http.StatusBadRequest),
		"another login":   fmt.Errorf("%w: prefix mismatch", bridgev2.ErrResolveIdentifierTryNext),
	} {
		w.n.ChatStartErr = err
		_, got := w.a.DirectChat(ctx, group.ID, alice)
		require.ErrorIs(t, got, ErrNotSupported, name)
		require.NotErrorIs(t, got, ErrNetworkRefused, name)
	}
	require.NotContains(t, logs.String(), "couldn't be started", "an unreachable person is no warning")

	w.n.ChatStartErr = errors.New("the network is unhappy")
	_, err := w.a.DirectChat(ctx, group.ID, alice)
	require.ErrorIs(t, err, ErrNetworkRefused)
	require.Contains(t, logs.String(), "couldn't be started")
	w.n.ChatStartErr = nil

	w.n.ChatInfoErr = errors.New("the network can't describe it")
	_, err = w.a.DirectChat(ctx, group.ID, alice)
	w.n.ChatInfoErr = nil
	require.ErrorIs(t, err, ErrNetworkRefused, "the bridge couldn't make the chat")
	recv(t, w.n.ChatStarts, "the start the network said yes to")
	none(t, w.n.ChatStarts, "a start of the refused ones")
}
