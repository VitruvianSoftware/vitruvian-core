// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"go.mau.fi/util/jsontime"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
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

// loop runs the engine's timer loop over the world's actions until the test ends, wired as the engine wires it (the
// actions' Wake pokes it), and returns it.
func (w world) loop(t *testing.T) *timers.Timers {
	t.Helper()
	return w.loopWith(t, w.a)
}

// loopWith is loop with d as the loop's dispatcher.
func (w world) loopWith(t *testing.T, d timers.Dispatcher) *timers.Timers {
	t.Helper()
	tm := timers.New(w.s, entitlement.Always{}, waitClock{}, zerolog.Nop())
	tm.SetDispatcher(d)
	w.a.Wake = tm.Poke
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
	return tm
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
		// bridgev2's Start loads the logins before it returns (StartLogins), and the start has returned.
		starting.login = h.Bridge.GetCachedUserLoginByID("fake-login")
		require.NotNil(t, starting.login, "the login was loaded again")
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

// Review Focus 5 (Ruling 4): the actions that still wait wait for the chat's own login, not any login of the network:
// a reaction in B's chat waits while only A is in, and goes when B is.
func TestWaitingActionsWaitForTheChatsOwnLogin(t *testing.T) {
	ctx := context.Background()
	w, roomA := startFeatureWorld(t, whatsappFeatures())
	b := w.work(t)
	w.n.Incoming(b, "chatB", "bob", "b1", "for B")
	roomB := w.roomWith(t, "for B").ID
	msg := w.mySent(t, roomB, "hello")
	lt := newLoginTimer()
	w.a.after = lt.After
	w.a.LoginWait = time.Minute

	w.n.SetLoggedIn(b, false)
	w.up() // A is in
	reacted := make(chan error, 1)
	go func() {
		_, err := w.a.React(ctx, roomB, msg, "👍")
		reacted <- err
	}()
	lt.awaitWait(t, time.Minute)
	// The wait is Courier's, not the bridge's: nothing is stored or handed over, and React hasn't answered.
	none(t, reacted, "React's answer while only A is in")
	_, staged, err := w.s.FindReaction(ctx, roomB, string(ids.Me), msg, "👍")
	require.NoError(t, err)
	require.False(t, staged, "a reaction stored while B is down")
	none(t, w.n.Reactions, "B's reaction while only A is in")
	w.n.SetLoggedIn(b, true)
	require.Equal(t, fakenet.Reaction{PortalID: "chatB", TargetID: "out-" + msg, Emoji: "👍"},
		recv(t, w.n.Reactions, "the reaction once B is back"))
	require.NoError(t, <-reacted)

	// A's chat doesn't wait for B.
	mine := w.mySent(t, roomA, "hi")
	w.n.SetLoggedIn(b, false)
	_, err = w.a.React(ctx, roomA, mine, "👍")
	require.NoError(t, err)
	require.Equal(t, "👍", recv(t, w.n.Reactions, "A's reaction").Emoji)
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

// reporting is the actions as the loop's dispatcher, reporting each SendWaiting run once it has returned.
type reporting struct {
	*Actions
	ran chan string
}

func (d reporting) SendWaiting(ctx context.Context, network string) {
	d.Actions.SendWaiting(ctx, network)
	select {
	case d.ran <- network:
	default: // nobody is counting runs any more: never hold the loop up
	}
}

func (d reporting) await(t *testing.T) {
	t.Helper()
	select {
	case <-d.ran:
	case <-time.After(5 * time.Second): // a deadlock guard, not a measure
		t.Fatal("SendWaiting never ran")
	}
}

// While every login is down, the loop's passes, through the real SendWaiting (its retell, then its early return),
// claim nothing and change nothing: no "status" change at all across passes, so the app's rows don't flicker every
// 30 s. A chat change kept for the network stays kept, and goes once the login is back.
func TestWaitingClaimsNothingWhileEveryLoginIsDown(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	w.down()
	id, err := w.a.SendText(ctx, room, "while down", "")
	require.NoError(t, err)
	require.NoError(t, w.a.SetPinned(ctx, room, true)) // kept for the network
	feed, cancel := w.s.Subscribe()
	defer cancel()
	d := reporting{Actions: w.a, ran: make(chan string, 64)}
	tm := w.loopWith(t, d)
	d.await(t)
	for range 3 {
		tm.Poke()
		d.await(t)
	}
	for len(feed) > 0 {
		c := <-feed
		require.NotEqual(t, "status", c.Kind, "a pass changed a message: %+v", c)
	}
	require.Equal(t, store.StatusWaiting, w.get(t, id).Status)
	none(t, w.n.Sent, "a message while down")
	none(t, w.n.Tags, "a pin while down")

	w.up()
	require.Equal(t, "while down", recv(t, w.n.Sent, "the waiting message").Body)
	require.Equal(t, fakenet.TagChange{PortalID: "chat1", Tags: []event.RoomTag{event.RoomTagFavourite}}, recv(t, w.n.Tags, "the pin"))
	w.waitStatus(t, id, "sent")
}

func TestSendVoiceSelectsContainerPerBridgeCapabilities(t *testing.T) {
	ctx := context.Background()
	tmpDir := t.TempDir()
	rawM4APath := filepath.Join(tmpDir, "rec.m4a")
	require.NoError(t, os.WriteFile(rawM4APath, []byte("\x00\x00\x00\x20ftypM4A \x00\x00\x02\x00M4A mp42isom"), 0o600))

	fakeFFmpeg := filepath.Join(tmpDir, "ffmpeg")
	script := "#!/bin/sh\nout=\"\"\nfor arg in \"$@\"; do out=\"$arg\"; done\nprintf 'OggS\\000\\002fake-opus' > \"$out\"\n"
	require.NoError(t, os.WriteFile(fakeFFmpeg, []byte(script), 0o755))

	// Case 1: Bridge capability requires Ogg/Opus (e.g. WhatsApp) — must transcode via ffmpeg.
	waVoiceCaps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgVoice: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"audio/ogg; codecs=opus": event.CapLevelFullySupported,
				},
				MaxSize: 16 * 1024 * 1024,
			},
		},
	}
	wOgg, roomOgg := startFeatureWorld(t, waVoiceCaps)
	resOgg, err := wOgg.a.SendVoice(ctx, roomOgg, rawM4APath, SendVoiceOpts{
		DurationMS: 4200,
		Waveform:   []int{10, 80, 40},
		FFmpegPath: fakeFFmpeg,
	})
	require.NoError(t, err)
	require.NotEmpty(t, resOgg.EventID)
	sentOgg := recv(t, wOgg.n.Files, "the ogg voice note")
	require.Equal(t, event.MsgAudio, sentOgg.MsgType)
	require.Equal(t, "audio/ogg; codecs=opus", sentOgg.MimeType)
	storedOgg := wOgg.get(t, resOgg.EventID)
	store.ExtractEventMedia(&storedOgg, wOgg.m, false)
	require.Equal(t, 4200, storedOgg.DurationMS)
	require.Equal(t, []int{10, 80, 40}, storedOgg.Waveform)
	oggHash, ok := ids.ParseContentURI(id.ContentURIString(sentOgg.URL))
	require.True(t, ok)
	oggData, err := wOgg.m.Read(oggHash)
	require.NoError(t, err)
	require.True(t, bytes.HasPrefix(oggData, []byte("OggS")), "transcoded voice note must start with OggS header")

	// Case 2: Bridge capability accepts AAC / MP4 natively (e.g. Signal / Telegram / Google Messages / Slack) —
	// sends directly without invoking ffmpeg even if ffmpeg is missing.
	aacVoiceCaps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgVoice: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"audio/aac": event.CapLevelFullySupported,
				},
				MaxSize: 100 * 1024 * 1024,
			},
		},
	}
	wAAC, roomAAC := startFeatureWorld(t, aacVoiceCaps)
	resAAC, err := wAAC.a.SendVoice(ctx, roomAAC, rawM4APath, SendVoiceOpts{
		DurationMS: 3100,
		Waveform:   []int{25, 50, 75},
		FFmpegPath: "/nonexistent/ffmpeg",
	})
	require.NoError(t, err)
	require.NotEmpty(t, resAAC.EventID)
	sentAAC := recv(t, wAAC.n.Files, "the aac voice note")
	require.Equal(t, event.MsgAudio, sentAAC.MsgType)
	require.Equal(t, "audio/aac", sentAAC.MimeType)

	// Case 3: Bridge requires Ogg/Opus and ffmpeg is unavailable — fails cleanly with ErrVoiceTranscodeUnavailable.
	_, err = wOgg.a.SendVoice(ctx, roomOgg, rawM4APath, SendVoiceOpts{
		DurationMS: 4200,
		Waveform:   []int{10, 80, 40},
		FFmpegPath: "/nonexistent/ffmpeg",
	})
	require.ErrorIs(t, err, ErrVoiceTranscodeUnavailable)
}

