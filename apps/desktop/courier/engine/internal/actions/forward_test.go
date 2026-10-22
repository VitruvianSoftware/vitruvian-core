// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// insertFrom stores an event from someone else straight into the store, returning its ID.
func (w world) insertFrom(t *testing.T, room, sender, typ, content string, ts time.Time) string {
	t.Helper()
	id := string(ids.RandomEventID())
	_, err := w.s.InsertEvent(context.Background(), store.Event{
		RoomID: room, EventID: id, Sender: sender, Type: typ, Content: json.RawMessage(content), TS: ts,
	})
	require.NoError(t, err)
	return id
}

func TestForwardCopiesWithoutAttributionOrMentions(t *testing.T) {
	ctx := context.Background()
	w, roomA := startFeatureWorld(t, whatsappFeatures())
	roomB, _ := w.secondChat(t, "bob", "m2", roomA)
	now := time.Now()
	alice := "@alice:courier.local"

	// A reply of Alice's that mentions Bob, with a timer and Beeper keys, then edited.
	original := w.insertFrom(t, roomA, alice, "m.room.message", `{
		"msgtype": "m.text",
		"body": "> <@carol:courier.local> earlier\n\nhi Bob",
		"format": "org.matrix.custom.html",
		"formatted_body": "<mx-reply><blockquote>earlier</blockquote></mx-reply>hi <a href=\"https://matrix.to/#/@bob:courier.local\">Bob</a>",
		"m.mentions": {"user_ids": ["@bob:courier.local"]},
		"m.relates_to": {"m.in_reply_to": {"event_id": "$earlier"}},
		"com.beeper.disappearing_timer": {"type": "after_send", "timer": 86400000},
		"com.beeper.linkpreviews": []
	}`, now)
	w.insertFrom(t, roomA, alice, "m.room.message", fmt.Sprintf(`{
		"msgtype": "m.text", "body": "* hi Bob!",
		"m.new_content": {"msgtype": "m.text", "body": "hi Bob!", "format": "org.matrix.custom.html",
			"formatted_body": "<em>hi</em> <a href='https://matrix.to/#/%%40bob%%3Acourier.local'><strong>Bob</strong></a>!"},
		"m.relates_to": {"rel_type": "m.replace", "event_id": %q}
	}`, original), now.Add(time.Second))

	res := w.a.Forward(ctx, original, []string{roomB})
	require.Empty(t, res.Failed)
	copyID := res.Sent[roomB]
	require.NotEmpty(t, copyID)
	sent := recv(t, w.n.Sent, "the copy")
	require.Equal(t, "hi Bob!", sent.Body)
	require.Empty(t, sent.ReplyTo)
	copied := w.waitStatus(t, copyID, "sent")
	require.Equal(t, roomB, copied.RoomID)
	require.Equal(t, string(ids.Me), copied.Sender)
	require.Equal(t, map[string]any{
		"msgtype": "m.text", "body": "hi Bob!", "format": "org.matrix.custom.html",
		"formatted_body": "<em>hi</em> <strong>Bob</strong>!",
	}, content(t, copied), "no reply, mentions, timer or Beeper keys; the mention is its text")

	// A sticker goes as an image, with its picture.
	sticker := w.insertFrom(t, roomA, alice, "m.sticker",
		`{"body":"cat","url":"mxc://courier.local/abc","info":{"mimetype":"image/png","w":64,"h":64},"m.relates_to":{"m.in_reply_to":{"event_id":"$x"}}}`, now)
	res = w.a.Forward(ctx, sticker, []string{roomB})
	require.Empty(t, res.Failed)
	f := recv(t, w.n.Files, "the sticker as an image")
	require.Equal(t, event.MsgImage, f.MsgType)
	require.Equal(t, "mxc://courier.local/abc", f.URL)
	require.Equal(t, "image/png", f.MimeType)
	c := content(t, w.get(t, res.Sent[roomB]))
	require.Equal(t, "m.image", c["msgtype"])
	require.NotContains(t, c, "m.relates_to")

	// A chat with a timer gives the copy its own.
	require.NoError(t, w.a.SetDisappearing(ctx, roomB, "after_send", 7*24*time.Hour))
	recv(t, w.n.Timers, "the timer")
	res = w.a.Forward(ctx, original, []string{roomB})
	require.Empty(t, res.Failed)
	recv(t, w.n.Sent, "the copy")
	require.Equal(t, map[string]any{"type": "after_send", "timer": float64(7 * 24 * 3600 * 1000)},
		content(t, w.get(t, res.Sent[roomB]))["com.beeper.disappearing_timer"])
}

func TestForwardToAPlainChatDropsTheFormatting(t *testing.T) {
	ctx := context.Background()
	w, roomA := startFeatureWorld(t, googleMessagesFeatures())
	roomB, _ := w.secondChat(t, "bob", "m2", roomA)
	msg := w.insertFrom(t, roomA, "@alice:courier.local", "m.room.message",
		`{"msgtype":"m.text","body":"hi","format":"org.matrix.custom.html","formatted_body":"<b>hi</b>"}`, time.Now())
	res := w.a.Forward(ctx, msg, []string{roomB})
	require.Empty(t, res.Failed)
	recv(t, w.n.Sent, "the copy")
	require.Equal(t, map[string]any{"msgtype": "m.text", "body": "hi"}, content(t, w.get(t, res.Sent[roomB])))
}

func TestForwardReportsEachRoom(t *testing.T) {
	ctx := context.Background()
	w, roomA := startFeatureWorld(t, whatsappFeatures())
	roomB, _ := w.secondChat(t, "bob", "m2", roomA)
	msg := w.firstID(t, roomA)

	res := w.a.Forward(ctx, msg, []string{roomB, "!nonesuch:courier.local", roomB})
	require.Len(t, res.Sent, 1, "one copy for a chat named twice")
	require.NotEmpty(t, res.Sent[roomB])
	require.Len(t, res.Failed, 1)
	require.Error(t, res.Failed["!nonesuch:courier.local"])
	require.Equal(t, "hi", recv(t, w.n.Sent, "the copy").Body)
	require.Empty(t, w.n.Sent)

	// More than 20 chats: none of them.
	many := make([]string, MaxForwardRooms+1)
	for i := range many {
		many[i] = roomB
	}
	many[0] = "!a:courier.local"
	res = w.a.Forward(ctx, msg, many)
	require.Empty(t, res.Sent)
	require.ErrorIs(t, res.Failed[roomB], ErrBadValue)
	require.ErrorIs(t, res.Failed["!a:courier.local"], ErrBadValue)

	// A poll, a deleted message and an unknown one can't be forwarded anywhere.
	poll, err := w.a.CreatePoll(ctx, roomA, "Lunch?", []string{"Pizza", "Sushi"}, false)
	require.NoError(t, err)
	recv(t, w.n.Polls, "the poll")
	deleted := w.insertFrom(t, roomA, "@alice:courier.local", "m.room.message", `{"msgtype":"m.text","body":"gone"}`, time.Now())
	require.NoError(t, w.s.SetDeletedForMe(ctx, deleted))
	for _, id := range []string{poll, deleted} {
		res = w.a.Forward(ctx, id, []string{roomB})
		require.Empty(t, res.Sent)
		require.ErrorIs(t, res.Failed[roomB], ErrNotSupported, id)
	}
	res = w.a.Forward(ctx, "$nonesuch", []string{roomB})
	require.ErrorIs(t, res.Failed[roomB], store.ErrNotFound)
	require.Empty(t, w.n.Sent)
}
