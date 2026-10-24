// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"go.mau.fi/util/jsontime"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
	"github.com/VitruvianSoftware/courier/engine/internal/timers"
)

// testClock is an injected clock a test moves by hand.
type testClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *testClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *testClock) Set(t time.Time) {
	c.mu.Lock()
	c.t = t
	c.mu.Unlock()
}

// clocked gives the world's store (and so its actions) a clock fixed at the wall time now, which the test moves.
func (w world) clocked() *testClock {
	c := &testClock{t: time.UnixMilli(time.Now().UnixMilli())}
	w.s.SetClock(c.Now)
	return c
}

func anyFiles() event.FileFeatureMap {
	anyFile := func() *event.FileFeatures {
		return &event.FileFeatures{MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported}}
	}
	return event.FileFeatureMap{event.MsgImage: anyFile(), event.MsgVideo: anyFile(), event.MsgAudio: anyFile(), event.MsgFile: anyFile()}
}

func allFormatting() event.FormattingFeatureMap {
	m := event.FormattingFeatureMap{}
	for _, f := range formattingKinds {
		m[f.feature] = event.CapLevelFullySupported
	}
	return m
}

// slackFeatures is a chat like Slack's: every formatting and @room, threads and no plain replies, edits and unsends.
func slackFeatures() *event.RoomFeatures {
	f := allFormatting()
	f[event.FmtSpoiler] = event.CapLevelUnsupported
	f[event.FmtAtRoomMention] = event.CapLevelFullySupported
	return &event.RoomFeatures{
		Formatting: f, Thread: event.CapLevelFullySupported, Reaction: event.CapLevelFullySupported,
		Edit: event.CapLevelFullySupported, Delete: event.CapLevelFullySupported, File: anyFiles(),
	}
}

// whatsappFeatures is a chat like WhatsApp's: formatting without spoilers or @room, replies, edits for 15 minutes,
// unsends for 2 days, polls of 12 options of 100 characters, after-send timers of 1, 7 and 90 days.
func whatsappFeatures() *event.RoomFeatures {
	f := allFormatting()
	f[event.FmtSpoiler] = event.CapLevelUnsupported
	return &event.RoomFeatures{
		Formatting: f, Reply: event.CapLevelFullySupported, Reaction: event.CapLevelFullySupported,
		Edit: event.CapLevelFullySupported, EditMaxAge: seconds(15 * time.Minute),
		Delete: event.CapLevelFullySupported, DeleteMaxAge: seconds(48 * time.Hour),
		Poll: event.CapLevelFullySupported, PollMaxOptions: 12, PollOptionMaxLength: 100,
		DisappearingTimer: &event.DisappearingTimerCapability{
			Types: []event.DisappearingType{event.DisappearingTypeAfterSend},
			Timers: []jsontime.Milliseconds{
				jsontime.MS(24 * time.Hour), jsontime.MS(7 * 24 * time.Hour), jsontime.MS(90 * 24 * time.Hour),
			},
		},
		File: anyFiles(),
	}
}

// googleMessagesFeatures is a chat like Google Messages': no formatting, replies, and a deletion that reaches only
// the phone (delete_for_me).
func googleMessagesFeatures() *event.RoomFeatures {
	return &event.RoomFeatures{
		Reply: event.CapLevelFullySupported, Reaction: event.CapLevelFullySupported,
		Delete: event.CapLevelFullySupported, DeleteForMe: true, File: anyFiles(),
	}
}

// content reads a stored event's content as a map.
func content(t *testing.T, e store.Event) map[string]any {
	t.Helper()
	var m map[string]any
	require.NoError(t, json.Unmarshal(e.Content, &m))
	return m
}

// eventCount is how many events the store has in room, of any kind.
func (w world) eventCount(t *testing.T, room string) int {
	t.Helper()
	evs, err := w.s.Events(context.Background(), room, 1000)
	require.NoError(t, err)
	return len(evs)
}

// mySent sends text and waits for the network to take it.
func (w world) mySent(t *testing.T, room, text string) string {
	t.Helper()
	id, err := w.a.SendText(context.Background(), room, text, "")
	require.NoError(t, err)
	recv(t, w.n.Sent, "the message")
	w.waitStatus(t, id, "sent")
	return id
}