func TestSendLocationQueuesGeoURIAndRespectsCapability(t *testing.T) {
	ctx := context.Background()
	locSupported := &event.RoomFeatures{
		LocationMessage: event.CapLevelFullySupported,
		Reply:           event.CapLevelFullySupported,
	}
	w, room := startFeatureWorld(t, locSupported)

	res, err := w.a.SendLocation(ctx, room, 37.7749, -122.4194, "Mission Dolores Park", "")
	require.NoError(t, err)
	require.NotEmpty(t, res.EventID)
	sent := recv(t, w.n.Files, "the location message")
	require.Equal(t, event.MsgLocation, sent.MsgType)
	require.Equal(t, "Mission Dolores Park", sent.Body)
	stored := w.get(t, res.EventID)
	store.ExtractEventMedia(&stored, w.m, false)
	require.Equal(t, "geo:37.7749,-122.4194", stored.GeoURI)

	// Tiny coordinates near 0 must format in fixed decimal notation (never scientific notation like 1e-07).
	resTiny, err := w.a.SendLocation(ctx, room, 1e-7, -2e-7, "Equator Origin", "")
	require.NoError(t, err)
	recv(t, w.n.Files, "the tiny-coord location message")
	storedTiny := w.get(t, resTiny.EventID)
	store.ExtractEventMedia(&storedTiny, w.m, false)
	require.Equal(t, "geo:0.0000001,-0.0000002", storedTiny.GeoURI)

	// Unsupported room rejects location sending with ErrNotSupported.
	locRejected := &event.RoomFeatures{
		LocationMessage: event.CapLevelRejected,
	}
	wNo, roomNo := startFeatureWorld(t, locRejected)
	_, err = wNo.a.SendLocation(ctx, roomNo, 37.7749, -122.4194, "Nowhere", "")
	require.ErrorIs(t, err, ErrNotSupported)
}

