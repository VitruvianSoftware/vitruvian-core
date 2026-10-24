// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// world is an engine running the fake network under some network's name, over a real store.
type world struct {
	eng   *engine.Engine
	s     *store.Store
	m     *media.Store
	n     *fakenet.Network
	a     *Actions
	login *bridgev2.UserLogin // nil when the world is not linked
	dir   string              // the data directory: courier.db, the bridge's database and media
}

// startWorld runs the fake network as `name`. With linked, it has one login, whose client reports "logged in"
// only loginDelay after Connect, the way a real network does once the server's success message arrives.
func startWorld(t *testing.T, name string, linked bool, loginDelay ...time.Duration) world {
	t.Helper()
	n := fakenet.New()
	if len(loginDelay) > 0 {
		n.LoginDelay = loginDelay[0]
	}
	return startWorldOn(t, name, n, linked, zerolog.Nop())
}

// startWorldOn is startWorld over a fake network the test made, with the engine logging to log.
func startWorldOn(t *testing.T, name string, n *fakenet.Network, linked bool, log zerolog.Logger) world {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	m := &media.Store{Dir: filepath.Join(dir, "media")}
	eng, errs := engine.Start(ctx, dir, s, m,
		[]engine.Spec{{Name: name, Connector: func() (bridgev2.NetworkConnector, error) { return n, nil }}}, log)
	require.Empty(t, errs)
	t.Cleanup(eng.Stop)
	w := world{eng: eng, s: s, m: m, n: n, a: New(eng, s, m), dir: dir}
	if linked {
		h, ok := eng.Host(name)
		require.True(t, ok)
		w.login, err = n.Login(ctx, h.Bridge)
		require.NoError(t, err)
	}
	return w
}

// chat has the network deliver a message from a contact, which makes the bridge create a real room for it.
// It returns the room and the event ID of that message. Call it once per world.
func (w world) chat(t *testing.T, chatID, msgID string) (room, eventID string) {
	t.Helper()
	w.n.Incoming(w.login, chatID, "alice", msgID, "hi")
	return w.firstMessage(t, "")
}

// secondChat is chat for another contact: it returns the room that is not `not`.
func (w world) secondChat(t *testing.T, chatID, msgID, not string) (room, eventID string) {
	t.Helper()
	w.n.Incoming(w.login, chatID, "bob", msgID, "hello")
	return w.firstMessage(t, not)
}

// firstMessage waits for a room other than `not` to hold a message, and returns that room and message.
func (w world) firstMessage(t *testing.T, not string) (room, eventID string) {
	t.Helper()
	require.Eventually(t, func() bool {
		rooms, err := w.s.ListRooms(context.Background())
		if err != nil {
			return false
		}
		for _, r := range rooms {
			if r.ID == not {
				continue
			}
			evs, err := w.s.Events(context.Background(), r.ID, 10)
			if err != nil || len(evs) == 0 {
				continue
			}
			room, eventID = r.ID, evs[0].EventID
			return true
		}
		return false
	}, 5*time.Second, 20*time.Millisecond, "the bridge never stored the contact's message")
	return room, eventID
}

func (w world) get(t *testing.T, eventID string) store.Event {
	t.Helper()
	e, ok, err := w.s.GetEvent(context.Background(), eventID)
	require.NoError(t, err)
	require.True(t, ok, "event %s should exist", eventID)
	return e
}

func (w world) waitStatus(t *testing.T, eventID, want string) store.Event {
	t.Helper()
	var e store.Event
	require.Eventually(t, func() bool {
		var ok bool
		var err error
		e, ok, err = w.s.GetEvent(context.Background(), eventID)
		return err == nil && ok && e.Status == want
	}, 5*time.Second, 20*time.Millisecond, "event %s never became %s", eventID, want)
	return e
}

func (w world) unread(t *testing.T, room string) int {
	t.Helper()
	rows, err := w.s.Inbox(context.Background())
	require.NoError(t, err)
	for _, r := range rows {
		if r.ID == room {
			return r.Unread
		}
	}
	t.Fatalf("room %s not in the inbox", room)
	return 0
}

func recv[T any](t *testing.T, ch <-chan T, what string) T {
	t.Helper()
	select {
	case v := <-ch:
		return v
	case <-time.After(5 * time.Second):
		t.Fatalf("%s never reached the network", what)
	}
	var zero T
	return zero
}

func none[T any](t *testing.T, ch <-chan T, what string) {
	t.Helper()
	select {
	case v := <-ch:
		t.Fatalf("%s reached the network: %+v", what, v)
	case <-time.After(200 * time.Millisecond):
	}
}

func relatesTo(t *testing.T, e store.Event) map[string]any {
	t.Helper()
	var c struct {
		RelatesTo map[string]any `json:"m.relates_to"`
	}
	require.NoError(t, json.Unmarshal(e.Content, &c))
	return c.RelatesTo
}

func TestSendTextQueuesPendingThenSent(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	w.n.Hold = make(chan struct{}) // the network sits on the message until we let go

	type result struct {
		id  string
		err error
	}
	done := make(chan result, 1)
	go func() {
		id, err := w.a.SendText(ctx, room, "hello there", "")
		done <- result{id, err}
	}()

	var pending store.Event
	require.Eventually(t, func() bool {
		evs, err := w.s.Events(ctx, room, 1)
		if err != nil || len(evs) != 1 {
			return false
		}
		pending = evs[0]
		return pending.Sender == string(ids.Me)
	}, 5*time.Second, 20*time.Millisecond, "the message is never stored")
	require.Equal(t, "pending", pending.Status, "stored as pending before the network has it")
	require.Equal(t, event.EventMessage.Type, pending.Type)
	require.JSONEq(t, `{"msgtype":"m.text","body":"hello there"}`, string(pending.Content))
	none(t, w.n.Sent, "a held message")

	close(w.n.Hold)
	var r result
	select {
	case r = <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("SendText never returned")
	}
	require.NoError(t, r.err)
	require.Equal(t, pending.EventID, r.id, "SendText returns the ID of the stored row")
	got := recv(t, w.n.Sent, "the message")
	require.Equal(t, fakenet.Sent{PortalID: "chat1", Body: "hello there"}, got)
	w.waitStatus(t, r.id, "sent")
}

func TestReplyCarriesInReplyTo(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, target := w.chat(t, "chat1", "m1")

	id, err := w.a.SendText(ctx, room, "answering you", target)
	require.NoError(t, err)
	e := w.get(t, id)
	inReplyTo, _ := relatesTo(t, e)["m.in_reply_to"].(map[string]any)
	require.Equal(t, target, inReplyTo["event_id"], "the stored content points at the message it answers")
	got := recv(t, w.n.Sent, "the reply")
	require.Equal(t, fakenet.Sent{PortalID: "chat1", Body: "answering you", ReplyTo: "m1"}, got,
		"the bridge resolved the reply to the network's own message ID")

	t.Run("a target that does not exist is refused", func(t *testing.T) {
		_, err := w.a.SendText(ctx, room, "x", "$nope")
		require.ErrorContains(t, err, "$nope")
	})
	t.Run("a target in another chat is refused", func(t *testing.T) {
		_, otherEvt := w.secondChat(t, "chat2", "m2", room)
		_, err := w.a.SendText(ctx, room, "x", otherEvt)
		require.ErrorContains(t, err, "not in this chat")
	})
	// Neither refusal stored or sent anything.
	evs, err := w.s.Events(ctx, room, 50)
	require.NoError(t, err)
	require.Len(t, evs, 2, "the contact's message and the one reply")
	none(t, w.n.Sent, "a refused reply")
}

