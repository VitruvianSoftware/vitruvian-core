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

func mkLabel(t *testing.T, s *Store, title string) Label {
	t.Helper()
	l, err := s.CreateLabel(context.Background(), title, 3, "tag")
	require.NoError(t, err)
	return l
}

func ptr[T any](v T) *T { return &v }

func TestLabelsAreKeptOldestFirst(t *testing.T) {
	s, ctx := open(t), context.Background()
	clk := clockAt(s, time.Unix(1000, 0))
	ch, cancel := s.Subscribe()
	defer cancel()

	work, err := s.CreateLabel(ctx, "  Work  ", 0, "briefcase")
	require.NoError(t, err)
	require.Equal(t, Change{Kind: "spaces"}, nextChange(t, ch))
	require.Equal(t, Label{ID: work.ID, Title: "Work", Color: 0, Icon: "briefcase", ShowInInbox: "all"}, work, "the title is trimmed")
	clk.set(time.Unix(2000, 0))
	family := mkLabel(t, s, "Family")
	require.Equal(t, "spaces", nextChange(t, ch).Kind)

	labels, err := s.Labels(ctx)
	require.NoError(t, err)
	require.Equal(t, []Label{work, family}, labels)

	// A partial update changes only what it names.
	require.NoError(t, s.UpdateLabel(ctx, work.ID, LabelUpdate{Color: ptr(11)}))
	require.Equal(t, Change{Kind: "spaces"}, nextChange(t, ch))
	require.NoError(t, s.UpdateLabel(ctx, work.ID, LabelUpdate{Title: ptr(" Office "), Icon: ptr("building.2")}))
	require.Equal(t, "spaces", nextChange(t, ch).Kind)
	labels, err = s.Labels(ctx)
	require.NoError(t, err)
	require.Equal(t, Label{ID: work.ID, Title: "Office", Color: 11, Icon: "building.2", ShowInInbox: "all"}, labels[0])

	require.ErrorIs(t, s.UpdateLabel(ctx, 9999, LabelUpdate{Color: ptr(1)}), ErrNotFound)
	requireNoChange(t, ch)
}

func TestLabelValidation(t *testing.T) {
	s, ctx := open(t), context.Background()
	bad := []struct {
		title string
		color int
		icon  string
	}{
		{strings.Repeat("a", 41), 0, "tag"},
		{"   ", 0, "tag"},
		{"", 0, "tag"},
		{"ok", 12, "tag"},
		{"ok", -1, "tag"},
		{"ok", 0, ""},
		{"ok", 0, strings.Repeat("x", 65)},
	}
	for _, b := range bad {
		_, err := s.CreateLabel(ctx, b.title, b.color, b.icon)
		require.ErrorIs(t, err, ErrBadValue, "%q %d %q", b.title, b.color, b.icon)
	}
	labels, err := s.Labels(ctx)
	require.NoError(t, err)
	require.Empty(t, labels, "nothing is stored")

	// The limits themselves are fine: 40 characters (not bytes), colour 11, a 64-byte icon.
	l, err := s.CreateLabel(ctx, strings.Repeat("é", 40), 11, strings.Repeat("x", 64))
	require.NoError(t, err)

	// An update is checked the same way and, refused, changes nothing.
	require.ErrorIs(t, s.UpdateLabel(ctx, l.ID, LabelUpdate{Title: ptr(strings.Repeat("a", 41))}), ErrBadValue)
	require.ErrorIs(t, s.UpdateLabel(ctx, l.ID, LabelUpdate{Color: ptr(12)}), ErrBadValue)
	require.ErrorIs(t, s.UpdateLabel(ctx, l.ID, LabelUpdate{Icon: ptr("")}), ErrBadValue)
	require.ErrorIs(t, s.UpdateLabel(ctx, l.ID, LabelUpdate{Color: ptr(1), Icon: ptr("")}), ErrBadValue)
	labels, err = s.Labels(ctx)
	require.NoError(t, err)
	require.Equal(t, []Label{l}, labels)
}

func TestSetLabelReportsOnlyRealChanges(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!a", time.Unix(1, 0))
	mkRoom(t, s, "!b", time.Unix(2, 0))
	work, fam := mkLabel(t, s, "Work"), mkLabel(t, s, "Family")

	ch, cancel := s.Subscribe()
	defer cancel()
	changed, err := s.SetLabel(ctx, []string{"!a", "!b", "!a"}, fam.ID, true)
	require.NoError(t, err)
	require.Equal(t, []string{"!a", "!b"}, changed)
	require.Equal(t, Change{Kind: "room", RoomID: "!a"}, nextChange(t, ch))
	require.Equal(t, Change{Kind: "room", RoomID: "!b"}, nextChange(t, ch))
	changed, err = s.SetLabel(ctx, []string{"!a"}, work.ID, true)
	require.NoError(t, err)
	require.Equal(t, []string{"!a"}, changed)
	require.Equal(t, "room", nextChange(t, ch).Kind)

	changed, err = s.SetLabel(ctx, []string{"!a", "!b"}, fam.ID, true)
	require.NoError(t, err)
	require.Empty(t, changed)
	requireNoChange(t, ch)

	rows := inboxByID(t, s)
	require.Equal(t, []int64{work.ID, fam.ID}, rows["!a"].Labels, "by label ID")
	require.Equal(t, []int64{fam.ID}, rows["!b"].Labels)

	_, err = s.SetLabel(ctx, []string{"!a"}, 9999, true)
	require.ErrorIs(t, err, ErrNotFound)
	_, err = s.SetLabel(ctx, []string{"!b", "!nope"}, work.ID, true)
	require.ErrorIs(t, err, ErrNotFound)
	require.Equal(t, []int64{fam.ID}, inboxByID(t, s)["!b"].Labels, "a batch with an unknown chat changes none")

	changed, err = s.SetLabel(ctx, []string{"!a"}, fam.ID, false)
	require.NoError(t, err)
	require.Equal(t, []string{"!a"}, changed)
	require.Equal(t, []int64{work.ID}, inboxByID(t, s)["!a"].Labels)
}

