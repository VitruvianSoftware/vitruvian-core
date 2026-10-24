// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package engine

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"strings"
	"sync"
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
	// assert.Eventually runs the condition on its own goroutine and can still be running it when it times out,
	// so what the condition finds is handed back under a lock.
	var mu sync.Mutex
	var roomID string
	var lastErr error
	found := func() bool {
		rooms, err := s.ListRooms(context.Background())
		if err != nil {
			mu.Lock()
			lastErr = err
			mu.Unlock()
			return false
		}
		for _, r := range rooms {
			if r.Network != network {
				continue
			}
			evs, err := s.Events(context.Background(), r.ID, 10)
			if err != nil {
				mu.Lock()
				lastErr = err
				mu.Unlock()
				return false
			}
			for _, e := range evs {
				if containsBody(e.Content, body) {
					mu.Lock()
					roomID = r.ID
					mu.Unlock()
					return true
				}
			}
		}
		return false
	}
	ok := assert.Eventually(t, found, 5*time.Second, 50*time.Millisecond)
	mu.Lock()
	defer mu.Unlock()
	if !ok {
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

// panicStartNet is a connector whose Start panics, as a bridge with a bug in its start-up might.
type panicStartNet struct{ *fakenet.Network }

func (n *panicStartNet) Start(context.Context) error { panic("sentinel start panic") }

func TestPanicWhileStartingIsConfinedToThatNetwork(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s := openStore(t, dir)
	good := fakenet.New()
	e, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, []Spec{
		{Name: "fakeconstruct", Connector: func() (bridgev2.NetworkConnector, error) { panic("sentinel constructor panic") }},
		{Name: "fakestart", Connector: func() (bridgev2.NetworkConnector, error) { return &panicStartNet{fakenet.New()}, nil }},
		goodSpec("fakegood", good),
	}, zerolog.New(zerolog.NewTestWriter(t)))
	defer e.Stop()
	require.Len(t, errs, 2)
	for _, name := range []string{"fakeconstruct", "fakestart"} {
		require.ErrorContains(t, errs[name], name+" panicked while starting", "the error names the network")
		require.NotContains(t, errs[name].Error(), "goroutine", "the stack goes to the log, not into the error")
	}
	require.ErrorContains(t, errs["fakeconstruct"], "sentinel constructor panic")
	require.ErrorContains(t, errs["fakestart"], "sentinel start panic")
	requireGoodHostStillWorks(t, e, s, good)
}

// quiet is the log of the start-up tests: they stop a bridge right after it starts, while bridgev2's own post-start
// goroutine may still log, which a test writer would report after the test has ended.
var quiet = zerolog.Nop()

// gatedNet is a fake network whose start-up waits for release, the way a slow bridge's does. It says when its start
// has begun (entered) and when its bridge is stopped (stopped).
type gatedNet struct {
	*fakenet.Network
	entered  chan struct{}
	release  chan struct{}
	stopped  chan struct{}
	stopOnce sync.Once
}

func newGated() *gatedNet {
	return &gatedNet{Network: fakenet.New(), entered: make(chan struct{}), release: make(chan struct{}), stopped: make(chan struct{})}
}

// open is a gated network that starts at once.
func open() *gatedNet {
	n := newGated()
	close(n.release)
	return n
}

func (n *gatedNet) Start(ctx context.Context) error {
	close(n.entered)
	<-n.release
	return n.Network.Start(ctx)
}

// Stop is bridgev2's StoppableNetwork: the bridge calls it when its host stops.
func (n *gatedNet) Stop() { n.stopOnce.Do(func() { close(n.stopped) }) }

func gatedSpec(name string, n *gatedNet) Spec {
	return Spec{Name: name, Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }}
}

// closed reports whether ch is closed, without waiting.
func closed(ch <-chan struct{}) bool {
	select {
	case <-ch:
		return true
	default:
		return false
	}
}