func TestReactReachesTheNetwork(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, target := w.chat(t, "chat1", "m1")

	id, err := w.a.React(ctx, room, target, "👍")
	require.NoError(t, err)
	require.Equal(t, fakenet.Reaction{PortalID: "chat1", TargetID: "m1", Emoji: "👍"}, recv(t, w.n.Reactions, "the reaction"))

	e := w.waitStatus(t, id, "sent") // bridgev2 reports a reaction's outcome the way it does a message's
	require.Equal(t, event.EventReaction.Type, e.Type)
	require.Equal(t, string(ids.Me), e.Sender)
	rel := relatesTo(t, e)
	require.Equal(t, "m.annotation", rel["rel_type"])
	require.Equal(t, target, rel["event_id"])
	require.Equal(t, "👍", rel["key"])

	t.Run("a reaction the bridge cannot place ends up failed", func(t *testing.T) {
		// An event the store has but the bridge never bridged.
		stray := ids.RandomEventID()
		_, err := w.s.InsertEvent(ctx, store.Event{
			RoomID: room, EventID: string(stray), Sender: "@alice:courier.local", Type: event.EventMessage.Type,
			Content: json.RawMessage(`{"msgtype":"m.text","body":"x"}`), TS: time.Now(), Status: "sent",
		})
		require.NoError(t, err)
		id, err := w.a.React(ctx, room, string(stray), "❤️")
		require.NoError(t, err)
		e := w.waitStatus(t, id, "failed")
		require.NotEmpty(t, e.StatusReason)
	})
	t.Run("the target must be in this chat, and the key must not be empty", func(t *testing.T) {
		_, err := w.a.React(ctx, room, "$nope", "👍")
		require.ErrorContains(t, err, "$nope")
		_, err = w.a.React(ctx, room, target, "  ")
		require.Error(t, err)
	})
	none(t, w.n.Reactions, "a refused reaction")
}

func pngBytes(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	img.Set(0, 0, color.RGBA{R: 200, A: 255})
	var buf bytes.Buffer
	require.NoError(t, png.Encode(&buf, img))
	return buf.Bytes()
}

func writeFile(t *testing.T, name string, data []byte) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	require.NoError(t, os.WriteFile(p, data, 0o600))
	return p
}

func TestSendFileStoresMediaAndSendsMessage(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, target := w.chat(t, "chat1", "m1")

	t.Run("an image", func(t *testing.T) {
		data := pngBytes(t, 3, 2)
		id, err := w.a.SendFile(ctx, room, writeFile(t, "pic.png", data), "")
		require.NoError(t, err)
		f := recv(t, w.n.Files, "the image")
		require.Equal(t, event.MsgImage, f.MsgType)
		require.Equal(t, "pic.png", f.Body)
		require.Equal(t, "pic.png", f.FileName)
		require.Equal(t, "image/png", f.MimeType)
		require.Equal(t, len(data), f.Size)
		require.Equal(t, 3, f.Width)
		require.Equal(t, 2, f.Height)

		e := w.waitStatus(t, id, "sent")
		var c event.MessageEventContent
		require.NoError(t, json.Unmarshal(e.Content, &c))
		require.Equal(t, event.MsgImage, c.MsgType)
		require.Equal(t, f.URL, string(c.URL))
		hash, ok := ids.ParseContentURI(c.URL)
		require.True(t, ok, "the URL is one of our own")
		stored, err := w.m.Read(hash)
		require.NoError(t, err)
		require.Equal(t, data, stored, "the bytes are in the media store under their hash")
	})

	t.Run("anything else is a file, and it can be a reply", func(t *testing.T) {
		id, err := w.a.SendFile(ctx, room, writeFile(t, "notes.txt", []byte("some plain notes\n")), target)
		require.NoError(t, err)
		f := recv(t, w.n.Files, "the file")
		require.Equal(t, event.MsgFile, f.MsgType)
		require.Equal(t, "text/plain", f.MimeType, "the content type has no parameters")
		require.Zero(t, f.Width)
		require.Equal(t, "m1", f.ReplyTo)
		inReplyTo, _ := relatesTo(t, w.waitStatus(t, id, "sent"))["m.in_reply_to"].(map[string]any)
		require.Equal(t, target, inReplyTo["event_id"])
	})

	t.Run("a file that is not there, or not a file, is refused", func(t *testing.T) {
		_, err := w.a.SendFile(ctx, room, filepath.Join(t.TempDir(), "missing.png"), "")
		require.Error(t, err)
		_, err = w.a.SendFile(ctx, room, t.TempDir(), "")
		require.ErrorContains(t, err, "not a regular file")
	})
	none(t, w.n.Files, "a refused file")
}

func TestSendFileOverTheCapIsRefusedWithNothingStored(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")

	require.EqualValues(t, 90*1024*1024, MaxFileBytes)
	// A sparse file: one byte over the cap without writing 90 MB.
	big := filepath.Join(t.TempDir(), "big.bin")
	f, err := os.Create(big)
	require.NoError(t, err)
	require.NoError(t, f.Truncate(MaxFileBytes+1))
	require.NoError(t, f.Close())

	_, err = w.a.SendFile(ctx, room, big, "")
	require.ErrorIs(t, err, ErrTooLarge)
	require.NoDirExists(t, w.m.Dir, "nothing was read, so nothing was stored")
	evs, err := w.s.Events(ctx, room, 10)
	require.NoError(t, err)
	require.Len(t, evs, 1, "only the contact's message")
	none(t, w.n.Files, "a file over the cap")

	// The cap is inclusive: a file of exactly the cap is fine. Checked with a small cap, to keep the test small.
	w.a.maxFile = 10
	_, err = w.a.SendFile(ctx, room, writeFile(t, "ten.bin", bytes.Repeat([]byte{1}, 10)), "")
	require.NoError(t, err)
	recv(t, w.n.Files, "a file of exactly the cap")
	_, err = w.a.SendFile(ctx, room, writeFile(t, "eleven.bin", bytes.Repeat([]byte{1}, 11)), "")
	require.ErrorIs(t, err, ErrTooLarge)
}

func TestSendFileKinds(t *testing.T) {
	tests := []struct {
		name, sniffed, byExt string
		wantMime             string
		wantType             event.MessageType
	}{
		{"png by content", "image/png", "", "image/png", event.MsgImage},
		{"content wins over a wrong extension", "image/jpeg", "image/png", "image/jpeg", event.MsgImage},
		{"extension fills in when content says nothing", "application/octet-stream", "image/png", "image/png", event.MsgImage},
		{"text is a file", "text/plain; charset=utf-8", "", "text/plain", event.MsgFile},
		{"video by content", "video/mp4", "", "video/mp4", event.MsgVideo},
		{"an audio extension beats a video container", "video/mp4", "audio/mp4", "audio/mp4", event.MsgAudio},
		{"audio by content", "audio/mpeg", "", "audio/mpeg", event.MsgAudio},
		{"unknown is a file", "application/octet-stream", "", "application/octet-stream", event.MsgFile},
		{"a pdf is a file", "application/pdf", "", "application/pdf", event.MsgFile},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			mt, typ := pickType(tc.sniffed, tc.byExt)
			require.Equal(t, tc.wantMime, mt)
			require.Equal(t, tc.wantType, typ)
		})
	}

	t.Run("sniffing real bytes", func(t *testing.T) {
		mp4 := append([]byte{0, 0, 0, 0x18}, []byte("ftypmp42")...)
		mp4 = append(mp4, make([]byte, 16)...)
		mt, typ := detect(append([]byte(nil), mp4...), ".mp4")
		require.Equal(t, "video/mp4", mt)
		require.Equal(t, event.MsgVideo, typ)
		mt, typ = detect([]byte("ID3\x03\x00\x00\x00\x00\x00\x00"), ".mp3")
		require.Equal(t, "audio/mpeg", mt)
		require.Equal(t, event.MsgAudio, typ)
	})
}

