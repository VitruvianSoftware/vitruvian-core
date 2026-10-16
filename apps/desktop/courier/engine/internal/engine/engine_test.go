// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package engine

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.mau.fi/util/configupgrade"
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
	var lastErr error
	found := func() bool {
		rooms, err := s.ListRooms(context.Background())
		if err != nil {
			lastErr = err
			return false
		}
		for _, r := range rooms {
			if r.Network != network {
				continue
			}
			evs, err := s.Events(context.Background(), r.ID, 10)
			if err != nil {
				lastErr = err
				return false
			}
			for _, e := range evs {
				if containsBody(e.Content, body) {
					roomID = r.ID
					return true
				}
			}
		}
		return false
	}
	if !assert.Eventually(t, found, 5*time.Second, 50*time.Millisecond) {
		require.NoError(t, lastErr)
		t.FailNow()
	}
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

func goodSpec(name string, n *fakenet.Network) Spec {
	return Spec{Name: name, Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }}
}

// badYAMLNet is a connector whose example config cannot be decoded, so host.Start fails for it.
type badYAMLNet struct{ *fakenet.Network }

func (n *badYAMLNet) GetConfig() (string, any, configupgrade.Upgrader) {
	return "greeting: [unclosed\n", &struct{ Greeting string }{}, configupgrade.NoopUpgrader
}

// configNet is a connector with a config to decode into, so a Configure hook has something to act on.
type configNet struct {
	*fakenet.Network
	cfg struct{ Greeting string }
}

func (n *configNet) GetConfig() (string, any, configupgrade.Upgrader) {
	return "Greeting: hello\n", &n.cfg, configupgrade.NoopUpgrader
}

func openStore(t *testing.T, dir string) *store.Store {
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	return s
}

// requireGoodHostStillWorks logs in to the good network and checks a message flows through to the store.
func requireGoodHostStillWorks(t *testing.T, e *Engine, s *store.Store, good *fakenet.Network) {
	ctx := context.Background()
	require.Equal(t, []string{"fakegood"}, e.Names())
	h, ok := e.Host("fakegood")
	require.True(t, ok)
	_, err := good.Login(ctx, h.Bridge)
	require.NoError(t, err)
	me, err := h.Me(ctx)
	require.NoError(t, err)
	good.Incoming(me.GetUserLogins()[0], "chat1", "alice", "m1", "still here")
	roomID := roomWith(t, s, "fakegood", "still here")
	got, err := e.HostForRoom(ctx, roomID)
	require.NoError(t, err)
	require.Equal(t, "fakegood", got.Network)
}

func TestFailingConfigureDoesNotStopTheOthers(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s := openStore(t, dir)
	good := fakenet.New()
	bad := Spec{Name: "fakebad", Connector: func() (bridgev2.NetworkConnector, error) {
		return &configNet{Network: fakenet.New()}, nil
	}}
	bad.Configure = func(any) error { return errors.New("missing api id") }
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, []Spec{bad, goodSpec("fakegood", good)},
		zerolog.New(zerolog.NewTestWriter(t)))
	defer e.Stop()
	require.Len(t, errs, 1)
	require.ErrorContains(t, errs["fakebad"], "missing api id")
	requireGoodHostStillWorks(t, e, s, good)
}

func TestFailingHostStartDoesNotStopTheOthers(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s := openStore(t, dir)
	good := fakenet.New()
	bad := Spec{Name: "fakebad", Connector: func() (bridgev2.NetworkConnector, error) {
		return &badYAMLNet{fakenet.New()}, nil
	}}
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, []Spec{bad, goodSpec("fakegood", good)},
		zerolog.New(zerolog.NewTestWriter(t)))
	defer e.Stop()
	require.Len(t, errs, 1)
	require.Error(t, errs["fakebad"])
	requireGoodHostStillWorks(t, e, s, good)
}

func TestHostForRoomNeverFallsBackToAnotherHost(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s := openStore(t, dir)
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, []Spec{goodSpec("fakegood", fakenet.New())},
		zerolog.New(zerolog.NewTestWriter(t)))
	defer e.Stop()
	require.Empty(t, errs)
	require.NoError(t, s.UpsertRoom(ctx, store.Room{ID: "!orphan:courier.local", Network: "telegram", Name: "Orphan"}))

	h, err := e.HostForRoom(ctx, "!orphan:courier.local")
	require.Error(t, err)
	require.Nil(t, h, "a room on a network that is not running must not be handed to another network's bridge")
	require.ErrorContains(t, err, "telegram")
}

func TestStopTwiceIsSafe(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s := openStore(t, dir)
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, []Spec{goodSpec("fakegood", fakenet.New())},
		zerolog.New(zerolog.NewTestWriter(t)))
	require.Empty(t, errs)
	require.NotPanics(t, func() {
		e.Stop()
		e.Stop()
	})
}

func TestInvalidAndDuplicateNamesAreSkipped(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s := openStore(t, dir)
	first, second := fakenet.New(), fakenet.New()
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, []Spec{
		goodSpec("fakegood", first),
		goodSpec("fakegood", second), // duplicate: the first one keeps the name
		goodSpec("Fake_Bad", fakenet.New()),
		goodSpec("", fakenet.New()),
	}, zerolog.New(zerolog.NewTestWriter(t)))
	defer e.Stop()
	require.Equal(t, []string{"fakegood"}, e.Names())
	require.NotContains(t, errs, "fakegood", "the network that is running must not be reported as failed")
	require.ErrorContains(t, errs["fakegood (duplicate)"], "already")
	require.ErrorContains(t, errs["Fake_Bad"], "name")
	require.ErrorContains(t, errs[""], "name")
	require.True(t, strings.Contains(errs["Fake_Bad"].Error(), "[a-z]"), "the error should say what a valid name looks like")
}
