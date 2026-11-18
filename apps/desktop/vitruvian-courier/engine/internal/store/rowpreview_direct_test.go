// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// A one-to-one chat's members_preview must name the same other person chat info names, so the inbox row, the header
// and chat info share one colour. Here the room also holds a service bot (listed in io.element.functional_members,
// not named as the network's bot, not flagged is_bot) that spoke most recently.
func TestOneToOneRowAndChatInfoAgreeOnTheCounterpartWithAServiceBotPresent(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!dm", time.Unix(1, 0))
	add := func(user, name string) {
		require.NoError(t, s.SetMember(ctx, "!dm", user, member(name, "")))
	}
	add(me, "Me")
	add("@ann:courier.local", "Ann")
	add("@opsbot:courier.local", "Ops")
	_, err := s.SetState(ctx, "!dm", "io.element.functional_members", "",
		[]byte(`{"service_members":["@opsbot:courier.local"]}`))
	require.NoError(t, err)
	mkMsg(t, s, "!dm", "$ann", "@ann:courier.local", "m.room.message", text("hi"), time.Unix(10, 0))
	mkMsg(t, s, "!dm", "$ops", "@opsbot:courier.local", "m.room.message", text("bridge notice"), time.Unix(20, 0))

	chatInfo, err := s.RoomMembers(ctx, "!dm")
	require.NoError(t, err)
	var infoPeers []string
	for _, m := range chatInfo {
		if m.UserID != me {
			infoPeers = append(infoPeers, m.UserID)
		}
	}
	require.Equal(t, []string{"@ann:courier.local"}, infoPeers, "chat info already leaves the service bot out")

	previews, err := s.MemberPreviews(ctx, []string{"!dm"})
	require.NoError(t, err)
	require.NotEmpty(t, previews["!dm"])
	require.Equal(t, "@ann:courier.local", previews["!dm"][0].UserID,
		"the row's counterpart must be the person chat info names, not the service bot")
}

// A one-to-one chat whose only other member is the network's bot has no counterpart: no entry, so the app falls back
// to the room ID, the same as chat info.
func TestOneToOneWithOnlyTheBridgeBotHasNoCounterpart(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!bot", time.Unix(1, 0))
	require.NoError(t, s.SetMember(ctx, "!bot", me, member("Me", "")))
	require.NoError(t, s.SetMember(ctx, "!bot", "@whatsappbot:courier.local", member("Bridge", "")))
	mkMsg(t, s, "!bot", "$b", "@whatsappbot:courier.local", "m.room.message", text("x"), time.Unix(10, 0))

	got, err := s.MemberPreviews(ctx, []string{"!bot"})
	require.NoError(t, err)
	require.Empty(t, got["!bot"])
}