func TestMarkReadSendsReceiptAndClearsUnread(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	require.Equal(t, 1, w.unread(t, room))

	require.NoError(t, w.a.MarkRead(ctx, room))
	require.Equal(t, fakenet.Receipt{PortalID: "chat1", MessageID: "m1"}, recv(t, w.n.Receipts, "the read receipt"),
		"the receipt names the newest message, as the network knows it")
	require.Equal(t, 0, w.unread(t, room), "the app's unread clears")

	// Again with nothing new: nothing to tell the network.
	require.NoError(t, w.a.MarkRead(ctx, room))
	none(t, w.n.Receipts, "a second receipt for the same message")

	// A new message from the contact is new news.
	w.n.Incoming(w.login, "chat1", "alice", "m2", "again")
	require.Eventually(t, func() bool { return w.unread(t, room) == 1 }, 5*time.Second, 20*time.Millisecond)
	require.NoError(t, w.a.MarkRead(ctx, room))
	require.Equal(t, "m2", recv(t, w.n.Receipts, "the receipt for the new message").MessageID)
	require.Equal(t, 0, w.unread(t, room))
	none(t, w.n.Receipts, "an extra receipt")

	t.Run("a reaction after the last message does not become the target", func(t *testing.T) {
		w := startWorld(t, "fake", true)
		room, target := w.chat(t, "chat1", "m1")
		_, err := w.a.React(ctx, room, target, "👍")
		require.NoError(t, err)
		recv(t, w.n.Reactions, "the reaction")
		w.waitStatus(t, w.lastEvent(t, room).EventID, "sent")
		require.Equal(t, event.EventReaction.Type, w.lastEvent(t, room).Type, "fixture: the newest event is the reaction")

		require.NoError(t, w.a.MarkRead(ctx, room))
		require.Equal(t, fakenet.Receipt{PortalID: "chat1", MessageID: "m1"}, recv(t, w.n.Receipts, "the read receipt"))
	})
	t.Run("an edit after the last message does not become the target", func(t *testing.T) {
		w := startWorld(t, "fake", true)
		room, target := w.chat(t, "chat1", "m1")
		edit := `{"msgtype":"m.text","body":"* edited","m.relates_to":{"rel_type":"m.replace","event_id":"` + target + `"}}`
		_, err := w.s.InsertEvent(ctx, store.Event{
			RoomID: room, EventID: "$edit", Sender: "@alice:courier.local", Type: event.EventMessage.Type,
			Content: json.RawMessage(edit), TS: time.Now().Add(time.Second), Status: "sent",
		})
		require.NoError(t, err)
		require.Equal(t, "$edit", w.lastEvent(t, room).EventID, "fixture: the newest event is the edit")

		require.NoError(t, w.a.MarkRead(ctx, room))
		require.Equal(t, fakenet.Receipt{PortalID: "chat1", MessageID: "m1"}, recv(t, w.n.Receipts, "the read receipt"))
	})
	t.Run("the unread count clears even if the network never hears of it", func(t *testing.T) {
		// A chat on a network that is not running: the receipt cannot go anywhere, but this device has read it.
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!tg:courier.local", Network: "telegram", Name: "Elsewhere"}))
		_, err := w.s.InsertEvent(ctx, store.Event{
			RoomID: "!tg:courier.local", EventID: "$tg1", Sender: "@alice:courier.local", Type: event.EventMessage.Type,
			Content: json.RawMessage(`{"msgtype":"m.text","body":"x"}`), TS: time.Now(), Status: "sent",
		})
		require.NoError(t, err)
		require.Equal(t, 1, w.unread(t, "!tg:courier.local"))
		err = w.a.MarkRead(ctx, "!tg:courier.local")
		require.ErrorContains(t, err, "not running")
		require.Equal(t, 0, w.unread(t, "!tg:courier.local"))
	})
	t.Run("a chat nobody has written in is not an error", func(t *testing.T) {
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!empty:courier.local", Network: "fake", Name: "Empty"}))
		require.NoError(t, w.a.MarkRead(ctx, "!empty:courier.local"))
	})
	t.Run("an unknown chat is an error", func(t *testing.T) {
		require.Error(t, w.a.MarkRead(ctx, "!nope:courier.local"))
	})
	none(t, w.n.Receipts, "a receipt nobody asked for")
}

func (w world) lastEvent(t *testing.T, room string) store.Event {
	t.Helper()
	evs, err := w.s.Events(context.Background(), room, 1)
	require.NoError(t, err)
	require.Len(t, evs, 1)
	return evs[0]
}

func TestReactTwiceSendsOnce(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, target := w.chat(t, "chat1", "m1")

	first, err := w.a.React(ctx, room, target, "👍")
	require.NoError(t, err)
	recv(t, w.n.Reactions, "the reaction")
	w.waitStatus(t, first, "sent")

	second, err := w.a.React(ctx, room, target, "👍")
	require.NoError(t, err)
	require.Equal(t, first, second, "the reaction I already have comes back")
	none(t, w.n.Reactions, "a repeated reaction")
	evs, err := w.s.Events(ctx, room, 10)
	require.NoError(t, err)
	require.Len(t, evs, 2, "the contact's message and one reaction")

	t.Run("another emoji, or another message, is another reaction", func(t *testing.T) {
		other, err := w.a.React(ctx, room, target, "❤️")
		require.NoError(t, err)
		require.NotEqual(t, first, other)
		require.Equal(t, "❤️", recv(t, w.n.Reactions, "the second emoji").Emoji)
	})
}

func TestReactConcurrentlySendsOnce(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, target := w.chat(t, "chat1", "m1")
	w.n.Hold = make(chan struct{}) // the first one sits in the network while the rest arrive

	const callers = 8
	type result struct {
		id  string
		err error
	}
	results := make(chan result, callers)
	for i := 0; i < callers; i++ {
		go func() {
			id, err := w.a.React(ctx, room, target, "👍")
			results <- result{id, err}
		}()
	}
	// All but the one in the network come back at once with its ID.
	var ids []string
	for i := 0; i < callers-1; i++ {
		select {
		case r := <-results:
			require.NoError(t, r.err)
			ids = append(ids, r.id)
		case <-time.After(5 * time.Second):
			t.Fatal("a repeated reaction waited for the first one to finish")
		}
	}
	close(w.n.Hold)
	select {
	case r := <-results:
		require.NoError(t, r.err)
		ids = append(ids, r.id)
	case <-time.After(5 * time.Second):
		t.Fatal("the first reaction never returned")
	}
	for _, id := range ids {
		require.Equal(t, ids[0], id, "every caller got the same reaction")
	}
	recv(t, w.n.Reactions, "the reaction")
	none(t, w.n.Reactions, "a second reaction")
	evs, err := w.s.Events(ctx, room, 20)
	require.NoError(t, err)
	require.Len(t, evs, 2, "the contact's message and one reaction")
}

func TestReactAgainAfterItFailed(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, target := w.chat(t, "chat1", "m1")

	w.n.FailWith(errors.New("no"))
	failed, err := w.a.React(ctx, room, target, "👍")
	require.NoError(t, err)
	w.waitStatus(t, failed, "failed")

	w.n.FailWith(nil)
	again, err := w.a.React(ctx, room, target, "👍")
	require.NoError(t, err)
	require.NotEqual(t, failed, again, "a failed reaction does not count: this is a new one")
	recv(t, w.n.Reactions, "the new reaction")
	w.waitStatus(t, again, "sent")

	t.Run("a discarded reaction can be sent again too", func(t *testing.T) {
		w.n.FailWith(errors.New("no"))
		doomed, err := w.a.React(ctx, room, target, "🎉")
		require.NoError(t, err)
		w.waitStatus(t, doomed, "failed")
		require.NoError(t, w.a.Discard(ctx, doomed))
		w.n.FailWith(nil)
		again, err := w.a.React(ctx, room, target, "🎉")
		require.NoError(t, err)
		require.NotEqual(t, doomed, again)
		recv(t, w.n.Reactions, "the reaction after the discard")
	})
}

