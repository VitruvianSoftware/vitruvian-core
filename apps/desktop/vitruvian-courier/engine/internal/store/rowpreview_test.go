// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func reactionTo(target, key string) string {
	b, _ := json.Marshal(map[string]any{"m.relates_to": map[string]string{"rel_type": "m.annotation", "event_id": target, "key": key}})
	return string(b)
}

func member(name, avatar string) json.RawMessage {
	b, _ := json.Marshal(map[string]string{"membership": "join", "displayname": name, "avatar_url": avatar})
	return b
}

// The newest activity being a reaction shows it on the row (Beeper's "Kent reacted 😂 to …"), with who reacted, and
// changes nothing else: the order, the time and the unread count stay the message's.
func TestInboxPreviewsANewerReaction(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!g", time.Unix(1, 0))
	mkRoom(t, s, "!other", time.Unix(2, 0))
	require.NoError(t, s.SetMember(ctx, "!g", ghost, member("Kent", "")))
	mkMsg(t, s, "!g", "$mine", me, "m.room.message", text("Maybe in his mind he did\nsomething about the long list of things we keep talking about"), time.Unix(100, 0))
	mkMsg(t, s, "!other", "$o", ghost, "m.room.message", text("newer chat"), time.Unix(150, 0))
	before := inboxByID(t, s)["!g"]
	require.Equal(t, "text", before.PreviewKind)
	require.True(t, before.PreviewMine)
	require.Empty(t, before.PreviewSenderName, "my own message names nobody")

	mkMsg(t, s, "!g", "$r", ghost, "m.reaction", reactionTo("$mine", "😂"), time.Unix(200, 0))
	rows, err := s.Inbox(ctx)
	require.NoError(t, err)
	require.Equal(t, "!other", rows[0].ID, "a reaction doesn't move the chat up")
	row := inboxByID(t, s)["!g"]
	require.Equal(t, "reaction", row.PreviewKind)
	require.Equal(t, "😂 to “Maybe in his mind he did something about the long list of t…”", row.Preview,
		"the message is quoted on one line and cut with an ellipsis")
	require.False(t, row.PreviewMine, "someone else reacted")
	require.Equal(t, "Kent", row.PreviewSenderName, "who reacted, by their name in the chat")
	require.Empty(t, row.PreviewStatus, "a reaction preview says nothing of my message's receipts")
	require.Equal(t, before.LastTS, row.LastTS, "the time stays the message's")
	require.Equal(t, before.Unread, row.Unread, "a reaction is never unread")

	// A message after the reaction takes the row back.
	mkMsg(t, s, "!g", "$next", ghost, "m.room.message", text("ok"), time.Unix(300, 0))
	row = inboxByID(t, s)["!g"]
	require.Equal(t, "text", row.PreviewKind)
	require.Equal(t, "ok", row.Preview)
	require.Equal(t, "Kent", row.PreviewSenderName, "the newest message's sender is named too")

	// My reaction to a photo: the reaction alone (the app words the rest), and it is mine.
	mkMsg(t, s, "!g", "$pic", ghost, "m.room.message", `{"msgtype":"m.image","body":"IMG_1.jpg","url":"mxc://x/y"}`, time.Unix(400, 0))
	mkMsg(t, s, "!g", "$r2", me, "m.reaction", reactionTo("$pic", "❤️"), time.Unix(500, 0))
	row = inboxByID(t, s)["!g"]
	require.Equal(t, "reaction", row.PreviewKind)
	require.Equal(t, "❤️", row.Preview)
	require.True(t, row.PreviewMine)
	require.Empty(t, row.PreviewSenderName)
	require.Empty(t, row.PreviewMediaURI, "the photo's thumbnail is the message's preview, not the reaction's")

	// Taking the reaction back shows the message again.
	mkMsg(t, s, "!g", "$unreact", me, "m.room.redaction", redactionOf("$r2"), time.Unix(600, 0))
	row = inboxByID(t, s)["!g"]
	require.Equal(t, "image", row.PreviewKind, "a removed reaction is no preview")
	require.Equal(t, "Kent", row.PreviewSenderName)
}

// An older reaction (a backfill, or one to an old message made before the newest message) doesn't take the row.
func TestInboxIgnoresReactionsOlderThanTheNewestMessage(t *testing.T) {
	s := open(t)
	mkRoom(t, s, "!g", time.Unix(1, 0))
	mkMsg(t, s, "!g", "$a", ghost, "m.room.message", text("a"), time.Unix(100, 0))
	mkMsg(t, s, "!g", "$r", ghost, "m.reaction", reactionTo("$a", "👍"), time.Unix(150, 0))
	mkMsg(t, s, "!g", "$b", ghost, "m.room.message", text("b"), time.Unix(200, 0))
	row := inboxByID(t, s)["!g"]
	require.Equal(t, "text", row.PreviewKind)
	require.Equal(t, "b", row.Preview)
	require.Equal(t, "ghost", row.PreviewSenderName, "no name anywhere: the ID's localpart")
}