func TestSendMessageSuppressesLinkPreviewByDefaultAndFetchesOnlyWhenEnabled(t *testing.T) {
	ctx := context.Background()
	var hits atomic.Int32
	var srvURL string
	srv := httptest.NewTLSServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		if r.URL.Path == "/og.png" {
			rw.Header().Set("Content-Type", "image/png")
			img := image.NewRGBA(image.Rect(0, 0, 16, 12))
			for y := 0; y < 12; y++ {
				for x := 0; x < 16; x++ {
					img.Set(x, y, color.RGBA{R: 40, G: 120, B: 200, A: 255})
				}
			}
			_ = png.Encode(rw, img)
			return
		}
		rw.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = fmt.Fprintf(rw, `<!doctype html><html><head>
			<meta property="og:title" content="Courier Media Plan">
			<meta property="og:description" content="Local-first rich media">
			<meta property="og:site_name" content="Vitruvian">
			<meta property="og:url" content="%s/article">
			<meta property="og:image" content="%s/og.png">
		</head><body>Hello</body></html>`, srvURL, srvURL)
	}))
	defer srv.Close()
	srvURL = srv.URL

	w, room := startFeatureWorld(t, whatsappFeatures())
	w.a.SetLinkPreviewHTTPClient(srv.Client())

	// Default (DisableLinkPreview == nil): zero outbound requests, and com.beeper.linkpreviews is [].
	idDefault, err := w.a.Send(ctx, room, "Read "+srv.URL+"/article", SendOptions{})
	require.NoError(t, err)
	recv(t, w.n.Sent, "default message")
	require.Equal(t, int32(0), hits.Load(), "must not fetch link preview when DisableLinkPreview is nil")
	rawDefault := content(t, w.get(t, idDefault))
	lpDefault, hasLPKey := rawDefault["com.beeper.linkpreviews"]
	require.True(t, hasLPKey, "outgoing URL message must carry com.beeper.linkpreviews: [] when suppressed")
	require.Empty(t, lpDefault)

	// Explicit DisableLinkPreview == true: also zero requests and com.beeper.linkpreviews: [].
	tr := true
	idTrue, err := w.a.Send(ctx, room, "Read "+srv.URL+"/article", SendOptions{DisableLinkPreview: &tr})
	require.NoError(t, err)
	recv(t, w.n.Sent, "explicit disabled message")
	require.Equal(t, int32(0), hits.Load(), "must not fetch link preview when DisableLinkPreview is true")
	rawTrue := content(t, w.get(t, idTrue))
	_, hasLPKeyTrue := rawTrue["com.beeper.linkpreviews"]
	require.True(t, hasLPKeyTrue)

	// Explicit DisableLinkPreview == false: fetches the first https URL and og:image into media.Store.
	fa := false
	idEnabled, err := w.a.Send(ctx, room, "Read "+srv.URL+"/article", SendOptions{DisableLinkPreview: &fa})
	require.NoError(t, err)
	recv(t, w.n.Sent, "enabled preview message")
	require.GreaterOrEqual(t, hits.Load(), int32(2), "must fetch HTML and og:image when DisableLinkPreview is false")
	stored := w.get(t, idEnabled)
	store.ExtractEventMedia(&stored, w.m, false)
	require.Len(t, stored.LinkPreviews, 1)
	require.Equal(t, "Courier Media Plan", stored.LinkPreviews[0].Title)
	require.Equal(t, "Local-first rich media", stored.LinkPreviews[0].Description)
	require.Equal(t, "Vitruvian", stored.LinkPreviews[0].SiteName)
	require.NotEmpty(t, stored.LinkPreviews[0].ImagePath)
	require.Equal(t, 16, stored.LinkPreviews[0].ImageWidth)
	require.Equal(t, 12, stored.LinkPreviews[0].ImageHeight)
	require.NotEmpty(t, stored.LinkPreviews[0].BlurHash)
}