func TestSendRendersForTheChatsFeatures(t *testing.T) {
	ctx := context.Background()
	bold := []richtext.Entity{{Kind: richtext.Bold, Offset: 0, Length: 2}}
	everyone := []richtext.Entity{{Kind: richtext.Mention, Offset: 8, Length: 5, UserID: richtext.RoomMention}}

	// Slack keeps bold, and @room reaches everyone.
	w, room := startFeatureWorld(t, slackFeatures())
	id, err := w.a.Send(ctx, room, "hi there", SendOptions{Entities: bold})
	require.NoError(t, err)
	c := content(t, w.get(t, id))
	require.Equal(t, "hi there", c["body"])
	require.Equal(t, "org.matrix.custom.html", c["format"])
	require.Equal(t, "<strong>hi</strong> there", c["formatted_body"])
	require.NotContains(t, c, "m.mentions", "nobody named")
	require.Equal(t, "hi there", recv(t, w.n.Sent, "the message").Body)
	id, err = w.a.Send(ctx, room, "heads up @room", SendOptions{Entities: everyone})
	require.NoError(t, err)
	require.Equal(t, map[string]any{"room": true}, content(t, w.get(t, id))["m.mentions"])
	recv(t, w.n.Sent, "the @room message")

	// WhatsApp keeps mentions but not @room: it is plain text there and mentions nobody.
	w, room = startFeatureWorld(t, whatsappFeatures())
	id, err = w.a.Send(ctx, room, "heads up @room", SendOptions{Entities: everyone})
	require.NoError(t, err)
	c = content(t, w.get(t, id))
	require.NotContains(t, c, "m.mentions")
	require.NotContains(t, c, "formatted_body")
	recv(t, w.n.Sent, "the message")

	// A chat that keeps no formatting gets the body only.
	w, room = startFeatureWorld(t, googleMessagesFeatures())
	id, err = w.a.Send(ctx, room, "hi there", SendOptions{Entities: bold})
	require.NoError(t, err)
	c = content(t, w.get(t, id))
	require.Equal(t, map[string]any{"msgtype": "m.text", "body": "hi there"}, c)
	require.Equal(t, "hi there", recv(t, w.n.Sent, "the message").Body)

	// Ranges that don't fit the text are refused, and leave no trace.
	before := w.eventCount(t, room)
	_, err = w.a.Send(ctx, room, "hi", SendOptions{Entities: []richtext.Entity{{Kind: richtext.Bold, Offset: 1, Length: 9}}})
	require.ErrorIs(t, err, ErrBadValue)
	require.ErrorIs(t, err, richtext.ErrBadEntity)
	require.Equal(t, before, w.eventCount(t, room))
}

func TestTextOverTheCapIsRefused(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	before := w.eventCount(t, room)
	_, err := w.a.Send(ctx, room, strings.Repeat("a", MaxTextBytes+1), SendOptions{})
	require.ErrorIs(t, err, ErrTooLong)
	_, err = w.a.SendText(ctx, room, strings.Repeat("é", MaxTextBytes/2+1), "") // bytes, not characters
	require.ErrorIs(t, err, ErrTooLong)
	require.Equal(t, before, w.eventCount(t, room))
	require.Empty(t, w.n.Sent)

	id, err := w.a.Send(ctx, room, strings.Repeat("a", MaxTextBytes), SendOptions{})
	require.NoError(t, err)
	require.Len(t, recv(t, w.n.Sent, "the longest message").Body, MaxTextBytes)
	w.waitStatus(t, id, "sent")
}

