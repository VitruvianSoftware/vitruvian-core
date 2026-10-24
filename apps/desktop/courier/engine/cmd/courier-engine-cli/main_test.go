// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/networks"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func TestParseArgs(t *testing.T) {
	a, err := parseArgs([]string{"--data", "/tmp/x", "send", "!r:courier.local", "hello", "there"})
	require.NoError(t, err)
	require.Equal(t, args{data: "/tmp/x", cmd: "send", room: "!r:courier.local", text: "hello there"}, a)
	_, err = parseArgs([]string{"send", "!r:courier.local"})
	require.Error(t, err, "send without text must be rejected")
	_, err = parseArgs([]string{"bogus"})
	require.Error(t, err)
}

func TestParseArgsRejectsBlankSend(t *testing.T) {
	_, err := parseArgs([]string{"send", "!r:courier.local", "   "})
	require.Error(t, err, "a whitespace-only message must not be sent")
}

func TestParseArgsKeepsBridgeLookingTextForSend(t *testing.T) {
	// Whether text is a bridge command depends on the room's network, which only send knows.
	a, err := parseArgs([]string{"send", "!r:courier.local", "!telegram logout"})
	require.NoError(t, err)
	require.Equal(t, "!telegram logout", a.text)
}

func TestLinkRequiresNetwork(t *testing.T) {
	_, err := parseArgs([]string{"link"})
	require.Error(t, err)
	require.Contains(t, err.Error(), "--network")
}

func TestParseArgsLinkNetworkAndFlow(t *testing.T) {
	a, err := parseArgs([]string{"--data", "/tmp/x", "--network", "slack", "--flow", "token", "link"})
	require.NoError(t, err)
	require.Equal(t, args{data: "/tmp/x", network: "slack", flow: "token", cmd: "link"}, a)

	a, err = parseArgs([]string{"--data", "/tmp/x", "--network", "whatsapp", "link"})
	require.NoError(t, err)
	require.Empty(t, a.flow, "no --flow means the network's first flow, chosen at link time")

	_, err = parseArgs([]string{"--network", "nonesuch", "link"})
	require.ErrorContains(t, err, "nonesuch")
	_, err = parseArgs([]string{"--network", "slack", "--flow", "nonesuch", "link"})
	require.ErrorContains(t, err, "nonesuch")
	require.ErrorContains(t, err, "email", "the error lists the flows that do exist")
}

func TestNetworkAndFlowAreOnlyForLink(t *testing.T) {
	for _, argv := range [][]string{
		{"--network", "slack", "chats"},
		{"--flow", "qr", "tail"},
		{"--network", "slack", "send", "!r:courier.local", "hi"},
	} {
		_, err := parseArgs(argv)
		require.Error(t, err, "%v", argv)
	}
}

func TestDefaultDataDir(t *testing.T) {
	t.Setenv("HOME", "/Users/someone")
	a, err := parseArgs([]string{"chats"})
	require.NoError(t, err)
	require.Equal(t, filepath.Join("/Users/someone", "Library", "Application Support", "Courier-m1"), a.data)

	_, err = defaultDataDir("", errors.New("no home"))
	require.Error(t, err, "no home directory must not fall back to a relative path")
	_, err = defaultDataDir("", nil)
	require.Error(t, err)
	_, err = parseArgs([]string{"--data", "", "chats"})
	require.Error(t, err, "an explicit empty --data is a mistake, not the default")
}

func newStoreWithPending(t *testing.T) (*store.Store, string) {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	content, err := json.Marshal(map[string]string{"msgtype": "m.text", "body": "hi"})
	require.NoError(t, err)
	require.NoError(t, s.UpsertRoom(context.Background(), store.Room{ID: "!r:courier.local", Network: "whatsapp", Name: "Test"}))
	_, err = s.InsertEvent(context.Background(), store.Event{
		RoomID: "!r:courier.local", EventID: "$e1", Sender: "@me:courier.local",
		Type: "m.room.message", Content: content, TS: time.Now(), Status: "pending",
	})
	require.NoError(t, err)
	return s, "$e1"
}

func TestWaitStatusSent(t *testing.T) {
	s, id := newStoreWithPending(t)
	require.NoError(t, s.SetStatus(context.Background(), id, "sent", ""))
	require.NoError(t, waitStatus(context.Background(), s, id, time.Second))
}

func TestWaitStatusSentArrivesWhileWaiting(t *testing.T) {
	s, id := newStoreWithPending(t)
	go func() {
		time.Sleep(100 * time.Millisecond)
		_ = s.SetStatus(context.Background(), id, "sent", "")
	}()
	require.NoError(t, waitStatus(context.Background(), s, id, 5*time.Second))
}