// bridgeChanges drains the "bridge" changes waiting in f, without waiting, and returns their networks in order.
func bridgeChanges(f *store.Feed) []string {
	var out []string
	for {
		select {
		case c := <-f.C:
			if c.Kind == "bridge" {
				out = append(out, c.RoomID)
			}
		default:
			return out
		}
	}
}

// A slow network doesn't hold the others' chats back from the app, and none is ever "not started" just because the
// engine hasn't reached it yet: every network to start is Starting from the outset, each becomes Running as its own
// bridge is up, one after the other, and the app hears about each before and after.
func TestHostsAppearAsEachStarts(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s := openStore(t, dir)
	feed := s.Feed()
	defer feed.Close()
	first, second := newGated(), newGated()
	specs := []Spec{gatedSpec("fakefirst", first), gatedSpec("fakesecond", second)}

	e := New(s)
	t.Cleanup(e.Stop)
	e.Expect(specs)
	starting := Status{Starting: true}
	require.Equal(t, starting, e.Status("fakefirst"))
	require.Equal(t, starting, e.Status("fakesecond"), "a network not reached yet is starting, not stopped (Ruling C7)")
	require.Equal(t, Status{}, e.Status("fakeother"), "a network the engine was never given is the zero Status")

	done := make(chan map[string]error, 1)
	go func() {
		done <- e.StartNetworks(ctx, dir, &media.Store{Dir: filepath.Join(dir, "media")}, specs, quiet)
	}()

	<-first.entered
	require.Equal(t, starting, e.Status("fakefirst"))
	require.Equal(t, starting, e.Status("fakesecond"))
	_, ok := e.Host("fakefirst")
	require.False(t, ok, "no host until its bridge is up")
	require.Empty(t, e.Names())
	require.Equal(t, []string{"fakefirst"}, bridgeChanges(feed), "the app hears the network is starting before its bridge is")

	close(first.release)
	<-second.entered
	require.Equal(t, Status{Running: true}, e.Status("fakefirst"))
	require.Equal(t, starting, e.Status("fakesecond"))
	require.Equal(t, []string{"fakefirst"}, e.Names())
	// The bridge's own state (UNCONFIGURED: this fake has no login) is written while its host starts, then the engine
	// says it is running; then the second network starts.
	require.Equal(t, []string{"fakefirst", "fakefirst", "fakesecond"}, bridgeChanges(feed))

	close(second.release)
	require.Empty(t, <-done)
	require.Equal(t, Status{Running: true}, e.Status("fakefirst"))
	require.Equal(t, Status{Running: true}, e.Status("fakesecond"))
	require.Equal(t, []string{"fakefirst", "fakesecond"}, e.Names())
	require.Equal(t, []string{"fakesecond", "fakesecond"}, bridgeChanges(feed))
}

// A network that can't start says why, for this whole session; the others run.
func TestAFailedStartIsNotStartedWithItsReason(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s := openStore(t, dir)
	feed := s.Feed()
	defer feed.Close()
	e := New(s)
	t.Cleanup(e.Stop)
	errs := e.StartNetworks(ctx, dir, &media.Store{Dir: filepath.Join(dir, "media")}, []Spec{
		{Name: "fakebad", Connector: func() (bridgev2.NetworkConnector, error) { return nil, errors.New("no credentials") }},
		goodSpec("fakegood", fakenet.New()),
		goodSpec("Fake_Bad", fakenet.New()),
	}, quiet)
	require.ErrorContains(t, errs["fakebad"], "no credentials")
	require.Equal(t, Status{NotStarted: "no credentials"}, e.Status("fakebad"))
	require.Equal(t, Status{Running: true}, e.Status("fakegood"))
	require.Contains(t, e.Status("Fake_Bad").NotStarted, "[a-z]", "a bad name is reported, with what a good one looks like")
	require.False(t, e.Status("Fake_Bad").Starting)
	require.Equal(t, []string{"fakegood"}, e.Names())
	changes := bridgeChanges(feed)
	require.GreaterOrEqual(t, len(changes), 2)
	require.Equal(t, []string{"fakebad", "fakebad"}, changes[:2], "the app hears a failed start too")
}