func TestSendIntoAThread(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, slackFeatures())
	root := w.firstID(t, room)

	// The first reply falls back to the root.
	first, err := w.a.Send(ctx, room, "first", SendOptions{ThreadRoot: root})
	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"rel_type": "m.thread", "event_id": root, "is_falling_back": true,
		"m.in_reply_to": map[string]any{"event_id": root},
	}, relatesTo(t, w.get(t, first)))
	require.Equal(t, "first", recv(t, w.n.Sent, "the first reply").Body)
	w.waitStatus(t, first, "sent")

	// The next falls back to the thread's newest reply.
	second, err := w.a.Send(ctx, room, "second", SendOptions{ThreadRoot: root})
	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"rel_type": "m.thread", "event_id": root, "is_falling_back": true,
		"m.in_reply_to": map[string]any{"event_id": first},
	}, relatesTo(t, w.get(t, second)))
	recv(t, w.n.Sent, "the second reply")
	w.waitStatus(t, second, "sent")

	// A newer reply the network refused isn't one to fall back to: the newest sent reply is.
	w.insertMine(t, room, "m.room.message", fmt.Sprintf(
		`{"msgtype":"m.text","body":"refused","m.relates_to":{"rel_type":"m.thread","event_id":%q,"is_falling_back":true,"m.in_reply_to":{"event_id":%q}}}`,
		root, second,
	), "failed", time.Now().Add(time.Second))
	// Nor one still waiting for its network: it hasn't gone yet.
	w.insertMine(t, room, "m.room.message", fmt.Sprintf(
		`{"msgtype":"m.text","body":"waiting","m.relates_to":{"rel_type":"m.thread","event_id":%q,"is_falling_back":true,"m.in_reply_to":{"event_id":%q}}}`,
		root, second,
	), store.StatusWaiting, time.Now().Add(2*time.Second))
	fallback, err := w.a.Send(ctx, room, "after the refused one", SendOptions{ThreadRoot: root})
	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"rel_type": "m.thread", "event_id": root, "is_falling_back": true,
		"m.in_reply_to": map[string]any{"event_id": second},
	}, relatesTo(t, w.get(t, fallback)))
	recv(t, w.n.Sent, "the reply after the refused one")

	// A reply to one message of the thread is a real reply, not a fallback.
	third, err := w.a.Send(ctx, room, "third", SendOptions{ThreadRoot: root, ReplyTo: first})
	require.NoError(t, err)
	require.Equal(t, map[string]any{
		"rel_type": "m.thread", "event_id": root, "m.in_reply_to": map[string]any{"event_id": first},
	}, relatesTo(t, w.get(t, third)))
	recv(t, w.n.Sent, "the third reply")

	page, _, err := w.s.ThreadEventsBefore(ctx, room, root, nil, 10)
	require.NoError(t, err)
	require.Len(t, page, 6, "first, second, the refused one, the waiting one, the one after them and third")
}

// firstID is the ID of the contact's first message in room.
func (w world) firstID(t *testing.T, room string) string {
	t.Helper()
	evs, err := w.s.Events(context.Background(), room, 1)
	require.NoError(t, err)
	require.Len(t, evs, 1)
	return evs[0].EventID
}

func TestThreadOnAChatWithoutThreadsIsRefused(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	root := w.firstID(t, room)
	_, err := w.a.Send(ctx, room, "in a thread", SendOptions{ThreadRoot: root})
	require.ErrorIs(t, err, ErrNotSupported)
	require.Equal(t, 1, w.eventCount(t, room), "nothing stored")
	require.Empty(t, w.n.Sent)
}

func TestSendCarriesTheChatsTimer(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_send", 24*time.Hour))
	recv(t, w.n.Timers, "the timer")

	id, err := w.a.Send(ctx, room, "gone tomorrow", SendOptions{})
	require.NoError(t, err)
	e := w.get(t, id)
	require.Equal(t, map[string]any{"type": "after_send", "timer": float64(86400000)}, content(t, e)["com.beeper.disappearing_timer"])
	require.Equal(t, e.TS.Add(24*time.Hour), e.ExpiresAt, "the store expires it itself")
	recv(t, w.n.Sent, "the message")

	// Off again: messages carry no timer.
	require.NoError(t, w.a.SetDisappearing(ctx, room, "", 0))
	recv(t, w.n.Timers, "the timer turned off")
	id, err = w.a.Send(ctx, room, "stays", SendOptions{})
	require.NoError(t, err)
	require.NotContains(t, content(t, w.get(t, id)), "com.beeper.disappearing_timer")
	require.True(t, w.get(t, id).ExpiresAt.IsZero())
	recv(t, w.n.Sent, "the message")
}

// An after-read timer (Signal) goes with the message too; it starts when the message is read, so the store sets no
// expiry of its own.
func TestSendCarriesAnAfterReadTimer(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, &event.RoomFeatures{
		Reply: event.CapLevelFullySupported,
		DisappearingTimer: &event.DisappearingTimerCapability{
			Types: []event.DisappearingType{event.DisappearingTypeAfterRead},
		},
	})
	require.NoError(t, w.a.SetDisappearing(ctx, room, "after_read", 30*time.Second))
	recv(t, w.n.Timers, "the timer")
	id, err := w.a.Send(ctx, room, "read and gone", SendOptions{})
	require.NoError(t, err)
	e := w.get(t, id)
	require.Equal(t, map[string]any{"type": "after_read", "timer": float64(30000)}, content(t, e)["com.beeper.disappearing_timer"])
	require.True(t, e.ExpiresAt.IsZero())
	recv(t, w.n.Sent, "the message")
}