func TestWaitStatusFailedCarriesReason(t *testing.T) {
	s, id := newStoreWithPending(t)
	require.NoError(t, s.SetStatus(context.Background(), id, "failed", "not connected to WhatsApp"))
	err := waitStatus(context.Background(), s, id, time.Second)
	require.Error(t, err)
	require.Contains(t, err.Error(), "not connected to WhatsApp")
	require.NotContains(t, err.Error(), "delivery unknown", "a definite failure is not an unknown delivery")
}

func TestWaitStatusTimeoutIsDeliveryUnknown(t *testing.T) {
	s, id := newStoreWithPending(t)
	err := waitStatus(context.Background(), s, id, 300*time.Millisecond)
	require.Error(t, err)
	require.Contains(t, err.Error(), "delivery unknown — check your phone before resending")
	require.Contains(t, err.Error(), "event "+id+" left pending")
	e, _, gerr := s.GetEvent(context.Background(), id)
	require.NoError(t, gerr)
	require.Equal(t, "pending", e.Status, "an unknown delivery must stay pending")
}

func TestWaitStatusCancelIsDeliveryUnknown(t *testing.T) {
	s, id := newStoreWithPending(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	err := waitStatus(ctx, s, id, 5*time.Second)
	require.Error(t, err)
	require.Contains(t, err.Error(), "delivery unknown — check your phone before resending")
	require.Contains(t, err.Error(), "event "+id+" left pending")
}

// world is an engine running the fake network under some network's name, over a real store.
type world struct {
	eng   *engine.Engine
	s     *store.Store
	n     *fakenet.Network
	login *bridgev2.UserLogin // nil when the world is not linked
}

// startWorld runs the fake network as `name`. With linked, it has one login whose client reports "logged in"
// only loginDelay after Connect, the way WhatsApp does once the server's success message arrives.
func startWorld(t *testing.T, name string, linked bool, loginDelay time.Duration) world {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	n := fakenet.New()
	n.LoginDelay = loginDelay
	eng, errs := engine.Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")},
		[]engine.Spec{{Name: name, Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }}}, zerolog.Nop())
	require.Empty(t, errs)
	t.Cleanup(eng.Stop)
	w := world{eng: eng, s: s, n: n}
	if linked {
		h, ok := eng.Host(name)
		require.True(t, ok)
		w.login, err = n.Login(ctx, h.Bridge)
		require.NoError(t, err)
	}
	return w
}

// chat has the network deliver a message from a contact, which makes the bridge create a real room for it.
func (w world) chat(t *testing.T) string {
	t.Helper()
	w.n.Incoming(w.login, "chat1", "alice", "m1", "hi")
	var room string
	require.Eventually(t, func() bool {
		rooms, err := w.s.ListRooms(context.Background())
		if err != nil || len(rooms) == 0 {
			return false
		}
		room = rooms[0].ID
		evs, err := w.s.Events(context.Background(), room, 10)
		return err == nil && len(evs) > 0
	}, 5*time.Second, 20*time.Millisecond, "the bridge never stored the contact's message")
	return room
}

// startFake is startWorld for a single linked network called "fake", returning its host.
func startFake(t *testing.T, loginDelay time.Duration) (*host.Host, *store.Store, *fakenet.Network) {
	t.Helper()
	w := startWorld(t, "fake", true, loginDelay)
	h, ok := w.eng.Host("fake")
	require.True(t, ok)
	return h, w.s, w.n
}

func TestWaitForLoginWaitsOutTheHandshake(t *testing.T) {
	h, _, _ := startFake(t, 600*time.Millisecond)
	me, err := h.Me(context.Background())
	require.NoError(t, err)
	require.False(t, me.GetUserLogins()[0].Client.IsLoggedIn(), "fixture: the login must start out not logged in")

	start := time.Now()
	require.NoError(t, waitForLogin(context.Background(), h, 10*time.Second))
	require.GreaterOrEqual(t, time.Since(start), 400*time.Millisecond, "must have waited for the login, not returned at once")
	require.True(t, me.GetUserLogins()[0].Client.IsLoggedIn())
}

func TestWaitForLoginReturnsAtOnceWhenLoggedIn(t *testing.T) {
	h, _, _ := startFake(t, 0)
	start := time.Now()
	require.NoError(t, waitForLogin(context.Background(), h, 10*time.Second))
	require.Less(t, time.Since(start), time.Second)
}