func TestRetryRequeuesOnlyFailed(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")

	// A message the network refuses ends up failed.
	w.n.FailWith(errors.New("the network said no"))
	failedID, err := w.a.SendText(ctx, room, "try me again", "")
	require.NoError(t, err, "a refused delivery is a failed row, not an error from SendText")
	e := w.waitStatus(t, failedID, "failed")
	require.NotEmpty(t, e.StatusReason)
	none(t, w.n.Sent, "a message the network refused")

	// A message that went through cannot be retried.
	w.n.FailWith(nil)
	sentID, err := w.a.SendText(ctx, room, "fine the first time", "")
	require.NoError(t, err)
	w.waitStatus(t, sentID, "sent")
	recv(t, w.n.Sent, "the good message")
	require.ErrorIs(t, w.a.Retry(ctx, sentID), ErrNotFailed)

	// Nor one that is still pending.
	pendingID := string(ids.RandomEventID())
	_, err = w.s.InsertEvent(ctx, store.Event{
		RoomID: room, EventID: pendingID, Sender: string(ids.Me), Type: event.EventMessage.Type,
		Content: json.RawMessage(`{"msgtype":"m.text","body":"p"}`), TS: time.Now(), Status: "pending",
	})
	require.NoError(t, err)
	require.ErrorIs(t, w.a.Retry(ctx, pendingID), ErrNotFailed)
	require.Error(t, w.a.Retry(ctx, "$nope"), "an unknown message")
	none(t, w.n.Sent, "a message that was not failed")

	// The failed one goes out again, as the same message.
	require.NoError(t, w.a.Retry(ctx, failedID))
	require.Equal(t, fakenet.Sent{PortalID: "chat1", Body: "try me again"}, recv(t, w.n.Sent, "the retried message"))
	e = w.waitStatus(t, failedID, "sent")
	require.Empty(t, e.StatusReason, "the old failure reason is gone")
	require.ErrorIs(t, w.a.Retry(ctx, failedID), ErrNotFailed, "a second retry has nothing to do")
	none(t, w.n.Sent, "a second retry")
}

func TestRetryOfAFailedReaction(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, target := w.chat(t, "chat1", "m1")
	w.n.FailWith(errors.New("no"))
	id, err := w.a.React(ctx, room, target, "👍")
	require.NoError(t, err)
	w.waitStatus(t, id, "failed")

	w.n.FailWith(nil)
	require.NoError(t, w.a.Retry(ctx, id))
	require.Equal(t, "👍", recv(t, w.n.Reactions, "the retried reaction").Emoji)
	w.waitStatus(t, id, "sent")
}

func TestDiscardRemovesOnlyFailed(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")

	w.n.FailWith(errors.New("no"))
	failedID, err := w.a.SendText(ctx, room, "never mind", "")
	require.NoError(t, err)
	w.waitStatus(t, failedID, "failed")
	w.n.FailWith(nil)
	sentID, err := w.a.SendText(ctx, room, "this one went", "")
	require.NoError(t, err)
	w.waitStatus(t, sentID, "sent")

	require.ErrorIs(t, w.a.Discard(ctx, sentID), ErrNotFailed)
	_, ok, err := w.s.GetEvent(ctx, sentID)
	require.NoError(t, err)
	require.True(t, ok, "a sent message is not discarded")
	require.Error(t, w.a.Discard(ctx, "$nope"))

	feed, cancel := w.s.Subscribe()
	defer cancel()
	require.NoError(t, w.a.Discard(ctx, failedID))
	_, ok, err = w.s.GetEvent(ctx, failedID)
	require.NoError(t, err)
	require.False(t, ok, "the failed message is gone")
	select {
	case c := <-feed:
		require.Equal(t, store.Change{Kind: "status", RoomID: room, EventID: failedID, Seq: c.Seq}, c)
	case <-time.After(time.Second):
		t.Fatal("no change announced the discard")
	}
	require.Error(t, w.a.Discard(ctx, failedID), "it is gone")

	// The chat still shows the messages that are left.
	rows, err := w.s.Inbox(ctx)
	require.NoError(t, err)
	require.Equal(t, "this one went", rows[0].Preview)
}

func TestBridgeCommandPrefixRefused(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "telegram", true)
	room, _ := w.chat(t, "chat1", "m1")

	// Telegram's bridge runs "!telegram ..." as an admin command: never send that as a chat message.
	for _, text := range []string{"!telegram logout", "  !Telegram   list-logins", "!telegram"} {
		_, err := w.a.SendText(ctx, room, text, "")
		require.ErrorIs(t, err, ErrBridgeCommand, text)
		require.ErrorContains(t, err, "refusing to send text starting with !telegram: the bridge would run it as an admin command", text)
	}
	// A file's name is its body, so the same rule covers it.
	_, err := w.a.SendFile(ctx, room, writeFile(t, "!telegram logout.txt", []byte("x")), "")
	require.ErrorIs(t, err, ErrBridgeCommand)

	evs, err := w.s.Events(ctx, room, 50)
	require.NoError(t, err)
	require.Len(t, evs, 1, "only the contact's message is stored: a refused command leaves no trace")
	none(t, w.n.Sent, "a bridge command")
	none(t, w.n.Files, "a bridge command")

	// Another network's prefix, and a prefix that is not at the start, are just text here.
	for _, text := range []string{"!whatsapp logout", "hey !telegram is cool", "!important", "telegram !logout"} {
		_, err := w.a.SendText(ctx, room, text, "")
		require.NoError(t, err, text)
		require.Equal(t, text, recv(t, w.n.Sent, text).Body)
	}
}

// A network that isn't linked at all, or isn't running this session, is no network to wait for: a send is refused
// at once (-32010, -32016 on the wire), and nothing is stored, queued or sent.
func TestSendOnAnUnlinkedNetworkIsRefused(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", false) // running, but never linked: no login at all
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!r:courier.local", Network: "fake", Name: "Test"}))
	w.a.LoginWait = time.Hour // refusing must not depend on the wait

	_, err := w.a.SendText(ctx, "!r:courier.local", "hello", "")
	require.ErrorIs(t, err, ErrNotLinked)
	require.EqualError(t, err, "fake isn't linked — run link --network fake first")
	_, err = w.a.Send(ctx, "!r:courier.local", "held", SendOptions{Hold: time.Second})
	require.ErrorIs(t, err, ErrNotLinked, "a held send too")

	_, err = w.a.SendFile(ctx, "!r:courier.local", writeFile(t, "a.txt", []byte("x")), "")
	require.ErrorIs(t, err, ErrNotLinked)
	require.NoDirExists(t, w.m.Dir, "nothing may be stored when the send is refused")

	evs, err := w.s.Events(ctx, "!r:courier.local", 10)
	require.NoError(t, err)
	require.Empty(t, evs, "nothing may be stored")
	none(t, w.n.Sent, "a message")

	// A network that won't run this session.
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: "!tg:courier.local", Network: "telegram", Name: "Elsewhere"}))
	_, err = w.a.SendText(ctx, "!tg:courier.local", "hello", "")
	require.ErrorIs(t, err, engine.ErrNotRunning)
	_, err = w.a.SendFile(ctx, "!tg:courier.local", writeFile(t, "b.txt", []byte("x")), "")
	require.ErrorIs(t, err, engine.ErrNotRunning)
	evs, err = w.s.Events(ctx, "!tg:courier.local", 10)
	require.NoError(t, err)
	require.Empty(t, evs)
	waiting, err := w.s.HasWaiting(ctx, "!tg:courier.local")
	require.NoError(t, err)
	require.False(t, waiting)
}