// Quitting while a network is still starting waits for that start, then stops every bridge that came up, and starts
// no more.
func TestStopDuringStartStopsWhatStarted(t *testing.T) {
	dir := t.TempDir()
	s := openStore(t, dir)
	feed := s.Feed()
	defer feed.Close()
	first, second, third := open(), newGated(), newGated()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	e := New(s)
	done := make(chan map[string]error, 1)
	go func() {
		done <- e.StartNetworks(ctx, dir, &media.Store{Dir: filepath.Join(dir, "media")},
			[]Spec{gatedSpec("fakefirst", first), gatedSpec("fakesecond", second), gatedSpec("fakethird", third)},
			quiet)
	}()
	<-second.entered

	cancel() // the stop signal: no network after this one starts
	stopped := make(chan struct{})
	go func() {
		e.Stop()
		close(stopped)
	}()
	require.False(t, closed(stopped), "Stop waits for the start in flight")
	require.False(t, closed(first.stopped))

	close(second.release) // its bridge comes up after all, and is stopped with the others
	errs := <-done
	<-stopped
	require.True(t, closed(first.stopped), "the network that started is stopped")
	require.True(t, closed(second.stopped), "so is the one that was starting when the engine was told to stop")
	require.False(t, closed(third.entered), "the one after it never starts")
	require.Error(t, errs["fakethird"])
	require.False(t, e.Status("fakethird").Starting)
	require.NotEmpty(t, e.Status("fakethird").NotStarted)
	require.Contains(t, bridgeChanges(feed), "fakethird", "the app hears it won't start")
}

// Stop before any start: nothing starts after it.
func TestStartAfterStopStartsNothing(t *testing.T) {
	dir := t.TempDir()
	s := openStore(t, dir)
	n := open()
	e := New(s)
	e.Stop()
	errs := e.StartNetworks(context.Background(), dir, &media.Store{Dir: filepath.Join(dir, "media")},
		[]Spec{gatedSpec("fakeone", n)}, quiet)
	require.Error(t, errs["fakeone"])
	require.False(t, closed(n.entered))
	require.Empty(t, e.Names())
}

// A chat's network that is still starting is "still starting", one that won't run this session is "not running",
// and neither ever hands the chat to another network's bridge.
func TestHostForRoomSaysStartingOrNotRunning(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s := openStore(t, dir)
	for id, network := range map[string]string{"!slow:courier.local": "fakeslow", "!bad:courier.local": "fakebad", "!gone:courier.local": "telegram"} {
		require.NoError(t, s.UpsertRoom(ctx, store.Room{ID: id, Network: network, Name: "Test chat"}))
	}
	slow := newGated()
	specs := []Spec{
		{Name: "fakebad", Connector: func() (bridgev2.NetworkConnector, error) { return nil, errors.New("no credentials") }},
		gatedSpec("fakeslow", slow),
	}
	e := New(s)
	t.Cleanup(e.Stop)
	e.Expect(specs)
	done := make(chan map[string]error, 1)
	go func() {
		done <- e.StartNetworks(ctx, dir, &media.Store{Dir: filepath.Join(dir, "media")}, specs, quiet)
	}()
	<-slow.entered

	h, err := e.HostForRoom(ctx, "!slow:courier.local")
	require.ErrorIs(t, err, ErrStarting)
	require.Nil(t, h)
	h, err = e.HostForRoom(ctx, "!bad:courier.local")
	require.ErrorIs(t, err, ErrNotRunning)
	require.Nil(t, h)
	h, err = e.HostForRoom(ctx, "!gone:courier.local")
	require.ErrorIs(t, err, ErrNotRunning)
	require.ErrorContains(t, err, "telegram")
	require.Nil(t, h)

	close(slow.release)
	<-done
	h, err = e.HostForRoom(ctx, "!slow:courier.local")
	require.NoError(t, err)
	require.Equal(t, "fakeslow", h.Network)
}