func TestWaitForLoginTimesOut(t *testing.T) {
	h, _, _ := startFake(t, time.Hour)
	err := waitForLogin(context.Background(), h, 400*time.Millisecond)
	require.ErrorIs(t, err, errNotConnected)
}

func TestWaitForLoginCancel(t *testing.T) {
	h, _, _ := startFake(t, time.Hour)
	ctx, cancel := context.WithCancel(context.Background())
	go func() { time.Sleep(100 * time.Millisecond); cancel() }()
	require.ErrorIs(t, waitForLogin(ctx, h, 10*time.Second), errNotConnected)
}

func TestSendBeforeLoginSendsNothing(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true, time.Hour)
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!r:courier.local", Network: "fake", Name: "Test"}))

	err := send(ctx, w.eng, w.s, args{cmd: "send", room: "!r:courier.local", text: "hello"}, 300*time.Millisecond)
	require.ErrorIs(t, err, errNotConnected)
	require.EqualError(t, err, "fake: not connected yet — nothing was sent")

	evs, err := w.s.Events(ctx, "!r:courier.local", 10)
	require.NoError(t, err)
	require.Empty(t, evs, "nothing may be stored when the send is refused")
	select {
	case got := <-w.n.Sent:
		t.Fatalf("a message reached the network: %+v", got)
	case <-time.After(200 * time.Millisecond):
	}
}

func TestSendToUnlinkedNetworkFailsFast(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", false, 0) // running, but never linked: no login at all
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!r:courier.local", Network: "fake", Name: "Test"}))

	start := time.Now()
	// A long wait: failing fast must not depend on the timeout.
	err := send(ctx, w.eng, w.s, args{cmd: "send", room: "!r:courier.local", text: "hello"}, 30*time.Second)
	require.Less(t, time.Since(start), time.Second, "an unlinked network must not make send wait for a login")
	require.EqualError(t, err, "fake isn't linked — run link --network fake first")

	evs, err := w.s.Events(ctx, "!r:courier.local", 10)
	require.NoError(t, err)
	require.Empty(t, evs, "nothing may be stored")
	select {
	case got := <-w.n.Sent:
		t.Fatalf("a message reached the network: %+v", got)
	case <-time.After(200 * time.Millisecond):
	}
}

func TestSendToANetworkThatIsNotRunningNeverFallsBack(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true, 0)
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!t:courier.local", Network: "telegram", Name: "Elsewhere"}))

	err := send(ctx, w.eng, w.s, args{cmd: "send", room: "!t:courier.local", text: "hello"}, time.Second)
	require.ErrorContains(t, err, "telegram")
	require.ErrorContains(t, err, "not running")
	select {
	case got := <-w.n.Sent:
		t.Fatalf("a message for a telegram room reached another network: %+v", got)
	case <-time.After(200 * time.Millisecond):
	}
}

func TestBridgePrefixPerNetwork(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "telegram", true, 0)
	room := w.chat(t)

	// Telegram's bridge runs "!telegram ..." as an admin command: never send that as a chat message.
	for _, text := range []string{"!telegram logout", "  !Telegram   list-logins", "!telegram"} {
		err := send(ctx, w.eng, w.s, args{cmd: "send", room: room, text: text}, time.Second)
		require.ErrorContains(t, err, "!telegram", text)
		require.ErrorContains(t, err, "admin command", text)
	}
	before, err := w.s.Events(ctx, room, 50)
	require.NoError(t, err)
	require.Len(t, before, 1, "only the contact's message is stored: a refused command leaves no trace")
	select {
	case got := <-w.n.Sent:
		t.Fatalf("a bridge command reached the network: %+v", got)
	default:
	}

	// Another network's prefix is just text here.
	require.NoError(t, send(ctx, w.eng, w.s, args{cmd: "send", room: room, text: "!whatsapp logout"}, time.Second))
	select {
	case got := <-w.n.Sent:
		require.Equal(t, "!whatsapp logout", got.Body)
	case <-time.After(5 * time.Second):
		t.Fatal("the message never reached the network")
	}
	// So is ordinary text with a bang or the network's name later on.
	for _, text := range []string{"hey !telegram is cool", "!important", "telegram !logout"} {
		require.NoError(t, send(ctx, w.eng, w.s, args{cmd: "send", room: room, text: text}, time.Second), text)
		select {
		case got := <-w.n.Sent:
			require.Equal(t, text, got.Body)
		case <-time.After(5 * time.Second):
			t.Fatalf("%q never reached the network", text)
		}
	}
}