// waitClock is the timer loop's clock in these tests: the wall clock, and timers that never fire. The loop only wakes
// when poked (a send, a bridge state), so what it does is driven by the test, never by time passing.
type waitClock struct{}

func (waitClock) Now() time.Time                       { return time.Now() }
func (waitClock) After(time.Duration) <-chan time.Time { return nil }

// loop runs the engine's timer loop over the world's actions until the test ends.
func (w world) loop(t *testing.T) {
	t.Helper()
	tm := timers.New(w.s, entitlement.Always{}, waitClock{}, zerolog.Nop())
	tm.SetDispatcher(w.a)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		tm.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
}

// down logs the world's login out (fakenet's SetLoggedIn), at once; up logs it back in, and its bridge state tells
// the store, which wakes the loop.
func (w world) down() { w.n.SetLoggedIn(w.login, false) }
func (w world) up()   { w.n.SetLoggedIn(w.login, true) }

// Review Focus 1: a message sent while its network is down is stored waiting and answered at once, reaches nothing,
// and goes once, by the timer loop, when the login is back.
func TestSendWhileDownWaitsThenGoesWhenConnected(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	w.a.LoginWait = time.Hour // a send never waits for it
	w.down()
	w.loop(t)

	id, err := w.a.SendText(ctx, room, "while down", "")
	require.NoError(t, err, "answered at once")
	e := w.get(t, id)
	require.Equal(t, store.StatusWaiting, e.Status)
	src, ok := SourceOf(e.Content)
	require.True(t, ok, "Don't Send gives back what was typed")
	require.Equal(t, "while down", src.Text)
	none(t, w.n.Sent, "a message while down")

	w.up()
	require.Equal(t, fakenet.Sent{PortalID: "chat1", Body: "while down"}, recv(t, w.n.Sent, "the waiting message"))
	w.waitStatus(t, id, "sent")
	none(t, w.n.Sent, "the waiting message a second time")
	for _, raw := range w.n.Raws() {
		require.NotContains(t, string(raw), store.SourceKey, "what was typed never reaches the bridge")
	}
}

// Review Focus 1: messages typed while down go in the order they were typed, files and texts alike.
func TestWaitingMessagesGoOldestFirst(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	clock := w.clocked()
	w.down()
	var sent []string
	for i, text := range []string{"one", "two", "three"} {
		clock.Set(clock.Now().Add(time.Duration(i) * time.Millisecond))
		id, err := w.a.SendText(ctx, room, text, "")
		require.NoError(t, err)
		require.Equal(t, store.StatusWaiting, w.get(t, id).Status)
		sent = append(sent, id)
	}
	file, err := w.a.SendFile(ctx, room, writeFile(t, "four.txt", []byte("4")), "")
	require.NoError(t, err)
	require.Equal(t, store.StatusWaiting, w.get(t, file).Status)

	w.up()
	w.a.SendWaiting(ctx, "fake")
	for _, text := range []string{"one", "two", "three"} {
		require.Equal(t, text, recv(t, w.n.Sent, text).Body)
	}
	require.Equal(t, "four.txt", recv(t, w.n.Files, "the file").FileName)
	for _, id := range append(sent, file) {
		w.waitStatus(t, id, "sent")
	}
}

// Ruling C33: a send in a chat that already has messages waiting waits behind them, even once the network is back,
// so it never overtakes them.
func TestSendBehindWaitingMessagesWaitsToo(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	w.down()
	first, err := w.a.SendText(ctx, room, "first", "")
	require.NoError(t, err)
	w.n.SetLoggedIn(w.login, true) // back, but the loop hasn't run yet
	second, err := w.a.SendText(ctx, room, "second", "")
	require.NoError(t, err)
	require.Equal(t, store.StatusWaiting, w.get(t, second).Status)
	none(t, w.n.Sent, "the second message ahead of the first")

	w.a.SendWaiting(ctx, "fake")
	require.Equal(t, "first", recv(t, w.n.Sent, "the first").Body)
	require.Equal(t, "second", recv(t, w.n.Sent, "the second").Body)
	w.waitStatus(t, first, "sent")
	w.waitStatus(t, second, "sent")
}