func TestSendFileStreamsFromDiskAndUsesPerKindMaxSize(t *testing.T) {
	ctx := context.Background()
	caps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.MsgImage: {
				MimeTypes: map[string]event.CapabilitySupportLevel{"image/png": event.CapLevelFullySupported},
				MaxSize:   4096, // 4 KiB cap for images
			},
			event.MsgFile: {
				MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported},
				MaxSize:   128 * 1024, // 128 KiB cap for general files
			},
		},
	}
	w, room := startFeatureWorld(t, caps)
	// Inject a tiny in-memory read limit (1 KiB) on media.Store so any full-file in-memory read fails.
	w.m.MaxMemoryBytes = 1024

	tmpDir := t.TempDir()
	// 1. An 8 KiB PNG exceeds MsgImage's 4 KiB MaxSize and must be refused with ErrTooLarge.
	bigImgPath := filepath.Join(tmpDir, "big.png")
	pngPayload := append([]byte("\x89PNG\r\n\x1a\n"), bytes.Repeat([]byte("A"), 8192)...)
	require.NoError(t, os.WriteFile(bigImgPath, pngPayload, 0o600))
	_, err := w.a.SendFileWith(ctx, room, bigImgPath, SendOptions{})
	require.ErrorIs(t, err, ErrTooLarge)

	// 2. A 64 KiB binary file fits within MsgFile's 128 KiB MaxSize and is 64x larger than MaxMemoryBytes (1 KiB).
	// Both SendFileWith and localmatrix's DownloadMediaToFile must stream it from disk without reading into memory.
	streamPath := filepath.Join(tmpDir, "archive.bin")
	streamPayload := bytes.Repeat([]byte("0123456789abcdef"), 4096) // 64 KiB
	require.NoError(t, os.WriteFile(streamPath, streamPayload, 0o600))
	evtID, err := w.a.SendFileWith(ctx, room, streamPath, SendOptions{})
	require.NoError(t, err)
	sentFile := recv(t, w.n.Files, "streamed binary file")
	require.Equal(t, len(streamPayload), sentFile.Size)
	require.NotEmpty(t, evtID)

	h, ok := w.eng.Host("whatsapp")
	require.True(t, ok)
	var streamedSize int64
	err = h.Bridge.Bot.DownloadMediaToFile(ctx, id.ContentURIString(sentFile.URL), nil, false, func(f *os.File) error {
		fi, serr := f.Stat()
		if serr != nil {
			return serr
		}
		streamedSize = fi.Size()
		return nil
	})
	require.NoError(t, err)
	require.EqualValues(t, len(streamPayload), streamedSize)

	// 3. Per-kind MaxSize larger than 2 GiB (e.g. Telegram Premium 4 GiB) is clamped to the 2 GiB ceiling on Telegram,
	// while non-streaming bridges (WhatsApp, Signal, Google Messages, Slack) are clamped to the 100 MiB in-memory ceiling.
	feats4GiB := Features{FileFeatures: &FileKindFeatures{Supported: true, MaxSize: 4 * 1024 * 1024 * 1024}}
	require.EqualValues(t, MaxFileCeiling, w.a.maxSizeForKind(feats4GiB, event.MsgFile, "application/octet-stream"))

	// 4. A 150 MiB file to a WhatsApp fake (whose bridge advertises 2000 MiB on MsgFile but uses DownloadMedia []byte)
	// is refused with ErrTooLarge before reading its contents, and Features caps FileFeatures.MaxSize at 100 MiB.
	waLargeCaps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.MsgFile: {
				MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported},
				MaxSize:   2000 * 1024 * 1024,
			},
		},
	}
	wWA, roomWA := startFeatureWorld(t, waLargeCaps)
	waFeats, err := wWA.a.Features(ctx, roomWA)
	require.NoError(t, err)
	require.NotNil(t, waFeats.FileFeatures)
	require.EqualValues(t, MaxInMemoryFileCeiling, waFeats.FileFeatures.MaxSize, "non-streaming bridge MaxSize must be capped at 100 MiB")

	bigWAPath := filepath.Join(tmpDir, "huge-150mb.bin")
	bigWAFile, err := os.Create(bigWAPath)
	require.NoError(t, err)
	require.NoError(t, bigWAFile.Truncate(150*1024*1024))
	require.NoError(t, bigWAFile.Close())
	_, err = wWA.a.SendFileWith(ctx, roomWA, bigWAPath, SendOptions{})
	require.ErrorIs(t, err, ErrTooLarge, "150 MiB file to WhatsApp must be refused before reading")
}

type fakeExecFileInfo struct {
	os.FileInfo
	name string
}

func (f fakeExecFileInfo) Name() string       { return f.name }
func (f fakeExecFileInfo) Size() int64        { return 1024 }
func (f fakeExecFileInfo) Mode() os.FileMode  { return 0o755 }
func (f fakeExecFileInfo) ModTime() time.Time { return time.Time{} }
func (f fakeExecFileInfo) IsDir() bool        { return false }
func (f fakeExecFileInfo) Sys() any           { return nil }

func TestConfigureFFmpegProbesHomebrewUsrLocalAndMacPortsPaths(t *testing.T) {
	noLookPath := func(string) (string, error) { return "", errors.New("not in PATH") }

	// When /opt/homebrew/bin is absent and /usr/local/bin/ffmpeg exists, ConfigureFFmpeg selects /usr/local/bin/ffmpeg.
	statUsrLocal := func(p string) (os.FileInfo, error) {
		if p == "/usr/local/bin/ffmpeg" || p == "/usr/local/bin/ffprobe" {
			return fakeExecFileInfo{name: filepath.Base(p)}, nil
		}
		return nil, os.ErrNotExist
	}
	ffBin, fpBin := ConfigureFFmpeg(statUsrLocal, noLookPath)
	require.Equal(t, "/usr/local/bin/ffmpeg", ffBin)
	require.Equal(t, "/usr/local/bin/ffprobe", fpBin)

	// When /opt/homebrew/bin/ffmpeg exists, it takes precedence.
	statHomebrew := func(p string) (os.FileInfo, error) {
		if p == "/opt/homebrew/bin/ffmpeg" || p == "/opt/homebrew/bin/ffprobe" {
			return fakeExecFileInfo{name: filepath.Base(p)}, nil
		}
		return nil, os.ErrNotExist
	}
	ffBin, fpBin = ConfigureFFmpeg(statHomebrew, noLookPath)
	require.Equal(t, "/opt/homebrew/bin/ffmpeg", ffBin)
	require.Equal(t, "/opt/homebrew/bin/ffprobe", fpBin)
}

