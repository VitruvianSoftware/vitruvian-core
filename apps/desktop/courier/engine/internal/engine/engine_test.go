// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package engine

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func startTwo(t *testing.T) (*Engine, *store.Store, map[string]*fakenet.Network) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	nets := map[string]*fakenet.Network{"fakea": fakenet.New(), "fakeb": fakenet.New()}
	var specs []Spec
	for name, n := range nets {
		n := n
		specs = append(specs, Spec{Name: name, Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }})
	}
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, specs, zerolog.New(zerolog.NewTestWriter(t)))
	require.Empty(t, errs)
	t.Cleanup(e.Stop)
	for name, n := range nets {
		h, ok := e.Host(name)
		require.True(t, ok)
		_, err := n.Login(ctx, h.Bridge)
		require.NoError(t, err)
	}
	return e, s, nets
}

func roomWith(t *testing.T, s *store.Store, network, body string) string {
	var roomID string
	require.Eventually(t, func() bool {
		rooms, err := s.ListRooms(context.Background())
		require.NoError(t, err)
		for _, r := range rooms {
			if r.Network != network {
				continue
			}
			evs, err := s.Events(context.Background(), r.ID, 10)
			require.NoError(t, err)
			for _, e := range evs {
				if json.Valid(e.Content) && string(e.Content) != "" && containsBody(e.Content, body) {
					roomID = r.ID
					return true
				}
			}
		}
		return false
	}, 5*time.Second, 50*time.Millisecond)
	return roomID
}

func containsBody(raw json.RawMessage, body string) bool {
	var c struct {
		Body string `json:"body"`
	}
	return json.Unmarshal(raw, &c) == nil && c.Body == body
}

func TestReplyRoutesToTheRoomsNetwork(t *testing.T) {
	e, s, nets := startTwo(t)
	ctx := context.Background()
	for name, n := range nets {
		hh, _ := e.Host(name)
		me, err := hh.Me(ctx)
		require.NoError(t, err)
		n.Incoming(me.GetUserLogins()[0], "chat1", "alice", "m1", "hi from "+name)
	}
	roomB := roomWith(t, s, "fakeb", "hi from fakeb")
	h, err := e.HostForRoom(ctx, roomB)
	require.NoError(t, err)
	require.Equal(t, "fakeb", h.Network)

	reply := &event.Event{
		Type: event.EventMessage, RoomID: id.RoomID(roomB), Sender: ids.Me, ID: ids.RandomEventID(),
		Timestamp: time.Now().UnixMilli(), Content: event.Content{Parsed: &event.MessageEventContent{MsgType: event.MsgText, Body: "to b"}},
	}
	h.Bridge.QueueMatrixEvent(ctx, reply)
	select {
	case got := <-nets["fakeb"].Sent:
		require.Equal(t, "to b", got.Body)
	case <-time.After(5 * time.Second):
		t.Fatal("reply never reached fakeb")
	}
	select {
	case got := <-nets["fakea"].Sent:
		t.Fatalf("reply leaked to fakea: %+v", got)
	case <-time.After(200 * time.Millisecond):
	}
}

func TestHostForUnknownRoomErrors(t *testing.T) {
	e, _, _ := startTwo(t)
	_, err := e.HostForRoom(context.Background(), "!nope:courier.local")
	require.Error(t, err)
}

func TestOneNetworkFailingDoesNotStopTheOthers(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	good := fakenet.New()
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, []Spec{
		{Name: "fakegood", Connector: func() (bridgev2.NetworkConnector, error) { return good, nil }},
		{Name: "fakebad", Connector: func() (bridgev2.NetworkConnector, error) { return nil, errors.New("no credentials") }},
	}, zerolog.New(zerolog.NewTestWriter(t)))
	defer e.Stop()
	require.Equal(t, []string{"fakegood"}, e.Names())
	require.ErrorContains(t, errs["fakebad"], "no credentials")
}