func TestEmptyTextIsRefused(t *testing.T) {
	w := startWorld(t, "fake", true)
	room, _ := w.chat(t, "chat1", "m1")
	_, err := w.a.SendText(context.Background(), room, "   ", "")
	require.ErrorIs(t, err, ErrEmpty)
	none(t, w.n.Sent, "an empty message")
}

func TestUnknownRoomNeverFallsBack(t *testing.T) {
	w := startWorld(t, "fake", true)
	_, err := w.a.SendText(context.Background(), "!nope:courier.local", "hi", "")
	require.ErrorContains(t, err, "!nope:courier.local")
	none(t, w.n.Sent, "a message to an unknown chat")
}

// A second account (Review Focus 5).

// work adds the login "second" ("Work") beside the world's first, "fake-login".
func (w world) work(t *testing.T) *bridgev2.UserLogin {
	t.Helper()
	h, ok := w.eng.Host(w.name(t))
	require.True(t, ok)
	b, err := w.n.LoginAs(context.Background(), h.Bridge, "second", "Work")
	require.NoError(t, err)
	return b
}

// name is the network the world runs.
func (w world) name(t *testing.T) string {
	t.Helper()
	names := w.eng.Names()
	require.Len(t, names, 1)
	return names[0]
}

// roomWith waits for the bridge to store a chat holding a message with body in it (fakenet.RoomWith), and returns
// the chat.
func (w world) roomWith(t *testing.T, body string) store.Room {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second) // a deadlock guard, not a measure
	defer cancel()
	r, err := fakenet.RoomWith(ctx, w.s, body)
	require.NoError(t, err, "the bridge never stored the chat")
	return r
}

// stateOf is the stored bridge state of the login id ("" when it has none).
func (w world) stateOf(t *testing.T, id string) string {
	t.Helper()
	states, err := w.s.LoginStates(context.Background(), w.name(t))
	require.NoError(t, err)
	for _, l := range states {
		if l.LoginID == id {
			var st struct {
				StateEvent string `json:"state_event"`
				RemoteID   string `json:"remote_id"`
			}
			require.NoError(t, json.Unmarshal(l.State, &st))
			require.Equal(t, id, st.RemoteID, "a login's state is kept under its own remote_id")
			return st.StateEvent
		}
	}
	return ""
}

// Each account's one-to-one chats are its own: the same chat ID on two accounts is two chats, each remembering its
// login (the bridge info's fi.mau.receiver), and a chat both share (a WhatsApp group: surprise 8) remembers none.
func TestSecondLoginKeepsBothAccountsChatsApart(t *testing.T) {
	w := startWorld(t, "fake", true)
	b := w.work(t)
	w.n.Incoming(w.login, "chat1", "alice", "a1", "to my first account")
	w.n.Incoming(b, "chat1", "alice", "b1", "to my second account")
	w.n.IncomingShared(w.login, "group", "carol", "g1", "to us both")

	a, second, shared := w.roomWith(t, "to my first account"), w.roomWith(t, "to my second account"), w.roomWith(t, "to us both")
	require.NotEqual(t, a.ID, second.ID, "one chat per account")
	require.Equal(t, "fake-login", a.LoginID)
	require.Equal(t, "second", second.LoginID)
	require.Empty(t, shared.LoginID, "a shared chat belongs to no one account")

	// The second account writing into the shared chat is still the one chat.
	w.n.IncomingShared(b, "group", "carol", "g2", "again to us both")
	require.Equal(t, shared.ID, w.roomWith(t, "again to us both").ID)
	r, ok, err := w.s.GetRoom(context.Background(), shared.ID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Empty(t, r.LoginID)
}

// Features asks the chat's own login's client (loginOf), never another account's: with that login down and nothing
// stored, a chat has NoFeatures, though the other account is in. A shared chat asks whichever login is in.
func TestFeaturesAskTheChatsOwnLogin(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	b := w.work(t)
	w.n.SetLoginFeatures("second", &event.RoomFeatures{Edit: event.CapLevelFullySupported})
	w.n.SetLoginFeatures("fake-login", &event.RoomFeatures{Thread: event.CapLevelFullySupported})
	w.n.Incoming(w.login, "chatA", "alice", "a1", "for A")
	w.n.Incoming(b, "chatB", "bob", "b1", "for B")
	w.n.IncomingShared(w.login, "group", "carol", "g1", "for both")
	w.n.IncomingShared(b, "group", "carol", "g2", "again for both") // both accounts are in the group
	roomA, roomB, group := w.roomWith(t, "for A").ID, w.roomWith(t, "for B").ID, w.roomWith(t, "for both").ID
	require.Equal(t, group, w.roomWith(t, "again for both").ID)
	for _, room := range []string{roomA, roomB, group} {
		// Nothing stored, so the client is asked (a row that holds null reads as none).
		_, err := w.s.SetState(ctx, room, event.StateBeeperRoomFeatures.Type, "fake", json.RawMessage(`null`))
		require.NoError(t, err)
	}
	features := func(room string) Features {
		t.Helper()
		f, err := w.a.Features(ctx, room)
		require.NoError(t, err)
		return f
	}

	require.True(t, features(roomB).Edit, "B's chat asks B's client")
	require.False(t, features(roomB).Thread)
	require.True(t, features(roomA).Thread, "A's chat asks A's client")
	require.False(t, features(roomA).Edit)

	w.n.SetLoggedIn(b, false)
	require.Equal(t, NoFeatures, features(roomB), "never A's client for B's chat")
	require.True(t, features(roomA).Thread)
	require.True(t, features(group).Thread, "a shared chat asks a login of its that is in")

	w.n.SetLoggedIn(b, true)
	w.n.SetLoggedIn(w.login, false)
	require.True(t, features(group).Edit, "and then the other one")
	w.n.SetLoggedIn(b, false)
	require.Equal(t, NoFeatures, features(group), "with neither of its logins in, nothing is asked")
	require.Equal(t, NoFeatures, features(roomA))
}

// Each login keeps its own state: one going down leaves the other's CONNECTED, and the other's chats still send.
func TestStatesAreKeptPerLogin(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "fake", true)
	b := w.work(t)
	w.n.Incoming(w.login, "chatA", "alice", "a1", "for A")
	roomA := w.roomWith(t, "for A").ID
	feed, cancel := w.s.Subscribe()
	defer cancel()
	settled := func(id, want string) {
		t.Helper()
		for w.stateOf(t, id) != want {
			select {
			case <-feed:
			case <-time.After(5 * time.Second): // a deadlock guard, not a measure
				t.Fatalf("login %s never became %s", id, want)
			}
		}
	}
	w.n.SetLoggedIn(w.login, true)
	w.n.SetLoggedIn(b, true)
	settled("fake-login", "CONNECTED")
	settled("second", "CONNECTED")

	w.n.SetLoggedIn(b, false)
	settled("second", "TRANSIENT_DISCONNECT")
	require.Equal(t, "CONNECTED", w.stateOf(t, "fake-login"), "B going down leaves A's state alone")
	states, err := w.s.LoginStates(ctx, "fake")
	require.NoError(t, err)
	var ids []string
	for _, l := range states {
		ids = append(ids, l.LoginID)
	}
	require.Equal(t, []string{"", "fake-login", "second"}, ids, "one row per login, beside the bridge's own")

	id, err := w.a.SendText(ctx, roomA, "A still sends", "")
	require.NoError(t, err)
	require.Equal(t, "A still sends", recv(t, w.n.Sent, "A's message").Body)
	w.waitStatus(t, id, "sent")
}