func TestLinkPreviewGuardRefusesTailnetLinkLocalULAAndHTTPDowngradeRedirect(t *testing.T) {
	ctx := context.Background()
	var targetHits atomic.Int32
	targetSrv := httptest.NewTLSServer(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		targetHits.Add(1)
		rw.Header().Set("Content-Type", "text/html")
		_, _ = rw.Write([]byte(`<meta property="og:title" content="Secret Internal">`))
	}))
	defer targetSrv.Close()

	w, room := startFeatureWorld(t, whatsappFeatures())
	fa := false

	for _, blockedIP := range []string{
		"100.64.0.1",  // CGNAT / Tailscale tailnet (100.64.0.0/10)
		"169.254.1.1", // IPv4 link-local
		"fe80::1",     // IPv6 link-local
		"fc00::1",     // IPv6 ULA
	} {
		w.a.SetLinkPreviewResolver(func(_ context.Context, _ string) ([]net.IPAddr, error) {
			return []net.IPAddr{{IP: net.ParseIP(blockedIP)}}, nil
		})
		id, err := w.a.Send(ctx, room, "Check https://internal.example.com/page", SendOptions{DisableLinkPreview: &fa})
		require.NoError(t, err)
		recv(t, w.n.Sent, "message with blocked IP "+blockedIP)
		stored := w.get(t, id)
		store.ExtractEventMedia(&stored, w.m, false)
		require.Empty(t, stored.LinkPreviews, "link preview must be refused for non-public IP %s", blockedIP)
	}
	require.Equal(t, int32(0), targetHits.Load())

	// Also verify isNonPublicIP directly rejects all private/special ranges and allows public IPs.
	for _, bad := range []string{"127.0.0.1", "10.0.0.1", "100.64.0.1", "100.127.255.254", "169.254.1.1", "192.168.1.1", "fe80::1", "fc00::1", "fd12:3456::1", "::1"} {
		require.True(t, isPrivateOrLoopbackIP(net.ParseIP(bad)), "must reject %s", bad)
	}
	require.False(t, isPrivateOrLoopbackIP(net.ParseIP("93.184.216.34")))

	// Verify an https -> http downgrade redirect is refused by the production client's CheckRedirect.
	prodClient := w.a.getLinkPreviewClient()
	require.NotNil(t, prodClient.CheckRedirect, "production link preview client must set CheckRedirect")
	httpReq, err := http.NewRequest(http.MethodGet, "http://example.com/downgraded", nil)
	require.NoError(t, err)
	httpsReq, err := http.NewRequest(http.MethodGet, "https://example.com/start", nil)
	require.NoError(t, err)
	require.Error(t, prodClient.CheckRedirect(httpReq, []*http.Request{httpsReq}), "https -> http redirect must be refused")
}

