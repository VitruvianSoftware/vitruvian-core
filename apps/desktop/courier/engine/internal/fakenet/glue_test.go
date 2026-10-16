// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package fakenet

import (
	"context"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
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
	cfg := &bridgeconfig.BridgeConfig{CommandPrefix: "!fake",
		Permissions: bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin}}
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
	reply := &event.Event{Type: event.EventMessage, RoomID: roomID, Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: time.Now().UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: "hi alice"}}}
	raw, err := json.Marshal(&reply.Content)
	require.NoError(t, err)
	inserted, err := s.InsertEvent(ctx, store.Event{RoomID: string(roomID), EventID: string(reply.ID), Sender: string(ids.Me),
		Type: event.EventMessage.Type, Content: raw, TS: time.Now(), Status: "pending"})
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