// A chat change goes to the network through the chat's own login (loginOf): a login whose client doesn't take pins
// is never asked for one, though the other login's chats are told theirs, and the network's Syncs is the union.
func TestChatChangesGoThroughTheChatsOwnLogin(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.PlainLogins = map[string]bool{"second": true}
	w := startWorldOn(t, "fake", n, true, zerolog.Nop())
	b := w.work(t)
	w.n.Incoming(w.login, "chatA", "alice", "a1", "for A")
	w.n.Incoming(b, "chatB", "bob", "b1", "for B")
	roomA, roomB := w.roomWith(t, "for A").ID, w.roomWith(t, "for B").ID

	require.Equal(t, []string{"pin", "mute", "accept_request"}, w.a.Syncs("fake"), "the union of the logins")
	require.NoError(t, w.a.SetPinned(ctx, roomB, true))
	require.NoError(t, w.a.SetPinned(ctx, roomA, true))
	require.Equal(t, fakenet.TagChange{PortalID: "chatA", Tags: []event.RoomTag{event.RoomTagFavourite}}, recv(t, w.n.Tags, "A's pin"))
	none(t, w.n.Tags, "B's pin")

	// B's pin is Courier's own, not kept for when B is next told anything.
	for key := range w.a.untold.take("fake") {
		require.NotEqual(t, roomB, key.room, "B's pin was kept for the network: %+v", key)
	}
}

// Ruling 12: a chat every account shares goes through the login bridgev2 sends it with (Portal.FindPreferredLogin):
// one of the chat's own logins that is in. A group only B is in is down while B is, though A is in: a send waits
// (and the loop's passes leave it alone), a pin is kept, an edit waits; once B is back each goes, once.
func TestASharedChatIsDownWhileItsOnlyLoginIs(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.Features = whatsappFeatures() // edits
	w := startWorldOn(t, "fake", n, true, zerolog.Nop())
	b := w.work(t)
	w.n.IncomingShared(b, "group", "carol", "g1", "only B is in here")
	group := w.roomWith(t, "only B is in here")
	require.Empty(t, group.LoginID, "a shared chat")
	w.up()
	msg := w.mySent(t, group.ID, "while B is in")
	w.n.SetLoggedIn(b, false)

	id, err := w.a.SendText(ctx, group.ID, "while B is down", "")
	require.NoError(t, err)
	require.Equal(t, store.StatusWaiting, w.get(t, id).Status, "A being in doesn't make B's group up")
	require.NoError(t, w.a.SetPinned(ctx, group.ID, true))
	none(t, w.n.Sent, "the message while B is down")
	none(t, w.n.Tags, "the pin while B is down")

	feed, cancel := w.s.Subscribe()
	defer cancel()
	w.a.SendWaiting(ctx, "fake")
	w.a.SendWaiting(ctx, "fake")
	for len(feed) > 0 {
		c := <-feed
		require.NotEqual(t, "status", c.Kind, "a pass claimed the message only to put it back: %+v", c)
	}
	require.Equal(t, store.StatusWaiting, w.get(t, id).Status)

	lt := newLoginTimer()
	w.a.after = lt.After
	w.a.LoginWait = time.Minute
	edited := make(chan error, 1)
	go func() {
		_, err := w.a.Edit(ctx, msg, "edited while B is down", nil)
		edited <- err
	}()
	lt.awaitWait(t, time.Minute)
	none(t, edited, "the edit's answer while B is down")

	w.n.SetLoggedIn(b, true)
	require.NoError(t, <-edited)
	require.Equal(t, "edited while B is down", recv(t, w.n.Edits, "the edit once B is back").Body)
	w.a.SendWaiting(ctx, "fake")
	require.Equal(t, fakenet.Sent{PortalID: "group", Body: "while B is down"}, recv(t, w.n.Sent, "the message once B is back"))
	w.waitStatus(t, id, "sent")
	require.Equal(t, fakenet.TagChange{PortalID: "group", Tags: []event.RoomTag{event.RoomTagFavourite}}, recv(t, w.n.Tags, "the pin once B is back"))
	none(t, w.n.Sent, "a second copy")
}

func TestRoomInfoAndSetLocalOverride(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "whatsapp", false)
	roomID := "!info:courier.local"

	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{
		ID:      roomID,
		Network: "whatsapp",
		Name:    "Original Group",
		Topic:   "Group topic",
	}))
	require.NoError(t, w.s.SetMember(ctx, roomID, string(ids.Me), json.RawMessage(`{"membership":"join","displayname":"Me"}`)))
	require.NoError(t, w.s.SetMember(ctx, roomID, "@whatsapp_alice:courier.local", json.RawMessage(`{"membership":"join","displayname":"Alice Example"}`)))

	t0 := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	_, err := w.s.InsertEvent(ctx, store.Event{
		RoomID:  roomID,
		EventID: "$img1",
		Sender:  "@whatsapp_alice:courier.local",
		Type:    event.EventMessage.Type,
		Content: json.RawMessage(`{"msgtype":"m.image","body":"photo.png","url":"mxc://courier.local/img1"}`),
		TS:      t0.Add(time.Minute),
		Status:  "sent",
	})
	require.NoError(t, err)
	_, err = w.s.InsertEvent(ctx, store.Event{
		RoomID:  roomID,
		EventID: "$file1",
		Sender:  "@whatsapp_alice:courier.local",
		Type:    event.EventMessage.Type,
		Content: json.RawMessage(`{"msgtype":"m.file","body":"spec.pdf","url":"mxc://courier.local/file1"}`),
		TS:      t0.Add(2 * time.Minute),
		Status:  "sent",
	})
	require.NoError(t, err)
	_, err = w.s.InsertEvent(ctx, store.Event{
		RoomID:  roomID,
		EventID: "$link1",
		Sender:  "@whatsapp_alice:courier.local",
		Type:    event.EventMessage.Type,
		Content: json.RawMessage(`{"msgtype":"m.text","body":"Read https://example.com/spec for details"}`),
		TS:      t0.Add(3 * time.Minute),
		Status:  "sent",
	})
	require.NoError(t, err)

	info, err := w.a.RoomInfo(ctx, roomID, false)
	require.NoError(t, err)
	require.Equal(t, "Original Group", info.Name)
	require.Equal(t, "Original Group", info.RemoteName)
	require.Len(t, info.Members, 2)
	require.Len(t, info.SharedMedia, 1)
	require.Equal(t, "$img1", info.SharedMedia[0].EventID)
	require.Len(t, info.SharedFiles, 1)
	require.Equal(t, "$file1", info.SharedFiles[0].EventID)
	require.Len(t, info.SharedLinks, 1)
	require.Equal(t, "https://example.com/spec", info.SharedLinks[0].URL)
	require.Equal(t, "example.com", info.SharedLinks[0].Host)

	require.NoError(t, w.a.SetRoomLocalOverride(ctx, roomID, "Renamed Locally", ""))
	info, err = w.a.RoomInfo(ctx, roomID, false)
	require.NoError(t, err)
	require.Equal(t, "Renamed Locally", info.Name)
	require.Equal(t, "Original Group", info.RemoteName)
	require.Equal(t, "Renamed Locally", info.LocalName)
}