func TestSendStickerAndGIF(t *testing.T) {
	ctx := context.Background()
	tmpDir := t.TempDir()

	// Create a 24x18 PNG sticker file on disk.
	stickerPNGPath := filepath.Join(tmpDir, "party-parrot.png")
	img := image.NewRGBA(image.Rect(0, 0, 24, 18))
	for y := 0; y < 18; y++ {
		for x := 0; x < 24; x++ {
			img.Set(x, y, color.RGBA{R: 220, G: 80, B: 140, A: 255})
		}
	}
	var pngBuf bytes.Buffer
	require.NoError(t, png.Encode(&pngBuf, img))
	require.NoError(t, os.WriteFile(stickerPNGPath, pngBuf.Bytes(), 0o600))

	// Create a GIF and an MP4 file on disk.
	gifPath := filepath.Join(tmpDir, "thumbs-up.gif")
	gifBytes := []byte("GIF89a\x10\x00\x0c\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x10\x00\x0c\x00\x00\x02\x02D\x01\x00;")
	require.NoError(t, os.WriteFile(gifPath, gifBytes, 0o600))

	mp4Path := filepath.Join(tmpDir, "dance.mp4")
	mp4Bytes := []byte("\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom")
	require.NoError(t, os.WriteFile(mp4Path, mp4Bytes, 0o600))

	stickerAndGIFCaps := &event.RoomFeatures{
		Reply:  event.CapLevelFullySupported,
		Thread: event.CapLevelFullySupported,
		File: event.FileFeatureMap{
			event.CapMsgSticker: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/webp": event.CapLevelFullySupported,
					"image/png":  event.CapLevelFullySupported,
				},
				MaxSize: 1024 * 1024,
			},
			event.CapMsgGIF: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif": event.CapLevelFullySupported,
					"video/mp4": event.CapLevelFullySupported,
				},
				Caption: event.CapLevelFullySupported,
				MaxSize: 16 * 1024 * 1024,
			},
			event.MsgImage: {
				MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported},
				MaxSize:   16 * 1024 * 1024,
			},
			event.MsgVideo: {
				MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported},
				MaxSize:   16 * 1024 * 1024,
			},
		},
	}
	w, room := startFeatureWorld(t, stickerAndGIFCaps)

	// 1. SendSticker from local .png path with BridgedSticker metadata.
	resSticker, err := w.a.SendSticker(ctx, SendStickerReq{
		RoomID: room,
		Path:   stickerPNGPath,
		Name:   "Party Parrot",
		Emoji:  "🦜",
		BridgedSticker: &BridgedStickerRef{
			Network: "signal",
			PackURL: "https://signal.art/addstickers/#pack_id=aa&pack_key=bb",
			ID:      "7",
		},
	})
	require.NoError(t, err)
	require.NotEmpty(t, resSticker.EventID)
	sentFile := recv(t, w.n.Files, "sent sticker from path")
	require.Equal(t, event.CapMsgSticker, sentFile.MsgType)
	require.Equal(t, "Party Parrot", sentFile.Body)
	require.Equal(t, "image/png", sentFile.MimeType)
	require.Equal(t, 24, sentFile.Width)
	require.Equal(t, 18, sentFile.Height)
	require.Equal(t, len(pngBuf.Bytes()), sentFile.Size)

	storedSticker := w.get(t, resSticker.EventID)
	require.Equal(t, event.EventSticker.Type, storedSticker.Type)
	rawSticker := content(t, storedSticker)
	require.Equal(t, "m.image", rawSticker["msgtype"])
	infoMap, ok := rawSticker["info"].(map[string]any)
	require.True(t, ok)
	bsMap, ok := infoMap["fi.mau.bridged_sticker"].(map[string]any)
	require.True(t, ok)
	require.Equal(t, "7", bsMap["id"])

	// 2. SendSticker from existing courier://media/<hash> URL.
	preHash, err := w.m.Put(pngBuf.Bytes())
	require.NoError(t, err)
	resFromURL, err := w.a.SendSticker(ctx, SendStickerReq{
		RoomID:   room,
		MediaURL: "courier://media/" + preHash,
		Emoji:    "🎉",
	})
	require.NoError(t, err)
	require.NotEmpty(t, resFromURL.EventID)
	sentFromURL := recv(t, w.n.Files, "sent sticker from courier://media URL")
	require.Equal(t, event.CapMsgSticker, sentFromURL.MsgType)
	require.Equal(t, "🎉", sentFromURL.Body)
	require.Equal(t, string(ids.ContentURI(preHash)), sentFromURL.URL)

	// 3. SendSticker returns ErrUnsupportedFeature when room does not support CapMsgSticker (e.g. Slack / Google Messages).
	wNoSticker, roomNoSticker := startFeatureWorld(t, slackFeatures())
	_, err = wNoSticker.a.SendSticker(ctx, SendStickerReq{
		RoomID: roomNoSticker,
		Path:   stickerPNGPath,
	})
	require.ErrorIs(t, err, ErrUnsupportedFeature)
	require.ErrorIs(t, err, ErrNotSupported)

	// 4. SendGIF from .gif path (MsgImage, fi.mau.gif: true) and .mp4 path (MsgVideo, fi.mau.gif: true) with caption.
	resGIF, err := w.a.SendGIF(ctx, SendGIFReq{
		RoomID:  room,
		Path:    gifPath,
		Caption: "Great job!",
	})
	require.NoError(t, err)
	sentGIF := recv(t, w.n.Files, "sent .gif")
	require.Equal(t, event.MsgImage, sentGIF.MsgType)
	require.Equal(t, "Great job!", sentGIF.Body)
	require.Equal(t, "thumbs-up.gif", sentGIF.FileName)
	storedGIF := w.get(t, resGIF.EventID)
	require.Equal(t, event.EventMessage.Type, storedGIF.Type)
	rawGIF := content(t, storedGIF)
	gifInfo, ok := rawGIF["info"].(map[string]any)
	require.True(t, ok)
	require.Equal(t, true, gifInfo["fi.mau.gif"])

	resMP4GIF, err := w.a.SendGIF(ctx, SendGIFReq{
		RoomID: room,
		Path:   mp4Path,
	})
	require.NoError(t, err)
	sentMP4GIF := recv(t, w.n.Files, "sent .mp4 gif")
	require.Equal(t, event.MsgVideo, sentMP4GIF.MsgType)
	require.Equal(t, "dance.mp4", sentMP4GIF.Body)
	rawMP4 := content(t, w.get(t, resMP4GIF.EventID))
	mp4Info, ok := rawMP4["info"].(map[string]any)
	require.True(t, ok)
	require.Equal(t, true, mp4Info["fi.mau.gif"])

	// 5. HoldMillis > 0 holds in outbox, Undo cancels cleanly, and Retry re-dispatches EventSticker / EventMessage.
	heldSticker, err := w.a.SendSticker(ctx, SendStickerReq{
		RoomID:     room,
		Path:       stickerPNGPath,
		HoldMillis: 5000,
	})
	require.NoError(t, err)
	require.Equal(t, "queued", w.get(t, heldSticker.EventID).Status)
	_, err = w.a.Undo(ctx, heldSticker.EventID)
	require.NoError(t, err)

	heldGIF, err := w.a.SendGIF(ctx, SendGIFReq{
		RoomID:     room,
		Path:       gifPath,
		Caption:    "Hold me",
		HoldMillis: 5000,
	})
	require.NoError(t, err)
	require.Equal(t, "queued", w.get(t, heldGIF.EventID).Status)
	undoneGIF, err := w.a.Undo(ctx, heldGIF.EventID)
	require.NoError(t, err)
	src, hasSrc := SourceOf(undoneGIF.Content)
	require.True(t, hasSrc)
	require.Equal(t, "Hold me", src.Text)

	// Retry failed sticker re-dispatches EventSticker.
	w.n.FailWith(errors.New("temporary failure"))
	failedSticker, err := w.a.SendSticker(ctx, SendStickerReq{
		RoomID: room,
		Path:   stickerPNGPath,
		Name:   "Retry Parrot",
	})
	require.NoError(t, err)
	w.waitStatus(t, failedSticker.EventID, "failed")
	w.n.FailWith(nil)
	require.NoError(t, w.a.Retry(ctx, failedSticker.EventID))
	retriedFile := recv(t, w.n.Files, "retried sticker")
	require.Equal(t, event.CapMsgSticker, retriedFile.MsgType)
	w.waitStatus(t, failedSticker.EventID, "sent")
}

func countMediaBlobs(t *testing.T, dir string) int {
	t.Helper()
	count := 0
	_ = filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil || d == nil || d.IsDir() {
			return nil
		}
		if filepath.Base(path) == "stickers.json" || strings.HasPrefix(filepath.Base(path), ".upload-") {
			return nil
		}
		count++
		return nil
	})
	return count
}