func TestEnsureNotLinked(t *testing.T) {
	ctx := context.Background()
	h, _, _ := startFake(t, 0)
	err := ensureNotLinked(ctx, h, "Fake Chat")
	require.EqualError(t, err, "already linked to Fake Chat — unlink this device in that app first, or use a fresh --data dir")

	w := startWorld(t, "fake", false, 0)
	empty, ok := w.eng.Host("fake")
	require.True(t, ok)
	require.NoError(t, ensureNotLinked(ctx, empty, "Fake Chat"), "a fresh data dir has no login, so link may proceed")
}

// loginCounter wraps the fake network to record CreateLogin calls and hand back a login that finishes at once.
type loginCounter struct {
	*fakenet.Network
	flows []string
	proc  *fakeProc
}

func (l *loginCounter) CreateLogin(_ context.Context, _ *bridgev2.User, flow string) (bridgev2.LoginProcess, error) {
	l.flows = append(l.flows, flow)
	return l.proc, nil
}

func startLinkable(t *testing.T, name string, linked bool) (*engine.Engine, *loginCounter) {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	lc := &loginCounter{Network: fakenet.New(), proc: &fakeProc{start: complete()}}
	eng, errs := engine.Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")},
		[]engine.Spec{{Name: name, Connector: func() (bridgev2.NetworkConnector, error) { return lc, nil }}}, zerolog.Nop())
	require.Empty(t, errs)
	t.Cleanup(eng.Stop)
	if linked {
		h, _ := eng.Host(name)
		_, err = lc.Network.Login(ctx, h.Bridge)
		require.NoError(t, err)
	}
	return eng, lc
}

func TestGoogleMessagesLinkWarnsFirst(t *testing.T) {
	gm := networks.Network{Name: "gmessages", DisplayName: "Google Messages", Flows: []string{"google"}}

	t.Run("declining starts no login and is not an error", func(t *testing.T) {
		eng, lc := startLinkable(t, "gmessages", false)
		p := &scripted{confirms: []bool{false}}
		var out bytes.Buffer
		linked, err := link(context.Background(), eng, gm, "", p, &out)
		require.NoError(t, err)
		require.False(t, linked)
		require.Equal(t, []string{"Google Messages allows one web session. Linking here disconnects it in Beeper. Continue?"}, p.askedWith("confirm"))
		require.Empty(t, lc.flows, "no login may be created after the user says no")
		require.Zero(t, lc.proc.cancelled)
	})

	t.Run("accepting links on the network's first flow", func(t *testing.T) {
		eng, lc := startLinkable(t, "gmessages", false)
		p := &scripted{confirms: []bool{true}}
		linked, err := link(context.Background(), eng, gm, "", p, &bytes.Buffer{})
		require.NoError(t, err)
		require.True(t, linked)
		require.Equal(t, []string{"google"}, lc.flows)
	})
}

func TestLinkOtherNetworksDoNotAskForConfirmation(t *testing.T) {
	eng, lc := startLinkable(t, "slack", false)
	sl := networks.Network{Name: "slack", DisplayName: "Slack", Flows: []string{"email", "token", "app"}}
	p := &scripted{} // any prompt would fail
	linked, err := link(context.Background(), eng, sl, "token", p, &bytes.Buffer{})
	require.NoError(t, err)
	require.True(t, linked)
	require.Equal(t, []string{"token"}, lc.flows, "--flow picks the flow")
	require.Empty(t, p.asked)
}

func TestGoogleMessagesAlreadyLinkedRefusesBeforeAsking(t *testing.T) {
	eng, lc := startLinkable(t, "gmessages", true)
	gm := networks.Network{Name: "gmessages", DisplayName: "Google Messages", Flows: []string{"google"}}
	p := &scripted{confirms: []bool{true}}
	linked, err := link(context.Background(), eng, gm, "", p, &bytes.Buffer{})
	require.ErrorContains(t, err, "already linked to Google Messages")
	require.False(t, linked)
	require.Empty(t, p.asked, "no warning is worth showing for a link that will be refused")
	require.Empty(t, lc.flows)
}

func TestLinkRefusesWhenAlreadyLinked(t *testing.T) {
	eng, lc := startLinkable(t, "slack", true)
	sl := networks.Network{Name: "slack", DisplayName: "Slack", Flows: []string{"email"}}
	linked, err := link(context.Background(), eng, sl, "", &scripted{}, &bytes.Buffer{})
	require.ErrorContains(t, err, "already linked to Slack")
	require.False(t, linked)
	require.Empty(t, lc.flows)
}