func TestExportChatWritesChronologicalPlainText(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "whatsapp", false)
	roomID := "!export:courier.local"
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: roomID, Network: "whatsapp", Name: "Export Group"}))
	require.NoError(t, w.s.SetMember(ctx, roomID, "@alice:courier.local", json.RawMessage(`{"membership":"join","displayname":"Alice"}`)))
	require.NoError(t, w.s.SetMember(ctx, roomID, "@bob:courier.local", json.RawMessage(`{"membership":"join","displayname":"Bob"}`)))

	_, err := w.s.InsertEvent(ctx, store.Event{
		RoomID:  roomID,
		EventID: "$e1",
		Sender:  "@alice:courier.local",
		Type:    event.EventMessage.Type,
		Content: json.RawMessage(`{"msgtype":"m.text","body":"Hello"}`),
		TS:      time.UnixMilli(1700000000000),
		Status:  "sent",
	})
	require.NoError(t, err)
	_, err = w.s.InsertEvent(ctx, store.Event{
		RoomID:  roomID,
		EventID: "$e2",
		Sender:  "@bob:courier.local",
		Type:    event.EventMessage.Type,
		Content: json.RawMessage(`{"msgtype":"m.text","body":"World"}`),
		TS:      time.UnixMilli(1700000060000),
		Status:  "sent",
	})
	require.NoError(t, err)

	tmpFile := filepath.Join(t.TempDir(), "export.txt")
	count, err := w.a.ExportChat(ctx, roomID, tmpFile)
	require.NoError(t, err)
	require.Equal(t, 2, count)

	raw, err := os.ReadFile(tmpFile)
	require.NoError(t, err)
	require.Equal(t, "[2023-11-14 22:13:20 UTC] Alice: Hello\n[2023-11-14 22:14:20 UTC] Bob: World\n", string(raw))
}

func TestReportSpamHidesLocallyByDefaultAndLeavesOnlyWhenOptedIn(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "whatsapp", true)
	roomID, _ := w.chat(t, "spam-grp", "m1")
	w.s.SetClock(func() time.Time { return time.UnixMilli(1700000000000) })
	w.n.ResetCalls()

	require.NoError(t, w.a.ReportSpam(ctx, roomID, false))
	room, ok, err := w.s.GetRoom(ctx, roomID)
	require.NoError(t, err)
	require.True(t, ok)
	require.True(t, room.Hidden)
	require.Equal(t, int64(1700000000000), room.SpamReportedAt)
	require.Empty(t, w.n.Calls())

	require.NoError(t, w.a.ReportSpam(ctx, roomID, true))
	calls := w.n.Calls()
	require.Len(t, calls, 1)
	require.Equal(t, "HandleMatrixMembership", calls[0].Method)
	require.Equal(t, "leave", calls[0].Value)
}

func TestGroupSetNameTopicAvatarUpdatesStoreAndCallsBridge(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "whatsapp", true)
	roomID, _ := w.chat(t, "grp-meta", "m1")
	w.n.ResetCalls()

	require.NoError(t, w.a.SetRoomName(ctx, roomID, "Project Hyperion"))
	require.NoError(t, w.a.SetRoomTopic(ctx, roomID, "Milestone 4.5a planning"))

	avatarPath := filepath.Join(t.TempDir(), "avatar.png")
	require.NoError(t, os.WriteFile(avatarPath, []byte("fake-png-bytes"), 0o600))
	require.NoError(t, w.a.SetRoomAvatar(ctx, roomID, avatarPath))

	calls := w.n.Calls()
	require.Len(t, calls, 3)
	require.Equal(t, "HandleMatrixRoomName", calls[0].Method)
	require.Equal(t, "Project Hyperion", calls[0].Value)
	require.Equal(t, "HandleMatrixRoomTopic", calls[1].Method)
	require.Equal(t, "Milestone 4.5a planning", calls[1].Value)
	require.Equal(t, "HandleMatrixRoomAvatar", calls[2].Method)
	require.Contains(t, calls[2].Value, "mxc://courier.local/")

	room, ok, err := w.s.GetRoom(ctx, roomID)
	require.NoError(t, err)
	require.True(t, ok)
	require.Equal(t, "Project Hyperion", room.Name)
	require.Equal(t, "Milestone 4.5a planning", room.Topic)
	require.Equal(t, calls[2].Value, room.AvatarURI)
	require.Empty(t, room.LocalName, "SetRoomName updates the network name, never local_name")
	require.Empty(t, room.LocalAvatarURI, "SetRoomAvatar updates the network avatar, never local_avatar_uri")
}

func TestGroupInviteKickAndSetAdmin(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "whatsapp", true)
	roomID, _ := w.chat(t, "grp-members", "m1")
	w.n.ResetCalls()

	carol := "@carol:courier.local"
	require.NoError(t, w.a.InviteMembers(ctx, roomID, []string{carol}))

	members, err := w.s.RoomMembers(ctx, roomID)
	require.NoError(t, err)
	var carolHit *store.MemberHit
	for i := range members {
		if members[i].UserID == carol {
			carolHit = &members[i]
			break
		}
	}
	require.NotNil(t, carolHit, "invited member must appear in RoomMembers")
	require.Equal(t, "invite", carolHit.Membership)
	require.False(t, carolHit.IsAdmin)

	require.NoError(t, w.a.SetMemberAdmin(ctx, roomID, carol, true))
	members, err = w.s.RoomMembers(ctx, roomID)
	require.NoError(t, err)
	carolHit = nil
	for i := range members {
		if members[i].UserID == carol {
			carolHit = &members[i]
			break
		}
	}
	require.NotNil(t, carolHit)
	require.Equal(t, 50, carolHit.PowerLevel)
	require.True(t, carolHit.IsAdmin)

	require.NoError(t, w.a.KickMember(ctx, roomID, carol, "wrong group"))
	members, err = w.s.RoomMembers(ctx, roomID)
	require.NoError(t, err)
	for _, m := range members {
		require.NotEqual(t, carol, m.UserID, "kicked member must not appear in RoomMembers")
	}

	calls := w.n.Calls()
	require.Len(t, calls, 3)
	require.Equal(t, "HandleMatrixMembership", calls[0].Method)
	require.Equal(t, "invite", calls[0].Value)
	require.Equal(t, "HandleMatrixPowerLevels", calls[1].Method)
	require.Equal(t, "50", calls[1].Value)
	require.Equal(t, "HandleMatrixMembership", calls[2].Method)
	require.Equal(t, "leave", calls[2].Value)
}

func TestGroupLeaveAndDeleteChat(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "whatsapp", true)
	leaveRoomID, _ := w.chat(t, "grp-leave", "m1")
	delRoomID, _ := w.chat(t, "grp-delete", "m2")
	w.n.ResetCalls()

	require.NoError(t, w.a.LeaveRoom(ctx, leaveRoomID))
	leaveRoom, ok, err := w.s.GetRoom(ctx, leaveRoomID)
	require.NoError(t, err)
	require.True(t, ok)
	require.True(t, leaveRoom.Hidden)
	members, err := w.s.RoomMembers(ctx, leaveRoomID)
	require.NoError(t, err)
	for _, m := range members {
		require.NotEqual(t, string(ids.Me), m.UserID, "self membership must be leave")
	}

	require.NoError(t, w.a.DeleteChat(ctx, delRoomID))
	delRoom, ok, err := w.s.GetRoom(ctx, delRoomID)
	require.NoError(t, err)
	require.True(t, ok)
	require.True(t, delRoom.Hidden)

	calls := w.n.Calls()
	require.Len(t, calls, 2)
	require.Equal(t, "HandleMatrixMembership", calls[0].Method)
	require.Equal(t, string(ids.Me), calls[0].Target)
	require.Equal(t, "leave", calls[0].Value)
	require.Equal(t, "HandleMatrixDeleteChat", calls[1].Method)
}