func TestSendGIFMP4UsesVideoWithMauGIFFlag(t *testing.T) {
	ctx := context.Background()
	tmpDir := t.TempDir()

	mp4Path := filepath.Join(tmpDir, "loop.mp4")
	mp4Bytes := []byte("\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom")
	require.NoError(t, os.WriteFile(mp4Path, mp4Bytes, 0o600))

	// Room whose GIF capability allows both image/gif and video/mp4.
	bothCaps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgGIF: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif": event.CapLevelFullySupported,
					"video/mp4": event.CapLevelFullySupported,
				},
				Caption: event.CapLevelFullySupported,
				MaxSize: 16 * 1024 * 1024,
			},
			event.MsgImage: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif": event.CapLevelFullySupported,
				},
				MaxSize: 16 * 1024 * 1024,
			},
			event.MsgVideo: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"video/mp4": event.CapLevelFullySupported,
				},
				MaxSize: 16 * 1024 * 1024,
			},
		},
	}
	w, room := startFeatureWorld(t, bothCaps)
	res, err := w.a.SendGIF(ctx, SendGIFReq{
		RoomID: room,
		Path:   mp4Path,
	})
	require.NoError(t, err)
	sent := recv(t, w.n.Files, "sent mp4 gif")
	require.Equal(t, event.MsgVideo, sent.MsgType)
	raw := content(t, w.get(t, res.EventID))
	infoMap, ok := raw["info"].(map[string]any)
	require.True(t, ok)
	require.Equal(t, true, infoMap["fi.mau.gif"])

	// Room whose GIF capability allows ONLY image/gif (like Google Messages or Slack) must refuse video/mp4
	// with ErrUnsupportedFeature and leave nothing in media.Store.
	gifOnlyCaps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgGIF: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif": event.CapLevelFullySupported,
				},
				MaxSize: 16 * 1024 * 1024,
			},
			event.MsgImage: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif": event.CapLevelFullySupported,
				},
				MaxSize: 16 * 1024 * 1024,
			},
		},
	}
	wGifOnly, roomGifOnly := startFeatureWorld(t, gifOnlyCaps)
	blobsBefore := countMediaBlobs(t, wGifOnly.m.Dir)
	_, err = wGifOnly.a.SendGIF(ctx, SendGIFReq{
		RoomID: roomGifOnly,
		Path:   mp4Path,
	})
	require.ErrorIs(t, err, ErrUnsupportedFeature)
	require.Equal(t, blobsBefore, countMediaBlobs(t, wGifOnly.m.Dir), "refused SendGIF must not store blob")

	// Sending a non-GIF/non-MP4 file (e.g. PNG) to SendGIF is always refused, even when CapMsgGIF has */*.
	pngPath := filepath.Join(tmpDir, "still.png")
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	var pngBuf bytes.Buffer
	require.NoError(t, png.Encode(&pngBuf, img))
	require.NoError(t, os.WriteFile(pngPath, pngBuf.Bytes(), 0o600))

	wildcardCaps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgGIF: {
				MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported},
				MaxSize:   16 * 1024 * 1024,
			},
			event.MsgImage: {
				MimeTypes: map[string]event.CapabilitySupportLevel{"*/*": event.CapLevelFullySupported},
				MaxSize:   16 * 1024 * 1024,
			},
		},
	}
	wWild, roomWild := startFeatureWorld(t, wildcardCaps)
	blobsBeforeWild := countMediaBlobs(t, wWild.m.Dir)
	_, err = wWild.a.SendGIF(ctx, SendGIFReq{
		RoomID: roomWild,
		Path:   pngPath,
	})
	require.ErrorIs(t, err, ErrUnsupportedFeature)
	require.Equal(t, blobsBeforeWild, countMediaBlobs(t, wWild.m.Dir), "refused non-GIF must not store blob")
}