func TestLinkNetworkThatDidNotStart(t *testing.T) {
	eng, _ := startLinkable(t, "slack", false)
	tg := networks.Network{Name: "telegram", DisplayName: "Telegram", Flows: []string{"qr"}}
	_, err := link(context.Background(), eng, tg, "", &scripted{}, &bytes.Buffer{})
	require.ErrorContains(t, err, "Telegram")
	require.ErrorContains(t, err, "not running")
}

func TestStartCarriesOnPastAFailure(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	nets := []networks.Network{
		{Name: "telegram", DisplayName: "Telegram", Spec: func() (engine.Spec, error) {
			return engine.Spec{}, errors.New("Telegram needs its own app credentials: set COURIER_TELEGRAM_API_ID")
		}},
		{Name: "fake", DisplayName: "Fake", Spec: func() (engine.Spec, error) {
			return engine.Spec{Name: "fake", Connector: func() (bridgev2.NetworkConnector, error) { return fakenet.New(), nil }}, nil
		}},
	}
	eng, errs := networks.Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, nets, zerolog.Nop())
	defer eng.Stop()
	require.Equal(t, []string{"fake"}, eng.Names(), "the network that could start runs")
	require.Len(t, errs, 1)
	require.ErrorContains(t, errs["telegram"], "COURIER_TELEGRAM_API_ID")

	var out bytes.Buffer
	reportNotStarted(&out, errs)
	require.Equal(t, "telegram: not started — Telegram needs its own app credentials: set COURIER_TELEGRAM_API_ID\n", out.String())
}

// Never log who: a bridge's start-up error can quote an account or a contact, and is printed redacted.
func TestReportNotStartedNamesNoOne(t *testing.T) {
	var out bytes.Buffer
	reportNotStarted(&out, map[string]error{
		"whatsapp": errors.New("start whatsapp bridge: no device for 15557654321@s.whatsapp.net"),
	})
	require.Equal(t, "whatsapp: not started — start whatsapp bridge: no device for [id]\n", out.String())
}

func TestReportNotStartedIsSortedAndSilentWhenEmpty(t *testing.T) {
	var out bytes.Buffer
	reportNotStarted(&out, nil)
	require.Empty(t, out.String())
	reportNotStarted(&out, map[string]error{"slack": errors.New("b"), "gmessages": errors.New("a")})
	require.Equal(t, "gmessages: not started — a\nslack: not started — b\n", out.String())
}

func TestFirstCtrlCHandsTheSecondToTheDefaultHandler(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	released := make(chan struct{})
	releaseSignalWhenDone(ctx, func() { close(released) })
	select {
	case <-released:
		t.Fatal("Ctrl-C was handed back before the first one arrived")
	case <-time.After(50 * time.Millisecond):
	}
	cancel() // the first Ctrl-C
	select {
	case <-released:
	case <-time.After(5 * time.Second):
		t.Fatal("after the first Ctrl-C a second one must end the process, not be swallowed")
	}
}

// send waits for the chat's own login, not any login of its network: a chat of a second account that is signed out
// is refused while the first is in, with nothing stored (review fix round 1).
func TestSendWaitsForTheChatsOwnLogin(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true, 0)
	h, ok := w.eng.Host("fake")
	require.True(t, ok)
	b, err := w.n.LoginAs(ctx, h.Bridge, "second", "Work")
	require.NoError(t, err)
	w.n.SetLoggedIn(b, false)
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!b:courier.local", Network: "fake", Name: "Test"}))
	require.NoError(t, w.s.SetRoomLogin(ctx, "!b:courier.local", "second"))

	err = send(ctx, w.eng, w.s, args{cmd: "send", room: "!b:courier.local", text: "hello"}, 300*time.Millisecond)
	require.ErrorIs(t, err, errNotConnected)
	evs, err := w.s.Events(ctx, "!b:courier.local", 10)
	require.NoError(t, err)
	require.Empty(t, evs, "nothing may be stored when the send is refused")
}

// Never log who: the CLI prints its log for a person to read, and what the bridges log in it names no contact or chat.
func TestTheCLIsLogNamesNoOne(t *testing.T) {
	var out bytes.Buffer
	log := newLog(&out)
	log.Warn().Str("bridge", "whatsapp").Str("portal_id", "15557654321@s.whatsapp.net").
		Str("pn", "+15557654321").Msg("Failed to sync 15557654321@s.whatsapp.net")
	log.Info().Msg("below warn")
	require.NotContains(t, out.String(), "15557654321")
	require.NotContains(t, out.String(), "portal_id")
	require.Contains(t, out.String(), "Failed to sync [id]")
	require.Contains(t, out.String(), "whatsapp")
	require.NotContains(t, out.String(), "below warn")
}