func TestDeletingALabelTakesItOffEveryChat(t *testing.T) {
	s, ctx := open(t), context.Background()
	mkRoom(t, s, "!a", time.Unix(1, 0))
	mkRoom(t, s, "!b", time.Unix(2, 0))
	mkRoom(t, s, "!c", time.Unix(3, 0))
	work, keep := mkLabel(t, s, "Work"), mkLabel(t, s, "Keep")
	_, err := s.SetLabel(ctx, []string{"!a", "!b"}, work.ID, true)
	require.NoError(t, err)
	_, err = s.SetLabel(ctx, []string{"!b"}, keep.ID, true)
	require.NoError(t, err)
	space := "label:" + strconv.FormatInt(work.ID, 10)
	require.NoError(t, s.SetSpaceLayout(ctx, []string{"inbox", space, "archive"}, []string{space}))
	_, err = s.db.Exec(ctx, `INSERT INTO auto_archive_rules (rule_id, scope, trigger, duration_ms) VALUES (1, $1, 'older_than', 1), (2, 'all', 'after_read', 1)`, space)
	require.NoError(t, err)
	_, err = s.db.Exec(ctx, `INSERT INTO archive_due (room_id, due_at, rule_id) VALUES ('!a', 1, 1), ('!c', 1, 2)`)
	require.NoError(t, err)

	ch, cancel := s.Subscribe()
	defer cancel()
	require.NoError(t, s.DeleteLabel(ctx, work.ID))
	got := map[Change]bool{nextChange(t, ch): true, nextChange(t, ch): true, nextChange(t, ch): true}
	require.Equal(t, map[Change]bool{{Kind: "room", RoomID: "!a"}: true, {Kind: "room", RoomID: "!b"}: true, {Kind: "spaces"}: true}, got)
	requireNoChange(t, ch)

	rows := inboxByID(t, s)
	require.Empty(t, rows["!a"].Labels)
	require.Equal(t, []int64{keep.ID}, rows["!b"].Labels)
	labels, err := s.Labels(ctx)
	require.NoError(t, err)
	require.Equal(t, []Label{keep}, labels)
	count := func(q string) int {
		var n int
		require.NoError(t, s.db.QueryRow(ctx, q).Scan(&n))
		return n
	}
	require.Equal(t, 0, count("SELECT COUNT(*) FROM space_layout WHERE space_id = '"+space+"'"), "its layout row goes")
	require.Equal(t, 2, count("SELECT COUNT(*) FROM space_layout"), "the others stay")
	require.Equal(t, 0, count("SELECT COUNT(*) FROM auto_archive_rules WHERE rule_id = 1"), "its rules go")
	require.Equal(t, 1, count("SELECT COUNT(*) FROM auto_archive_rules"), "other rules stay")
	require.Equal(t, 1, count("SELECT COUNT(*) FROM archive_due"), "and what its rules had scheduled")

	require.ErrorIs(t, s.DeleteLabel(ctx, work.ID), ErrNotFound)
}

func TestMutedByLabelAndAccount(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.SetNetworkNames(map[string]string{"whatsapp": "WhatsApp"})
	mkRoom(t, s, "!r", time.Unix(1, 0)) // a whatsapp chat
	first, second := mkLabel(t, s, "First"), mkLabel(t, s, "Second")
	_, err := s.SetLabel(ctx, []string{"!r"}, first.ID, true)
	require.NoError(t, err)
	_, err = s.SetLabel(ctx, []string{"!r"}, second.ID, true)
	require.NoError(t, err)
	labelSpace := func(l Label) string { return "label:" + strconv.FormatInt(l.ID, 10) }

	row := inboxByID(t, s)["!r"]
	require.Equal(t, "", row.MutedBy)
	require.Equal(t, "", row.MutedByName)

	require.NoError(t, s.UpdateSpace(ctx, labelSpace(second), ptr(true), nil))
	row = inboxByID(t, s)["!r"]
	require.Equal(t, "label", row.MutedBy)
	require.Equal(t, "Second", row.MutedByName)
	require.False(t, row.Muted, "the chat's own mute is untouched")

	require.NoError(t, s.UpdateSpace(ctx, labelSpace(first), ptr(true), nil))
	require.Equal(t, "First", inboxByID(t, s)["!r"].MutedByName, "the first muted label, by label ID")

	require.NoError(t, s.UpdateSpace(ctx, "account:whatsapp", ptr(true), nil))
	row = inboxByID(t, s)["!r"]
	require.Equal(t, "account", row.MutedBy, "an account mute wins over a label mute")
	require.Equal(t, "WhatsApp", row.MutedByName)
	require.False(t, row.Muted)

	require.NoError(t, s.UpdateSpace(ctx, "account:whatsapp", ptr(false), nil))
	require.Equal(t, "label", inboxByID(t, s)["!r"].MutedBy)
}