func TestReactionPreview(t *testing.T) {
	for _, tc := range []struct{ name, content, typ, target, want string }{
		{"short text", reactionTo("$x", "😂"), "m.room.message", text("hi there"), "😂 to “hi there”"},
		{"poll", reactionTo("$x", "👍"), pollStartType, `{"org.matrix.msc3381.poll.start":{"question":{"body":"Lunch?"},"answers":[]}}`, "👍 to “Lunch?”"},
		{"message not here", reactionTo("$x", "👍"), "", "", "👍"},
		{"malformed", "{", "m.room.message", text("x"), "to “x”"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, reactionPreview(tc.content, tc.typ, tc.target))
		})
	}
	long := reactionTo("$x", strings.Repeat("🎉", 200))
	require.LessOrEqual(t, len([]rune(reactionPreview(long, "m.room.message", text("x")))), maxPreviewRunes)
}

// A group with no picture gets up to three people for one: recent speakers first, then those with a picture; never
// me, the bridge's bot, a bot or my own ghost. One query for every chat.
func TestMemberPreviews(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!g", time.Unix(1, 0))
	mkRoom(t, s, "!solo", time.Unix(2, 0))
	add := func(room, user, name, avatar string) {
		require.NoError(t, s.SetMember(ctx, room, user, member(name, avatar)))
	}
	add("!g", me, "Me", "mxc://x/me")
	add("!g", "@whatsappbot:courier.local", "Bot", "mxc://x/bot")
	add("!g", "@whatsapp_self:courier.local", "Also me", "mxc://x/self")
	add("!g", "@a:courier.local", "Alice", "")
	add("!g", "@b:courier.local", "Bob", "mxc://x/b")
	add("!g", "@c:courier.local", "Carol", "mxc://x/c")
	add("!g", "@d:courier.local", "Dave", "")
	add("!g", "@robot:courier.local", "Robot", "mxc://x/r")
	require.NoError(t, s.SetMember(ctx, "!g", "@left:courier.local", json.RawMessage(`{"membership":"leave","displayname":"Gone","avatar_url":"mxc://x/l"}`)))
	require.NoError(t, s.SetProfileExtraMeta(ctx, "@robot:courier.local", nil, "", true))
	require.NoError(t, s.SetLoginState(ctx, "whatsapp", "self", json.RawMessage(`{"state_event":"CONNECTED","remote_id":"self"}`)))
	add("!solo", me, "Me", "")
	mkMsg(t, s, "!g", "$1", "@d:courier.local", "m.room.message", text("old"), time.Unix(10, 0))
	mkMsg(t, s, "!g", "$2", "@a:courier.local", "m.room.message", text("newer"), time.Unix(20, 0))
	mkMsg(t, s, "!g", "$3", me, "m.room.message", text("mine"), time.Unix(30, 0))

	got, err := s.MemberPreviews(ctx, []string{"!g", "!solo", "!g"})
	require.NoError(t, err)
	require.Equal(t, []RowMember{
		{UserID: "@a:courier.local", Name: "Alice"},
		{UserID: "@d:courier.local", Name: "Dave"},
		{UserID: "@b:courier.local", Name: "Bob", AvatarURI: "mxc://x/b"},
	}, got["!g"], "the newest speaker first, then the next; then whoever has a picture, by name")
	_, ok := got["!solo"]
	require.False(t, ok, "a chat with nobody else has no entry")

	none, err := s.MemberPreviews(ctx, nil)
	require.NoError(t, err)
	require.Empty(t, none)
}

// MemberPreviews reads a bounded slice of a huge chat: its recent speakers and its first member rows.
func TestMemberPreviewsOfAHugeChatIsBounded(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!big", time.Unix(1, 0))
	for i := 0; i < 2000; i++ {
		require.NoError(t, s.SetMember(ctx, "!big", fmt.Sprintf("@u%04d:courier.local", i), member(fmt.Sprintf("U%04d", i), "")))
	}
	mkMsg(t, s, "!big", "$last", "@u1999:courier.local", "m.room.message", text("hi"), time.Unix(10, 0))
	start := time.Now()
	got, err := s.MemberPreviews(ctx, []string{"!big"})
	require.NoError(t, err)
	require.Less(t, time.Since(start), time.Second)
	require.Len(t, got["!big"], MaxRowMembers)
	require.Equal(t, "@u1999:courier.local", got["!big"][0].UserID, "a recent speaker past the first member rows still counts")
	plan := strings.Join(planOf(t, s, memberPreviewsSQL, `["!big"]`), "\n")
	require.NotContains(t, plan, "SCAN m\n", "members are read by their primary key")
	require.NotContains(t, plan, "SCAN y", "the recent messages are a range of events_room_ts")
}