// startGate holds a network's start until release is closed, so a test sees the network STARTING.
type startGate struct {
	*fakenet.Network
	entered, release chan struct{}
}

func (g *startGate) Start(ctx context.Context) error {
	close(g.entered)
	<-g.release
	return g.Network.Start(ctx)
}

// restart stops the world's engine and starts a new one over the same store and data directory, as Courier quitting
// and opening does, with the network held in its start: until the returned up is called it is STARTING. up lets the
// start finish and returns the world with its login, loaded again by the bridge.
func (w world) restart(t *testing.T, name string) (starting world, up func() world) {
	t.Helper()
	w.eng.Stop()
	gate := &startGate{Network: w.n, entered: make(chan struct{}), release: make(chan struct{})}
	specs := []engine.Spec{{Name: name, Connector: func() (bridgev2.NetworkConnector, error) { return gate, nil }}}
	eng := engine.New(w.s)
	t.Cleanup(eng.Stop)
	var once sync.Once
	release := func() { once.Do(func() { close(gate.release) }) }
	t.Cleanup(release) // before eng.Stop, which waits for the start
	eng.Expect(specs)
	done := make(chan struct{})
	go func() {
		defer close(done)
		eng.StartNetworks(context.Background(), w.dir, w.m, specs, zerolog.Nop())
	}()
	<-gate.entered
	starting = world{eng: eng, s: w.s, m: w.m, n: w.n, a: New(eng, w.s, w.m), dir: w.dir}
	return starting, func() world {
		t.Helper()
		release()
		<-done
		h, ok := eng.Host(name)
		require.True(t, ok)
		require.Eventually(t, func() bool {
			starting.login = h.Bridge.GetCachedUserLoginByID("fake-login")
			return starting.login != nil
		}, 5*time.Second, 20*time.Millisecond, "the login was never loaded again")
		return starting
	}
}

// Task 2's ErrStarting: a send in a chat whose network hasn't started yet is stored waiting at once (composed with the
// chat's network from the store, Ruling C40), and goes once the network runs and its login is in.
func TestSendWhileStartingWaits(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	starting, up := w.restart(t, "fake")
	require.True(t, starting.eng.Status("fake").Starting)

	id, err := starting.a.SendText(ctx, room, "while starting", "")
	require.NoError(t, err)
	require.Equal(t, store.StatusWaiting, starting.get(t, id).Status)
	held, err := starting.a.Send(ctx, room, "held while starting", SendOptions{Hold: time.Second})
	require.NoError(t, err)
	require.Equal(t, "queued", starting.get(t, held).Status, "a held send is held first (Ruling C40)")
	_, err = starting.a.Undo(ctx, held)
	require.NoError(t, err)
	none(t, w.n.Sent, "a message while starting")

	running := up()
	running.a.SendWaiting(ctx, "fake")
	require.Equal(t, "while starting", recv(t, w.n.Sent, "the waiting message").Body)
	running.waitStatus(t, id, "sent")
}

// Retry of a failed message while its network is down waits like a new one, and goes when the login is back.
func TestRetryWhileDownWaits(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	w.n.FailWith(errors.New("the network said no"))
	id, err := w.a.SendText(ctx, room, "again", "")
	require.NoError(t, err)
	w.waitStatus(t, id, "failed")
	w.n.FailWith(nil)

	w.down()
	w.a.LoginWait = time.Hour // Retry never waits for it either
	require.NoError(t, w.a.Retry(ctx, id))
	e := w.get(t, id)
	require.Equal(t, store.StatusWaiting, e.Status)
	require.Empty(t, e.StatusReason)
	none(t, w.n.Sent, "a retry while down")
	require.ErrorIs(t, w.a.Retry(ctx, id), ErrNotFailed, "waiting is not failed")

	w.up()
	w.a.SendWaiting(ctx, "fake")
	require.Equal(t, "again", recv(t, w.n.Sent, "the retried message").Body)
	w.waitStatus(t, id, "sent")
}

// loginTimer is the login wait's injected timer: After reports each wait it starts on started, and nothing fires
// until the test says so (fire), so the wait and its refusal are driven, never timed.
type loginTimer struct {
	mu      sync.Mutex
	started chan time.Duration
	waits   map[time.Duration][]chan time.Time
}