func TestSendGIFImageChecksImageCapabilityMaxSizeAndLeavesNoBlob(t *testing.T) {
	ctx := context.Background()
	tmpDir := t.TempDir()

	// Telegram-like capabilities: MsgImage has MaxSize 10 MiB, while CapMsgGIF has MaxSize 50 MiB.
	// Because bridgev2's GetCapMsgType maps MsgImage to m.image (only MsgVideo+MauGIF maps to fi.mau.gif),
	// an 11 MiB image/gif sent as MsgImage must be checked against MsgImage's 10 MiB limit and refused.
	tgLikeCaps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.MsgImage: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif":  event.CapLevelPartialSupport,
					"image/png":  event.CapLevelFullySupported,
					"image/webp": event.CapLevelPartialSupport,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: 1024,
				MaxSize:          10 * 1024 * 1024,
			},
			event.CapMsgGIF: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/gif": event.CapLevelFullySupported,
					"video/mp4": event.CapLevelFullySupported,
				},
				Caption:          event.CapLevelFullySupported,
				MaxCaptionLength: 1024,
				MaxSize:          50 * 1024 * 1024,
			},
			event.CapMsgSticker: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/webp": event.CapLevelFullySupported,
				},
				MaxSize: 512 * 1024,
			},
		},
	}
	w, room := startFeatureWorld(t, tgLikeCaps)

	bigGIFPath := filepath.Join(tmpDir, "eleven-mib.gif")
	gifHeader := []byte("GIF89a\x02\x00\x02\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x02\x00\x02\x00\x00\x02\x02D\x01\x00;")
	bigGIF := make([]byte, 11*1024*1024)
	copy(bigGIF, gifHeader)
	require.NoError(t, os.WriteFile(bigGIFPath, bigGIF, 0o600))

	blobsBefore := countMediaBlobs(t, w.m.Dir)
	_, err := w.a.SendGIF(ctx, SendGIFReq{
		RoomID: room,
		Path:   bigGIFPath,
	})
	require.ErrorIs(t, err, ErrTooLarge)
	require.Equal(t, blobsBefore, countMediaBlobs(t, w.m.Dir), "refused 11 MiB image/gif must not write to media.Store")

	// Also verify a refused SendSticker (MIME disallowed by room's CapMsgSticker) writes nothing to media.Store.
	pngPath := filepath.Join(tmpDir, "disallowed.png")
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	var pngBuf bytes.Buffer
	require.NoError(t, png.Encode(&pngBuf, img))
	require.NoError(t, os.WriteFile(pngPath, pngBuf.Bytes(), 0o600))

	blobsBeforeSticker := countMediaBlobs(t, w.m.Dir)
	_, err = w.a.SendSticker(ctx, SendStickerReq{
		RoomID: room,
		Path:   pngPath,
	})
	require.ErrorIs(t, err, ErrUnsupportedFeature)
	require.Equal(t, blobsBeforeSticker, countMediaBlobs(t, w.m.Dir), "refused SendSticker must not write to media.Store")

	// A 25 MiB PNG sent as a sticker to a 512 KiB WebP-only room must be refused before image decoding/blurhashing runs.
	bigPNGPath := filepath.Join(tmpDir, "twentyfive-mib.png")
	bigPNG := make([]byte, 25*1024*1024)
	copy(bigPNG, pngBuf.Bytes())
	require.NoError(t, os.WriteFile(bigPNGPath, bigPNG, 0o600))

	inspectCalls := 0
	origInspect := inspectImageHook
	inspectImageHook = func(r io.Reader) (media.Metadata, error) {
		inspectCalls++
		return origInspect(r)
	}
	defer func() { inspectImageHook = origInspect }()

	_, err = w.a.SendSticker(ctx, SendStickerReq{
		RoomID: room,
		Path:   bigPNGPath,
	})
	require.Error(t, err)
	require.Zero(t, inspectCalls, "refused 25 MiB PNG sticker must not decode/blurhash image")
}

func TestSendStickerWithoutBridgedStickerPreservesEmojiInStoredEvent(t *testing.T) {
	ctx := context.Background()
	tmpDir := t.TempDir()

	caps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgSticker: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/png": event.CapLevelFullySupported,
				},
				MaxSize: 512 * 1024,
			},
		},
	}
	w, room := startFeatureWorld(t, caps)

	pngPath := filepath.Join(tmpDir, "local-sticker.png")
	img := image.NewRGBA(image.Rect(0, 0, 16, 16))
	var pngBuf bytes.Buffer
	require.NoError(t, png.Encode(&pngBuf, img))
	require.NoError(t, os.WriteFile(pngPath, pngBuf.Bytes(), 0o600))

	res, err := w.a.SendSticker(ctx, SendStickerReq{
		RoomID: room,
		Path:   pngPath,
		Name:   "Party Parrot",
		Emoji:  "🦜",
	})
	require.NoError(t, err)

	stored := w.get(t, res.EventID)

	var content struct {
		Body string `json:"body"`
		URL  string `json:"url"`
		Info struct {
			BridgedSticker *struct {
				Network string `json:"network"`
				ID      string `json:"id"`
				Emoji   string `json:"emoji"`
				PackURL string `json:"pack_url"`
			} `json:"fi.mau.bridged_sticker"`
		} `json:"info"`
	}
	require.NoError(t, json.Unmarshal([]byte(stored.Content), &content))
	require.Equal(t, "Party Parrot", content.Body)
	require.NotNil(t, content.Info.BridgedSticker, "non-bridged sticker with emoji must persist emoji in info.fi.mau.bridged_sticker")
	require.Equal(t, "🦜", content.Info.BridgedSticker.Emoji)
	require.Empty(t, content.Info.BridgedSticker.Network)
	require.Empty(t, content.Info.BridgedSticker.ID)
	require.Empty(t, content.Info.BridgedSticker.PackURL)
}

func TestSendStickerRejectsSpoofedMimeTypeAndLeavesNoBlob(t *testing.T) {
	ctx := context.Background()
	tmpDir := t.TempDir()

	caps := &event.RoomFeatures{
		File: event.FileFeatureMap{
			event.CapMsgSticker: {
				MimeTypes: map[string]event.CapabilitySupportLevel{
					"image/webp": event.CapLevelFullySupported,
				},
				MaxSize: 512 * 1024,
			},
		},
	}
	w, webpOnlyRoom := startFeatureWorld(t, caps)

	jpgPath := filepath.Join(tmpDir, "spoofed.webp")
	img := image.NewRGBA(image.Rect(0, 0, 16, 16))
	var jpgBuf bytes.Buffer
	require.NoError(t, jpeg.Encode(&jpgBuf, img, nil))
	require.NoError(t, os.WriteFile(jpgPath, jpgBuf.Bytes(), 0o600))

	blobsBefore := countMediaBlobs(t, w.m.Dir)
	_, err := w.a.SendSticker(ctx, SendStickerReq{
		RoomID:   webpOnlyRoom,
		Path:     jpgPath,
		MimeType: "image/webp",
		Name:     "Spoofed JPEG",
	})
	require.ErrorIs(t, err, ErrUnsupportedFeature, "SendSticker must sniff actual file bytes rather than trusting client-supplied MimeType")
	require.Equal(t, blobsBefore, countMediaBlobs(t, w.m.Dir), "rejected spoofed sticker must leave no blob in media.Store")
}

