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
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// insertMine stores an event of mine straight into the store (as if sent earlier), returning its ID.
func (w world) insertMine(t *testing.T, room, typ, content, status string, ts time.Time) string {
	t.Helper()
	id := string(ids.RandomEventID())
	_, err := w.s.InsertEvent(context.Background(), store.Event{
		RoomID: room, EventID: id, Sender: string(ids.Me), Type: typ, Content: json.RawMessage(content), TS: ts, Status: status,
	})
	require.NoError(t, err)
	return id
}

func TestEditReachesTheNetwork(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	msg := w.mySent(t, room, "hello")

	bold := []richtext.Entity{{Kind: richtext.Bold, Offset: 6, Length: 5}}
	editID, err := w.a.Edit(ctx, msg, "hello there", bold)
	require.NoError(t, err)
	edit := recv(t, w.n.Edits, "the edit")
	require.Equal(t, "hello there", edit.Body)
	require.Equal(t, "out-"+msg, edit.TargetID)
	w.waitStatus(t, editID, "sent")

	c := content(t, w.get(t, editID))
	require.Equal(t, "* hello there", c["body"])
	require.Equal(t, "* hello <strong>there</strong>", c["formatted_body"])
	require.Equal(t, map[string]any{"rel_type": "m.replace", "event_id": msg}, c["m.relates_to"])
	require.Equal(t, map[string]any{
		"msgtype": "m.text", "body": "hello there", "format": "org.matrix.custom.html",
		"formatted_body": "hello <strong>there</strong>",
	}, c["m.new_content"])
	text, err := w.s.CurrentText(ctx, w.get(t, msg))
	require.NoError(t, err)
	require.Equal(t, "hello there", text)
}

func TestEditRefusals(t *testing.T) {
	ctx := context.Background()
	rf := whatsappFeatures()
	rf.EditMaxCount = 2
	w, room := startFeatureWorld(t, rf)
	clock := w.clocked()
	now := clock.Now()
	theirs := w.firstID(t, room)
	text := func(body string) string { return fmt.Sprintf(`{"msgtype":"m.text","body":%q}`, body) }

	image := w.insertMine(t, room, "m.room.message", `{"msgtype":"m.image","body":"a.png","url":"mxc://courier.local/x"}`, "sent", now)
	sticker := w.insertMine(t, room, "m.sticker", `{"body":"cat","url":"mxc://courier.local/x"}`, "sent", now)
	pending := w.insertMine(t, room, "m.room.message", text("pending"), "pending", now)
	failed := w.insertMine(t, room, "m.room.message", text("failed"), "failed", now)
	deleted := w.insertMine(t, room, "m.room.message", text("deleted"), "sent", now)
	require.NoError(t, w.s.SetDeletedForMe(ctx, deleted))
	target := w.insertMine(t, room, "m.room.message", text("target"), "sent", now)
	anEdit := w.insertMine(t, room, "m.room.message",
		fmt.Sprintf(`{"msgtype":"m.text","body":"* x","m.new_content":{"msgtype":"m.text","body":"x"},"m.relates_to":{"rel_type":"m.replace","event_id":%q}}`, target), "sent", now)
	old := w.insertMine(t, room, "m.room.message", text("old"), "sent", now.Add(-15*time.Minute-time.Second))
	edge := w.insertMine(t, room, "m.room.message", text("edge"), "sent", now.Add(-15*time.Minute))
	edited := w.insertMine(t, room, "m.room.message", text("edited"), "sent", now)
	for i := range 2 {
		w.insertMine(t, room, "m.room.message",
			fmt.Sprintf(`{"msgtype":"m.text","body":"* v%d","m.new_content":{"msgtype":"m.text","body":"v%d"},"m.relates_to":{"rel_type":"m.replace","event_id":%q}}`, i, i, edited), "sent", now)
	}
	before := w.eventCount(t, room)

	for _, tc := range []struct {
		name, eventID string
		want          error
	}{
		{"someone else's message", theirs, ErrNotYours},
		{"an image", image, ErrNotSupported},
		{"a sticker", sticker, ErrNotSupported},
		{"a message still pending", pending, ErrNotSupported},
		{"a failed message", failed, ErrNotSupported},
		{"a deleted message", deleted, ErrNotSupported},
		{"an edit itself", anEdit, ErrNotSupported},
		{"past the 15 minutes", old, ErrTooOld},
		{"at its most edits", edited, ErrTooOld},
	} {
		_, err := w.a.Edit(ctx, tc.eventID, "new", nil)
		require.ErrorIs(t, err, tc.want, tc.name)
	}
	_, err := w.a.Edit(ctx, "$nonesuch", "new", nil)
	require.ErrorIs(t, err, store.ErrNotFound)
	require.Equal(t, before, w.eventCount(t, room), "nothing stored")
	require.Empty(t, w.n.Edits, "nothing sent")

	// At exactly 15 minutes it is still editable. (The bridge, which goes by its own record of when the network
	// took the message, has none for a message stored straight into the store, so it refuses: the edit fails.)
	edgeEdit, err := w.a.Edit(ctx, edge, "still in time", nil)
	require.NoError(t, err)
	w.waitStatus(t, edgeEdit, "failed")

	// A chat whose network can't edit.
	w2, room2 := startFeatureWorld(t, googleMessagesFeatures())
	mine := w2.mySent(t, room2, "can't change this")
	_, err = w2.a.Edit(ctx, mine, "new", nil)
	require.ErrorIs(t, err, ErrNotSupported)
	require.Empty(t, w2.n.Edits)
}