func newLoginTimer() *loginTimer {
	return &loginTimer{started: make(chan time.Duration, 1024), waits: map[time.Duration][]chan time.Time{}}
}

func (l *loginTimer) After(d time.Duration) <-chan time.Time {
	ch := make(chan time.Time, 1)
	l.mu.Lock()
	l.waits[d] = append(l.waits[d], ch)
	l.mu.Unlock()
	select {
	case l.started <- d:
	default:
	}
	return ch
}

// awaitWait waits until a wait of d has started.
func (l *loginTimer) awaitWait(t *testing.T, d time.Duration) {
	t.Helper()
	timeout := time.After(5 * time.Second)
	for {
		select {
		case got := <-l.started:
			if got == d {
				return
			}
		case <-timeout:
			t.Fatalf("no wait of %s started", d)
		}
	}
}

// fire ends every wait of d started so far.
func (l *loginTimer) fire(d time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	for _, ch := range l.waits[d] {
		ch <- time.Now()
	}
	delete(l.waits, d)
}

// 4.3's rule stands for everything but a new message: an edit or a reaction waits up to LoginWait for the login,
// goes the moment the login is back (woken by its bridge state, Ruling P5), and is refused as not connected when the
// wait runs out, with nothing sent.
func TestEditsAndReactionsStillWaitForTheLogin(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	msg := w.mySent(t, room, "hello")
	lt := newLoginTimer()
	w.a.after = lt.After
	w.a.LoginWait = time.Minute

	w.down()
	reacted := make(chan error, 1)
	go func() {
		_, err := w.a.React(ctx, room, msg, "👍")
		reacted <- err
	}()
	lt.awaitWait(t, time.Minute)
	none(t, w.n.Reactions, "a reaction while down")
	w.up()
	require.Equal(t, "👍", recv(t, w.n.Reactions, "the reaction once the login is back").Emoji)
	require.NoError(t, <-reacted)

	w.down()
	edited := make(chan error, 1)
	go func() {
		_, err := w.a.Edit(ctx, msg, "hello there", nil)
		edited <- err
	}()
	lt.awaitWait(t, time.Minute)
	lt.fire(time.Minute)
	require.ErrorIs(t, <-edited, ErrNotConnected)
	none(t, w.n.Edits, "an edit refused while down")
	_, err := w.a.Send(ctx, room, "a new message waits instead", SendOptions{})
	require.NoError(t, err)
}

// Review Focus 5: a send goes out through the chat's own login. A chat of login B waits while only A is logged in,
// and goes when B is; A's chats go at once meanwhile.
func TestSendUsesTheChatsOwnLogin(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	roomA, _ := w.chat(t, "chatA", "m1")
	h, ok := w.eng.Host("fake")
	require.True(t, ok)
	b, err := w.n.LoginAs(ctx, h.Bridge, "second", "Work")
	require.NoError(t, err)
	w.n.Incoming(b, "chatB", "bob", "m2", "hello")
	roomB, _ := w.firstMessage(t, roomA)
	require.NoError(t, w.s.SetRoomLogin(ctx, roomA, string(w.login.ID)))
	require.NoError(t, w.s.SetRoomLogin(ctx, roomB, "second"))

	w.n.SetLoggedIn(b, false)
	idB, err := w.a.SendText(ctx, roomB, "for B", "")
	require.NoError(t, err)
	require.Equal(t, store.StatusWaiting, w.get(t, idB).Status, "B is down, though A is in")
	idA, err := w.a.SendText(ctx, roomA, "for A", "")
	require.NoError(t, err)
	require.Equal(t, fakenet.Sent{PortalID: "chatA", Body: "for A"}, recv(t, w.n.Sent, "A's message"))
	w.waitStatus(t, idA, "sent")

	w.a.SendWaiting(ctx, "fake")
	none(t, w.n.Sent, "B's message while B is down")
	require.Equal(t, store.StatusWaiting, w.get(t, idB).Status)

	w.n.SetLoggedIn(b, true)
	w.a.SendWaiting(ctx, "fake")
	require.Equal(t, fakenet.Sent{PortalID: "chatB", Body: "for B"}, recv(t, w.n.Sent, "B's message"))
	w.waitStatus(t, idB, "sent")
}