func TestGroupLeaveFailureDoesNotHideRoom(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "whatsapp", true)
	roomID, _ := w.chat(t, "grp-leave-fail", "m1")
	w.n.ResetCalls()
	w.n.Refuse = true
	t.Cleanup(func() { w.n.Refuse = false })

	err := w.a.LeaveRoom(ctx, roomID)
	require.ErrorIs(t, err, ErrNetworkRefused)

	room, ok, err := w.s.GetRoom(ctx, roomID)
	require.NoError(t, err)
	require.True(t, ok)
	require.False(t, room.Hidden, "failed leave must not hide the room")

	members, err := w.s.RoomMembers(ctx, roomID)
	require.NoError(t, err)
	foundMe := false
	for _, m := range members {
		if m.UserID == string(ids.Me) {
			foundMe = true
			require.Equal(t, "join", m.Membership)
		}
	}
	require.True(t, foundMe, "self must remain joined when leave fails on the network")
}

func TestGroupActionsRejectWhenCapabilityFalse(t *testing.T) {
	ctx := context.Background()
	w := startWorld(t, "gmessages", true)
	roomID, _ := w.chat(t, "gm-grp", "m1")
	origClient := w.login.Client
	w.login.Client = struct{ bridgev2.NetworkAPI }{origClient}
	t.Cleanup(func() { w.login.Client = origClient })
	w.n.ResetCalls()

	require.ErrorIs(t, w.a.SetRoomTopic(ctx, roomID, "nope"), ErrNotSupported)
	require.ErrorIs(t, w.a.SetMemberAdmin(ctx, roomID, "@carol:courier.local", true), ErrNotSupported)
	require.ErrorIs(t, w.a.SetRoomName(ctx, roomID, "nope"), ErrNotSupported)
	require.ErrorIs(t, w.a.SetRoomAvatar(ctx, roomID, "mxc://courier.local/abc"), ErrNotSupported)
	require.ErrorIs(t, w.a.InviteMembers(ctx, roomID, []string{"@carol:courier.local"}), ErrNotSupported)
	require.ErrorIs(t, w.a.KickMember(ctx, roomID, "@carol:courier.local", ""), ErrNotSupported)
	require.ErrorIs(t, w.a.LeaveRoom(ctx, roomID), ErrNotSupported)
	require.ErrorIs(t, w.a.DeleteChat(ctx, roomID), ErrNotSupported)
	require.Empty(t, w.n.Calls())
}

func TestResolveIdentifierCreatesRoomWhenPortalInfoNil(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.StartChats = fakenet.ViaGhost
	n.OmitPortalInfo = true
	aliceName := "Alice"
	n.SetChat(fakenet.DirectChatID("+15550100101"), fakenet.Chat{Name: &aliceName})
	w := startWorldOn(t, "whatsapp", n, true, zerolog.Nop())

	cand, err := w.a.ResolveIdentifier(ctx, "whatsapp", "", "+15550100101", true)
	require.NoError(t, err)
	require.NotEmpty(t, cand.RoomID)
	require.Equal(t, "Alice", cand.Name)

	room, ok, err := w.s.GetRoom(ctx, cand.RoomID)
	require.NoError(t, err)
	require.True(t, ok)
	require.True(t, room.IsDirect)
	require.Equal(t, "Alice", room.Name)

	members, err := w.s.Members(ctx, cand.RoomID)
	require.NoError(t, err)
	require.Contains(t, members, string(ids.GhostMXID("whatsapp", "+15550100101")))
}

func TestListContactsMergesContactListAndUserSearch(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.StartChats = fakenet.ViaGhost
	w := startWorldOn(t, "whatsapp", n, true, zerolog.Nop())

	hash, err := w.m.Put([]byte("fake-avatar-bytes"))
	require.NoError(t, err)
	avatarURI := ids.ContentURI(hash)
	wantAvatarPath, err := w.m.Path(hash)
	require.NoError(t, err)

	w.n.Contacts = []fakenet.Contact{
		{
			UserID:      "u-alice",
			Name:        "Alice",
			AvatarURL:   avatarURI,
			Identifiers: []string{"tel:+15550100101"},
		},
		{
			UserID:      "u-bob",
			Name:        "Bob",
			Identifiers: []string{"tel:+15550100202"},
		},
	}
	w.n.SearchResults = []fakenet.Contact{
		{
			UserID:      "u-alice",
			Name:        "Alice",
			AvatarURL:   avatarURI,
			Identifiers: []string{"tel:+15550100101"},
		},
	}

	got, err := w.a.ListContacts(ctx, "whatsapp", "", "ali")
	require.NoError(t, err)
	require.Len(t, got, 1)
	require.Equal(t, "Alice", got[0].Name)
	require.Equal(t, wantAvatarPath, got[0].AvatarPath)
	require.Contains(t, got[0].Identifiers, "tel:+15550100101")
}

func TestCreateGroupAndSendBlast(t *testing.T) {
	ctx := context.Background()
	n := fakenet.New()
	n.StartChats = fakenet.ViaGhost
	w := startWorldOn(t, "whatsapp", n, true, zerolog.Nop())

	groupRoomID, err := w.a.CreateGroup(ctx, "whatsapp", "", "Trip Planners", []string{"@u1:courier.local", "@u2:courier.local"})
	require.NoError(t, err)
	require.NotEmpty(t, groupRoomID)

	grp, ok, err := w.s.GetRoom(ctx, groupRoomID)
	require.NoError(t, err)
	require.True(t, ok)
	require.False(t, grp.IsDirect)
	require.Equal(t, "Trip Planners", grp.Name)

	dmRoom1, _ := w.chat(t, "dm-1", "m1")
	dmRoom2, _ := w.secondChat(t, "dm-2", "m2", dmRoom1)

	evs, err := w.a.SendBlast(ctx, []string{dmRoom1, dmRoom2}, "Hey team")
	require.NoError(t, err)
	require.Len(t, evs, 2)
	require.NotEqual(t, evs[0].EventID, evs[1].EventID)
	require.Equal(t, dmRoom1, evs[0].RoomID)
	require.Equal(t, dmRoom2, evs[1].RoomID)
	require.Equal(t, event.EventMessage.Type, evs[0].Type)
	require.Equal(t, event.EventMessage.Type, evs[1].Type)

	sent1 := recv(t, w.n.Sent, "first blast message")
	sent2 := recv(t, w.n.Sent, "second blast message")
	require.ElementsMatch(t, []fakenet.Sent{
		{PortalID: "dm-1", Body: "Hey team"},
		{PortalID: "dm-2", Body: "Hey team"},
	}, []fakenet.Sent{sent1, sent2})

	// A failure in one room must not stop the others in a blast.
	partialEvs, err := w.a.SendBlast(ctx, []string{"!missing-room:courier.local", dmRoom2}, "Second blast")
	require.NoError(t, err)
	require.Len(t, partialEvs, 2)
	require.Equal(t, "failed", partialEvs[0].Status)
	require.Equal(t, dmRoom2, partialEvs[1].RoomID)
	require.Equal(t, fakenet.Sent{PortalID: "dm-2", Body: "Second blast"}, recv(t, w.n.Sent, "surviving room blast message"))

	// Bridge errors on CreateGroup (e.g. Google Messages ErrMinimumTwoUsers) surface to the caller.
	w.n.ChatStartErr = errors.New("minimum 2 other users required")
	t.Cleanup(func() { w.n.ChatStartErr = nil })
	_, err = w.a.CreateGroup(ctx, "whatsapp", "", "Too Small", []string{"@u1:courier.local"})
	require.ErrorIs(t, err, ErrNetworkRefused)
}
