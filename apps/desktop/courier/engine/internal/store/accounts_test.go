// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestMigration9SubAccountsAndRoomSpaces(t *testing.T) {
	TestMigration10SubAccountsAndRoomSpaces(t)
}

func TestMigration10SubAccountsAndRoomSpaces(t *testing.T) {
	s, _ := openFixture(t, "m10.sql")
	ctx := context.Background()
	require.Equal(t, 10, SchemaVersion)
	require.Equal(t, SchemaVersion, userVersion(t, s))
	require.Equal(t, len(migrations), userVersion(t, s))

	var isSpace int
	var parentSpaceID string
	require.NoError(t, s.db.QueryRow(ctx, "SELECT is_space, parent_space_id FROM rooms WHERE room_id = '!r1:courier.local'").Scan(&isSpace, &parentSpaceID))
	require.Equal(t, 0, isSpace)
	require.Equal(t, "", parentSpaceID)

	require.Zero(t, count(t, s, "SELECT count(*) FROM sub_accounts"))
}

func TestSpacePortalsExcludedFromInboxAndSpaces(t *testing.T) {
	s, ctx := open(t), context.Background()
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!space:courier.local", Network: "slack", Name: "Acme Corp", LoginID: "slack-1"}))
	require.NoError(t, s.SetRoomSpace(ctx, "!space:courier.local", true, ""))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!chan:courier.local", Network: "slack", Name: "#general", LoginID: "slack-1"}))
	require.NoError(t, s.SetRoomSpace(ctx, "!chan:courier.local", false, "!space:courier.local"))

	rows, err := s.Inbox(ctx)
	require.NoError(t, err)
	require.Len(t, rows, 1)
	require.Equal(t, "!chan:courier.local", rows[0].ID)

	page, _, err := s.InboxPage(ctx, InboxQuery{Space: "inbox"})
	require.NoError(t, err)
	require.Len(t, page, 1)
	require.Equal(t, "!chan:courier.local", page[0].ID)

	spaces, err := s.Spaces(ctx, []string{"slack"})
	require.NoError(t, err)
	var inboxCount, slackCount int
	for _, sp := range spaces {
		switch sp.ID {
		case "inbox":
			inboxCount = sp.Chats
		case "account:slack":
			slackCount = sp.Chats
		}
	}
	require.Equal(t, 1, inboxCount)
	require.Equal(t, 1, slackCount)
}

