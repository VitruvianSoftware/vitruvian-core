// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func (w world) redacted(t *testing.T, eventID string) bool {
	t.Helper()
	r, err := w.s.Redacted(context.Background(), eventID)
	require.NoError(t, err)
	return r
}

// Review Focus 1: an unsend past the network's limit never looks done here, and never reaches the network.
func TestUnsendTooOldIsRefusedBeforeSending(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures()) // unsend within 2 days
	clock := w.clocked()
	sentAt := clock.Now()
	old := w.mySent(t, room, "two days ago")
	fresh := w.mySent(t, room, "just now")
	require.Equal(t, sentAt, w.get(t, old).TS)

	clock.Set(sentAt.Add(48*time.Hour + time.Minute))
	before := w.eventCount(t, room)
	_, err := w.a.Unsend(ctx, old)
	require.ErrorIs(t, err, ErrTooOld)
	require.Equal(t, before, w.eventCount(t, room), "no redaction stored")
	require.False(t, w.redacted(t, old), "still in the chat")
	require.Empty(t, w.n.Removes, "nothing reached the network")

	// At exactly 2 days it still goes.
	clock.Set(sentAt.Add(48 * time.Hour))
	redaction, err := w.a.Unsend(ctx, fresh)
	require.NoError(t, err)
	require.True(t, w.redacted(t, fresh), "gone from the chat at once")
	require.Equal(t, "out-"+fresh, recv(t, w.n.Removes, "the unsend").TargetID)
	w.waitStatus(t, redaction, "sent")
	require.Equal(t, map[string]any{"redacts": fresh}, content(t, w.get(t, redaction)))

	// Gone already: nothing to unsend.
	_, err = w.a.Unsend(ctx, fresh)
	require.ErrorIs(t, err, ErrNotSupported)
}

func TestUnsendRefusals(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	clock := w.clocked()
	theirs := w.firstID(t, room)
	held, err := w.a.Send(ctx, room, "held", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)
	failed := w.insertMine(t, room, "m.room.message", `{"msgtype":"m.text","body":"failed"}`, "failed", clock.Now())
	before := w.eventCount(t, room)

	_, err = w.a.Unsend(ctx, theirs)
	require.ErrorIs(t, err, ErrNotYours)
	_, err = w.a.Unsend(ctx, held)
	require.ErrorIs(t, err, ErrNotSupported, "a held message is taken back with Undo")
	_, err = w.a.Unsend(ctx, failed)
	require.ErrorIs(t, err, ErrNotSupported)
	_, err = w.a.Unsend(ctx, "$nonesuch")
	require.ErrorIs(t, err, store.ErrNotFound)
	require.Equal(t, before, w.eventCount(t, room))
	require.Empty(t, w.n.Removes)
}

func TestUnsendMyReaction(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, googleMessagesFeatures()) // can't unsend messages, but takes reactions back
	clock := w.clocked()
	target := w.firstID(t, room)
	reaction, err := w.a.React(ctx, room, target, "👍")
	require.NoError(t, err)
	recv(t, w.n.Reactions, "the reaction")
	w.waitStatus(t, reaction, "sent")

	clock.Set(clock.Now().Add(365 * 24 * time.Hour)) // a reaction has no age limit
	redaction, err := w.a.Unsend(ctx, reaction)
	require.NoError(t, err)
	require.True(t, w.redacted(t, reaction))
	removed := recv(t, w.n.ReactionRemoves, "the reaction taken back")
	require.Equal(t, "👍", removed.Emoji)
	w.waitStatus(t, redaction, "sent")
	require.Empty(t, w.n.Removes, "a reaction isn't a message")
}

// Review Focus 1: Google Messages' bridge takes a redaction but only deletes from the phone, so Courier never
// offers it as an unsend: Delete for Me reaches the phone instead.
func TestGoogleMessagesNeverUnsends(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, googleMessagesFeatures())
	theirs := w.firstID(t, room)
	msg := w.mySent(t, room, "on the phone too")
	before := w.eventCount(t, room)

	_, err := w.a.Unsend(ctx, msg)
	require.ErrorIs(t, err, ErrNotSupported)
	require.False(t, w.redacted(t, msg))
	require.Empty(t, w.n.Removes)

	require.NoError(t, w.a.DeleteForMe(ctx, msg))
	require.Equal(t, "out-"+msg, recv(t, w.n.Removes, "the delete on the phone").TargetID)
	gone := w.get(t, msg)
	require.True(t, gone.DeletedForMe)
	require.True(t, w.redacted(t, msg))
	require.Equal(t, before, w.eventCount(t, room), "the redaction is stored nowhere")

	// Someone else's message leaves the phone too.
	require.NoError(t, w.a.DeleteForMe(ctx, theirs))
	recv(t, w.n.Removes, "their message deleted on the phone")
	require.True(t, w.get(t, theirs).DeletedForMe)
}

func TestDeleteForMeIsLocalElsewhere(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	theirs := w.firstID(t, room)
	mine := w.mySent(t, room, "mine")
	before := w.eventCount(t, room)

	require.NoError(t, w.a.DeleteForMe(ctx, theirs))
	require.NoError(t, w.a.DeleteForMe(ctx, mine))
	require.True(t, w.get(t, theirs).DeletedForMe)
	require.True(t, w.get(t, mine).DeletedForMe)
	require.Empty(t, w.n.Removes, "nothing reaches the network")
	require.Equal(t, before, w.eventCount(t, room))

	held, err := w.a.Send(ctx, room, "held", SendOptions{Hold: 10 * time.Second})
	require.NoError(t, err)
	require.ErrorIs(t, w.a.DeleteForMe(ctx, held), ErrNotSupported, "Undo takes a held message back")
	require.ErrorIs(t, w.a.DeleteForMe(ctx, "$nonesuch"), store.ErrNotFound)
}

func TestRefusedUnsendBringsTheMessageBack(t *testing.T) {
	ctx := context.Background()
	w, room := startFeatureWorld(t, whatsappFeatures())
	msg := w.mySent(t, room, "still here")
	w.n.Refuse = true
	redaction, err := w.a.Unsend(ctx, msg)
	require.NoError(t, err)
	w.waitStatus(t, redaction, "failed")
	require.False(t, w.redacted(t, msg), "back in the chat")
	require.Equal(t, event.EventRedaction.Type, w.get(t, redaction).Type)
}

// A delete for me that the phone refuses stays deleted here; the refusal is logged at warn, by network and kind of
// change only.
func TestDeleteForMeStaysWhenThePhoneRefuses(t *testing.T) {
	ctx := context.Background()
	logs := &logBuffer{}
	n := fakenet.New()
	n.Features = googleMessagesFeatures()
	w := startWorldOn(t, "gmessages", n, true, zerolog.New(logs))
	room, theirs := w.chat(t, "alice", "m1")
	n.Refuse = true

	require.NoError(t, w.a.DeleteForMe(ctx, theirs), "a refusal is no error to the person deleting")
	require.True(t, w.get(t, theirs).DeletedForMe, "and it stays deleted here")
	require.True(t, w.redacted(t, theirs))
	require.Empty(t, w.n.Removes)

	var warned []string
	for _, l := range logs.lines() {
		if strings.Contains(l, `"change":"delete_for_me"`) {
			warned = append(warned, l)
		}
	}
	require.Len(t, warned, 1, "one warning for the refused delete")
	require.Contains(t, warned[0], `"level":"warn"`)
	for _, private := range []string{room, theirs, "alice", "hi", "Fake chat"} {
		require.NotContains(t, warned[0], private, "it names nothing else")
	}
}
