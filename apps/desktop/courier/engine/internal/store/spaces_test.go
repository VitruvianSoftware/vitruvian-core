// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func spaceIDs(spaces []Space) []string {
	out := make([]string, len(spaces))
	for i, sp := range spaces {
		out[i] = sp.ID
	}
	return out
}

func spacesByID(t *testing.T, s *Store, networks ...string) map[string]Space {
	t.Helper()
	spaces, err := s.Spaces(context.Background(), networks)
	require.NoError(t, err)
	out := map[string]Space{}
	for _, sp := range spaces {
		out[sp.ID] = sp
	}
	return out
}

func TestDefaultSpaces(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.SetNetworkNames(map[string]string{"whatsapp": "WhatsApp", "telegram": "Telegram"})
	work := mkLabel(t, s, "Work")
	spaces, err := s.Spaces(ctx, []string{"whatsapp", "telegram"})
	require.NoError(t, err)
	label := "label:" + strconv.FormatInt(work.ID, 10)
	require.Equal(t, []string{
		"inbox", "reminders", "requests", "low_priority", "send_later", "archive",
		"account:whatsapp", "account:telegram", label,
	}, spaceIDs(spaces))
	require.Equal(t, Space{ID: "inbox", Kind: "builtin"}, spaces[0], "the app names the built-in spaces")
	require.Equal(t, Space{ID: "account:telegram", Kind: "account", Title: "Telegram", Network: "telegram", ShowInInbox: "all"}, spaces[7])
	require.Equal(t, Space{ID: label, Kind: "label", Title: "Work", LabelID: work.ID, Color: 3, Icon: "tag", ShowInInbox: "all"}, spaces[8])

	// A network without a display name shows its own name rather than nothing.
	require.Equal(t, "slack", spacesByID(t, s, "slack")["account:slack"].Title)
}

func TestSpaceLayoutKeepsInboxFirstAndAddsNewSpacesAtTheEnd(t *testing.T) {
	s, ctx := open(t), context.Background()
	nets := []string{"whatsapp", "telegram"}
	work := mkLabel(t, s, "Work")
	workSpace := "label:" + strconv.FormatInt(work.ID, 10)

	for _, bad := range []struct{ order, hidden []string }{
		{[]string{"archive", "inbox"}, nil},
		{[]string{}, nil},
		{[]string{"inbox", "archive"}, []string{"inbox"}},
		{[]string{"inbox", "archive", "archive"}, nil},
		{[]string{"inbox", "nope"}, nil},
		{[]string{"inbox", "account:"}, nil},
		{[]string{"inbox", "label:abc"}, nil},
		{[]string{"inbox", "archive"}, []string{"reminders"}},
	} {
		require.ErrorIs(t, s.SetSpaceLayout(ctx, bad.order, bad.hidden), ErrBadValue, "%v hidden %v", bad.order, bad.hidden)
	}

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.SetSpaceLayout(ctx, []string{"inbox", "archive", "account:whatsapp", workSpace, "reminders"}, []string{"reminders", workSpace}))
	require.Equal(t, Change{Kind: "spaces"}, nextChange(t, ch))
	spaces, err := s.Spaces(ctx, nets)
	require.NoError(t, err)
	require.Equal(t, []string{
		"inbox", "archive", "account:whatsapp", workSpace, "reminders",
		"requests", "low_priority", "send_later", "account:telegram",
	}, spaceIDs(spaces),
		"the saved order, then what it left out, in the default order")
	hidden := map[string]bool{}
	for _, sp := range spaces {
		hidden[sp.ID] = sp.Hidden
	}
	require.Equal(t, map[string]bool{
		"inbox": false, "archive": false, "account:whatsapp": false, workSpace: true, "reminders": true,
		"requests": false, "low_priority": false, "send_later": false, "account:telegram": false,
	}, hidden)

	// A new label goes at the end, visible.
	fam := mkLabel(t, s, "Family")
	spaces, err = s.Spaces(ctx, nets)
	require.NoError(t, err)
	last := spaces[len(spaces)-1]
	require.Equal(t, "label:"+strconv.FormatInt(fam.ID, 10), last.ID)
	require.False(t, last.Hidden)

	// An account that is no longer linked drops out of the list, and comes back where it was if it returns.
	require.NotContains(t, spaceIDs(spacesByIDList(t, s, "telegram")), "account:whatsapp")
	require.Equal(t, "account:whatsapp", spaceIDs(spacesByIDList(t, s, "whatsapp"))[2])
}

func spacesByIDList(t *testing.T, s *Store, networks ...string) []Space {
	t.Helper()
	spaces, err := s.Spaces(context.Background(), networks)
	require.NoError(t, err)
	return spaces
}

func TestUpdateSpace(t *testing.T) {
	s, ctx := open(t), context.Background()
	work := mkLabel(t, s, "Work")
	workSpace := "label:" + strconv.FormatInt(work.ID, 10)

	require.ErrorIs(t, s.UpdateSpace(ctx, "inbox", ptr(true), nil), ErrBadValue, "a built-in space has no settings")
	require.ErrorIs(t, s.UpdateSpace(ctx, "archive", nil, ptr("dms")), ErrBadValue)
	require.ErrorIs(t, s.UpdateSpace(ctx, "bogus", ptr(true), nil), ErrBadValue)
	require.ErrorIs(t, s.UpdateSpace(ctx, "account:whatsapp", nil, ptr("some")), ErrBadValue)
	require.ErrorIs(t, s.UpdateSpace(ctx, "label:9999", ptr(true), nil), ErrNotFound)

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.UpdateSpace(ctx, "account:whatsapp", nil, ptr("dms")))
	require.Equal(t, Change{Kind: "spaces"}, nextChange(t, ch))
	require.NoError(t, s.UpdateSpace(ctx, workSpace, ptr(true), ptr("none")))
	require.Equal(t, Change{Kind: "spaces"}, nextChange(t, ch))

	sp := spacesByID(t, s, "whatsapp")
	require.Equal(t, "dms", sp["account:whatsapp"].ShowInInbox)
	require.False(t, sp["account:whatsapp"].Muted, "setting one field leaves the other")
	require.True(t, sp[workSpace].Muted)
	require.Equal(t, "none", sp[workSpace].ShowInInbox)
	labels, err := s.Labels(ctx)
	require.NoError(t, err)
	require.True(t, labels[0].Muted)
	require.Equal(t, "none", labels[0].ShowInInbox)
}