func TestSubAccountFilteringAndBotSync(t *testing.T) {
	s, ctx := open(t), context.Background()

	// Create a Slack workspace space + 1 DM + 1 channel inside it.
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!ws:courier.local", Network: "slack", Name: "Acme Workspace", LoginID: "slack-1"}))
	require.NoError(t, s.SetRoomSpace(ctx, "!ws:courier.local", true, ""))
	require.NoError(t, s.UpsertSubAccount(ctx, SubAccount{
		Network: "slack", LoginID: "slack-1", SubID: "!ws:courier.local",
		Title: "Acme Workspace", AvatarURI: "mxc://courier.local/acme", Kind: "space", Enabled: true, ShowInInbox: "all",
	}))

	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!dm:courier.local", Network: "slack", Name: "Alice Example", IsDirect: true, LoginID: "slack-1"}))
	require.NoError(t, s.SetRoomSpace(ctx, "!dm:courier.local", false, "!ws:courier.local"))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!ch:courier.local", Network: "slack", Name: "#eng", IsDirect: false, LoginID: "slack-1"}))
	require.NoError(t, s.SetRoomSpace(ctx, "!ch:courier.local", false, "!ws:courier.local"))

	// ShowInInbox = "dms": only the DM appears in inbox; both appear in account:slack.
	dmsOnly := "dms"
	require.NoError(t, s.UpdateSubAccount(ctx, "slack", "slack-1", "!ws:courier.local", nil, &dmsOnly))

	inboxPage, _, err := s.InboxPage(ctx, InboxQuery{Space: "inbox"})
	require.NoError(t, err)
	require.Len(t, inboxPage, 1)
	require.Equal(t, "!dm:courier.local", inboxPage[0].ID)

	acctPage, _, err := s.InboxPage(ctx, InboxQuery{Space: "account:slack"})
	require.NoError(t, err)
	require.Len(t, acctPage, 2)

	// ShowInInbox = "none": neither appears in inbox; both still appear in account:slack.
	noneMode := "none"
	require.NoError(t, s.UpdateSubAccount(ctx, "slack", "slack-1", "!ws:courier.local", nil, &noneMode))
	inboxPage, _, err = s.InboxPage(ctx, InboxQuery{Space: "inbox"})
	require.NoError(t, err)
	require.Empty(t, inboxPage)
	acctPage, _, err = s.InboxPage(ctx, InboxQuery{Space: "account:slack"})
	require.NoError(t, err)
	require.Len(t, acctPage, 2)

	// Enabled = false: hidden from BOTH inbox and account:slack.
	disabled := false
	require.NoError(t, s.UpdateSubAccount(ctx, "slack", "slack-1", "!ws:courier.local", &disabled, nil))
	acctPage, _, err = s.InboxPage(ctx, InboxQuery{Space: "account:slack"})
	require.NoError(t, err)
	require.Empty(t, acctPage)

	// Invalid ShowInInbox is rejected with ErrBadValue and leaves stored row unchanged.
	bad := "invalid"
	require.ErrorIs(t, s.UpdateSubAccount(ctx, "slack", "slack-1", "!ws:courier.local", nil, &bad), ErrBadValue)

	// SyncBotSubAccounts discovers DM rooms on (telegram, tg-1) whose other member has profiles.is_bot = 1.
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!botdm:courier.local", Network: "telegram", Name: "AlertBot", IsDirect: true, LoginID: "tg-1"}))
	require.NoError(t, s.SetMember(ctx, "!botdm:courier.local", "@me:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.SetMember(ctx, "!botdm:courier.local", "@telegram_bot1:courier.local", json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, s.UpsertProfile(ctx, Profile{UserID: "@telegram_bot1:courier.local", DisplayName: "AlertBot", AvatarURI: "mxc://courier.local/bot"}))
	require.NoError(t, s.SetProfileExtraMeta(ctx, "@telegram_bot1:courier.local", nil, "", true))

	bots, err := s.SyncBotSubAccounts(ctx, "telegram", "tg-1")
	require.NoError(t, err)
	require.Len(t, bots, 1)
	require.Equal(t, SubAccount{
		Network: "telegram", LoginID: "tg-1", SubID: "!botdm:courier.local",
		Title: "AlertBot", AvatarURI: "mxc://courier.local/bot", Kind: "bot", Enabled: true, ShowInInbox: "all",
	}, bots[0])

	// Disabling the bot sub-account hides its DM from inbox and account:telegram.
	require.NoError(t, s.UpdateSubAccount(ctx, "telegram", "tg-1", "!botdm:courier.local", &disabled, nil))
	tgPage, _, err := s.InboxPage(ctx, InboxQuery{Space: "account:telegram"})
	require.NoError(t, err)
	require.Empty(t, tgPage)
}

func TestRemoveAccountDataSingleAndMultiAccount(t *testing.T) {
	s, ctx := open(t), context.Background()

	// Two accounts on telegram (tg-1 and tg-2) plus a shared room with login_id=''.
	require.NoError(t, s.SetLoginState(ctx, "telegram", "tg-1", json.RawMessage(`{"state_event":"CONNECTED"}`)))
	require.NoError(t, s.SetLoginState(ctx, "telegram", "tg-2", json.RawMessage(`{"state_event":"CONNECTED"}`)))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!tg1:courier.local", Network: "telegram", Name: "TG1 Chat", LoginID: "tg-1"}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!tg2:courier.local", Network: "telegram", Name: "TG2 Chat", LoginID: "tg-2"}))
	require.NoError(t, s.UpsertRoom(ctx, Room{ID: "!tgshared:courier.local", Network: "telegram", Name: "TG Shared", LoginID: ""}))
	_, err := s.InsertEvent(ctx, Event{
		RoomID: "!tg1:courier.local", EventID: "$ev-tg1", Sender: "@u1:courier.local",
		Type: "m.room.message", Content: json.RawMessage(`{"msgtype":"m.text","body":"secret tg1 text"}`), TS: time.Unix(100, 0),
	})
	require.NoError(t, err)
	require.NoError(t, s.UpsertSubAccount(ctx, SubAccount{
		Network: "telegram", LoginID: "tg-1", SubID: "!tg1:courier.local", Title: "TG1 Bot", Kind: "bot", Enabled: true, ShowInInbox: "all",
	}))

	// 1. Remove tg-1 with deleteChats=true while tg-2 remains: only tg-1 rooms, events, login_state, and sub_accounts are deleted.
	require.NoError(t, s.RemoveAccountData(ctx, "telegram", "tg-1", true))
	_, ok, err := s.GetRoom(ctx, "!tg1:courier.local")
	require.NoError(t, err)
	require.False(t, ok, "tg-1 room must be deleted")
	_, ok, err = s.GetRoom(ctx, "!tg2:courier.local")
	require.NoError(t, err)
	require.True(t, ok, "tg-2 room must remain")
	_, ok, err = s.GetRoom(ctx, "!tgshared:courier.local")
	require.NoError(t, err)
	require.True(t, ok, "shared room must remain while tg-2 is still linked")
	subs, err := s.SubAccounts(ctx, "telegram", "tg-1")
	require.NoError(t, err)
	require.Empty(t, subs)

	// 2. Remove tg-2 (the last login on telegram) with deleteChats=true: tg-2 room AND shared login_id='' room are deleted.
	require.NoError(t, s.RemoveAccountData(ctx, "telegram", "tg-2", true))
	_, ok, err = s.GetRoom(ctx, "!tg2:courier.local")
	require.NoError(t, err)
	require.False(t, ok)
	_, ok, err = s.GetRoom(ctx, "!tgshared:courier.local")
	require.NoError(t, err)
	require.False(t, ok, "shared room must be deleted when last account on network is removed with deleteChats=true")
}