func TestRefusedEditComesBackFailed(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	msg := w.mySent(t, room, "what I meant")

	w.n.Refuse = true
	editID, err := w.a.Edit(ctx, msg, "what I said", nil)
	require.NoError(t, err)
	w.waitStatus(t, editID, "failed")
	require.Empty(t, w.n.Edits)

	text, err := w.s.CurrentText(ctx, w.get(t, msg))
	require.NoError(t, err)
	require.Equal(t, "what I meant", text, "the old text is back")
	versions, err := w.s.EditHistory(ctx, msg)
	require.NoError(t, err)
	require.Len(t, versions, 1, "a refused edit isn't part of the history")
	require.Equal(t, event.MsgText, event.MessageType(content(t, w.get(t, editID))["m.new_content"].(map[string]any)["msgtype"].(string)))
}

// A notice and an emote are text too: the edit keeps their msgtype, in the fallback and in m.new_content.
func TestEditANoticeAndAnEmote(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	h, ok := w.eng.Host("whatsapp")
	require.True(t, ok)

	// An emote the network took (fakenet files every msgtype but text under Files).
	emote, err := w.a.submit(ctx, h, room, event.EventMessage, &event.MessageEventContent{MsgType: event.MsgEmote, Body: "waves"})
	require.NoError(t, err)
	recv(t, w.n.Files, "the emote")
	w.waitStatus(t, emote, "sent")
	editID, err := w.a.Edit(ctx, emote, "waves back", nil)
	require.NoError(t, err)
	require.Equal(t, "waves back", recv(t, w.n.Edits, "the edit of the emote").Body)
	w.waitStatus(t, editID, "sent")
	c := content(t, w.get(t, editID))
	require.Equal(t, "m.emote", c["msgtype"])
	require.Equal(t, "* waves back", c["body"])
	require.Equal(t, map[string]any{"msgtype": "m.emote", "body": "waves back"}, c["m.new_content"])

	// A notice (bridgev2 doesn't send notices by default, so this one is stored as sent straight away; the bridge,
	// with no record of it, then refuses the edit).
	notice := w.insertMine(t, room, "m.room.message", `{"msgtype":"m.notice","body":"note"}`, "sent", time.Now())
	editID, err = w.a.Edit(ctx, notice, "noted", nil)
	require.NoError(t, err)
	c = content(t, w.get(t, editID))
	require.Equal(t, "m.notice", c["msgtype"])
	require.Equal(t, "* noted", c["body"])
	require.Equal(t, map[string]any{"msgtype": "m.notice", "body": "noted"}, c["m.new_content"])
	w.waitStatus(t, editID, "failed")
}

// Final fix wave: a timer-change note, the engine's own (mine, sent, never handed to a bridge) or a bridge's of a
// change made from my phone, is no message of anyone's to edit, unsend or forward. The engine refuses each with
// ErrNotSupported, whatever the app offers; only Delete for Me takes it off this Mac.
func TestTimerNotesAreNotEditedUnsentOrForwarded(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	other, _ := w.secondChat(t, "bob", "m2", room)
	local := string(ids.RandomEventID())
	inserted, err := w.s.InsertTimerNote(ctx, room, local, "after_send", 24*time.Hour, time.Now(), w.s.LastSeq())
	require.NoError(t, err)
	require.True(t, inserted)
	// A different setting, so it isn't taken for the network echoing mine (Ruling 40).
	fromPhone := w.insertMine(t, room, "m.room.message", `{"msgtype":"m.notice","body":"Set the disappearing message timer to 1 week",
		"com.beeper.action_message":{"type":"disappearing_timer","timer":604800000,"timer_type":"after_send","implicit":false}}`,
		"sent", time.Now())

	for _, note := range []string{local, fromPhone} {
		_, err = w.a.Edit(ctx, note, "changed", nil)
		require.ErrorIs(t, err, ErrNotSupported, "edit %s", note)
		_, err = w.a.Unsend(ctx, note)
		require.ErrorIs(t, err, ErrNotSupported, "unsend %s", note)
		res := w.a.Forward(ctx, note, []string{other})
		require.Empty(t, res.Sent)
		require.ErrorIs(t, res.Failed[other], ErrNotSupported, "forward %s", note)
	}
	none(t, w.n.Sent, "a copy of a note")
	none(t, w.n.Edits, "an edit of a note")
	none(t, w.n.Removes, "an unsend of a note")
	require.NoError(t, w.a.DeleteForMe(ctx, local), "Delete for Me still takes it off this Mac")
}

// A call note of mine (Telegram's record of a call I made, which the bridge sends as me) is no words of mine to edit,
// unsend or forward either: the engine refuses each, and Delete for Me takes it off this Mac.
func TestCallNotesAreNotEditedUnsentOrForwarded(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	other, _ := w.secondChat(t, "bob", "m2", room)
	call := w.insertMine(t, room, "m.room.message", string(store.AnnotateCallNote("telegram", "m.room.message",
		json.RawMessage(`{"msgtype":"m.notice","body":"Call missed"}`))), "sent", time.Now())
	_, err := w.a.Edit(ctx, call, "changed", nil)
	require.ErrorIs(t, err, ErrNotSupported, "edit")
	_, err = w.a.Unsend(ctx, call)
	require.ErrorIs(t, err, ErrNotSupported, "unsend")
	res := w.a.Forward(ctx, call, []string{other})
	require.Empty(t, res.Sent)
	require.ErrorIs(t, res.Failed[other], ErrNotSupported, "forward")
	none(t, w.n.Sent, "a copy of a call note")
	none(t, w.n.Edits, "an edit of a call note")
	none(t, w.n.Removes, "an unsend of a call note")
	require.NoError(t, w.a.DeleteForMe(ctx, call), "Delete for Me still takes it off this Mac")
}