func TestSpaceCounts(t *testing.T) {
	s, ctx := open(t), context.Background()
	room := func(id, network string, direct bool) {
		require.NoError(t, s.UpsertRoom(ctx, Room{ID: id, Network: network, IsDirect: direct, CreatedAt: time.Unix(1, 0)}))
	}
	room("!dm", "whatsapp", true)
	room("!grp", "whatsapp", false)
	room("!arch", "whatsapp", false)
	room("!low", "whatsapp", false)
	room("!hid", "whatsapp", true)
	room("!req", "whatsapp", true)
	room("!tg", "telegram", true)
	mkMsg(t, s, "!dm", "$dm", ghost, "m.room.message", text("unread"), time.Unix(10, 0))
	mkMsg(t, s, "!grp", "$grp", ghost, "m.room.message", text("read"), time.Unix(10, 0))
	require.NoError(t, s.MarkReadLocal(ctx, "!grp", "$grp", time.Unix(10, 0)))
	mkMsg(t, s, "!req", "$req", me, "m.room.message", text("mine"), time.Unix(10, 0))
	_, err := s.SetArchived(ctx, []string{"!arch"}, true)
	require.NoError(t, err)
	_, err = s.SetLowPriority(ctx, []string{"!low"}, true)
	require.NoError(t, err)
	_, err = s.SetMarkedUnread(ctx, []string{"!low", "!tg"}, true)
	require.NoError(t, err)
	_, err = s.SetHidden(ctx, []string{"!hid"}, true)
	require.NoError(t, err)
	require.NoError(t, s.SetRequest(ctx, "!req", true))
	_, err = s.db.Exec(ctx, `INSERT INTO reminders (room_id, due_at, condition, set_at) VALUES ('!tg', 1, 'always', 1), ('!hid', 1, 'always', 1)`)
	require.NoError(t, err)
	work, home := mkLabel(t, s, "Work"), mkLabel(t, s, "Home")
	workSpace, homeSpace := "label:"+strconv.FormatInt(work.ID, 10), "label:"+strconv.FormatInt(home.ID, 10)
	_, err = s.SetLabel(ctx, []string{"!grp", "!arch"}, work.ID, true)
	require.NoError(t, err)
	_, err = s.SetLabel(ctx, []string{"!dm"}, home.ID, true)
	require.NoError(t, err)

	counts := func() map[string][2]int {
		out := map[string][2]int{}
		for id, sp := range spacesByID(t, s, "whatsapp", "telegram") {
			out[id] = [2]int{sp.Chats, sp.UnreadChats}
		}
		return out
	}
	require.Equal(t, map[string][2]int{
		"inbox":            {3, 2}, // !dm (unread), !grp (read), !tg (marked unread)
		"reminders":        {1, 1}, // !tg; !hid's reminder is hidden with it
		"requests":         {1, 0},
		"low_priority":     {1, 1},
		"send_later":       {0, 0},
		"archive":          {1, 0},
		"account:whatsapp": {2, 1}, // its chats in the inbox place
		"account:telegram": {1, 1},
		workSpace:          {1, 0}, // !grp; !arch is archived
		homeSpace:          {1, 1},
	}, counts())

	// Show in Inbox: WhatsApp at dms drops its group from the inbox, not from its own space; Home at none drops !dm.
	require.NoError(t, s.UpdateSpace(ctx, "account:whatsapp", nil, ptr("dms")))
	require.NoError(t, s.UpdateSpace(ctx, homeSpace, nil, ptr("none")))
	c := counts()
	require.Equal(t, [2]int{1, 1}, c["inbox"], "only !tg is left")
	require.Equal(t, [2]int{2, 1}, c["account:whatsapp"])
	require.Equal(t, [2]int{1, 1}, c[homeSpace])
	require.NoError(t, s.UpdateSpace(ctx, "account:telegram", nil, ptr("none")))
	require.Equal(t, [2]int{0, 0}, counts()["inbox"])
}

func TestSpaceCountsReadEachRoomOnceAndNeverScanEvents(t *testing.T) {
	s := open(t)
	seedBig(t, s, 200, 3, 10)
	plan := planOf(t, s, spaceCountsSQL, me)
	t.Log("plan:\n  " + strings.Join(plan, "\n  "))
	// Counting every space has to look at every chat, so rooms are scanned, once (into c); everything else,
	// events above all, is an index lookup.
	for _, line := range plan {
		if strings.HasPrefix(line, "SCAN ") && !strings.Contains(line, "INDEX") {
			require.Contains(t, []string{"SCAN r", "SCAN c"}, line, "only rooms and the materialized c are scanned")
		}
	}
	require.Contains(t, plan, "MATERIALIZE c")
	require.Contains(t, strings.Join(plan, "\n"), "SEARCH u USING INDEX events_room_ts")
}
