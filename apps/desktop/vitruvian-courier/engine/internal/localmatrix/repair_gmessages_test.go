// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/bridgeconfig"
	"maunium.net/go/mautrix/bridgev2/commands"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/media"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

const (
	repairLogin = "google-account/1"
	// The rooms of the story: a contact's chat that was merged into the chat with no conversation ID, a second one,
	// the chat with no conversation ID, and a chat nothing happened to.
	roomContact   = "!contact:courier.local"
	roomSecond    = "!second:courier.local"
	roomEmpty     = "!empty:courier.local"
	roomUntouched = "!untouched:courier.local"
)

// The table mautrix-gmessages keeps phone numbers to portals in (without its foreign key to the login).
const mappingSchema = `CREATE TABLE gmessages_direct_conversation (
	bridge_id TEXT NOT NULL, login_id TEXT NOT NULL, phone_number TEXT NOT NULL, portal_id TEXT NOT NULL,
	last_message_ts BIGINT,
	PRIMARY KEY (bridge_id, login_id, phone_number),
	CONSTRAINT gmessages_direct_conversation_portal_id_unique UNIQUE (bridge_id, login_id, portal_id))`

type repairWorld struct {
	c   *Connector
	br  *bridgev2.Bridge
	net *fakenet.Network
	s   *store.Store
}

// newRepairWorld is a started Google Messages bridge over fakenet and a store, the bridge's database without the
// phone number table (made by the network connector, which fakenet is not).
func newRepairWorld(t *testing.T) *repairWorld {
	t.Helper()
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	t.Cleanup(func() { s.Close() })
	bdb, err := sqlite.Open(filepath.Join(dir, "gmessages.db"))
	require.NoError(t, err)
	c := New("gmessages", s, &media.Store{Dir: filepath.Join(dir, "media")})
	net := fakenet.New()
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix: "!gm", Permissions: bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
		Backfill: bridgeconfig.BackfillConfig{Enabled: true, MaxInitialMessages: 50, MaxCatchupMessages: 500},
	}
	br := bridgev2.NewBridge("gmessages", bdb, zerolog.Nop(), cfg, c, net,
		func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	require.NoError(t, br.Start(ctx))
	t.Cleanup(br.Stop)
	return &repairWorld{c: c, br: br, net: net, s: s}
}

func (w *repairWorld) withMappingTable(t *testing.T) {
	t.Helper()
	_, err := w.br.DB.Exec(context.Background(), mappingSchema)
	require.NoError(t, err)
}

// room puts a chat's room in the store the way a bridge made it: its bridge info (the chat it is for, and whose),
// its name and, for a one-to-one chat, its ghost (power level 50). tombstonedInto, when set, is the room it was
// merged into.
func (w *repairWorld) room(t *testing.T, roomID, name, channel, tombstonedInto string, ghosts ...string) {
	t.Helper()
	ctx := context.Background()
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: roomID, Network: "gmessages", Name: name, IsDirect: true}))
	set := func(typ, key string, content any) {
		raw, err := json.Marshal(content)
		require.NoError(t, err)
		_, err = w.s.SetState(ctx, roomID, typ, key, raw)
		require.NoError(t, err)
	}
	set("m.bridge", "gmessages", map[string]any{
		"bridgebot":            "@gmessagesbot:courier.local",
		"channel":              map[string]any{"id": channel, "displayname": name, "fi.mau.receiver": repairLogin},
		"com.beeper.room_type": "dm", "com.beeper.room_type.v2": "dm",
	})
	set("m.room.name", "", map[string]any{"name": name})
	set("m.room.avatar", "", map[string]any{"url": "mxc://courier.local/" + channel})
	users := map[string]int{"@gmessagesbot:courier.local": 9001}
	for _, g := range ghosts {
		users[string(ids.GhostMXID("gmessages", networkid.UserID(g)))] = 50
	}
	set("m.room.power_levels", "", map[string]any{"users": users})
	require.NoError(t, w.s.SetMember(ctx, roomID, string(ids.Me), json.RawMessage(`{"membership":"join"}`)))
	require.NoError(t, w.s.SetMember(ctx, roomID, "@gmessagesbot:courier.local", json.RawMessage(`{"membership":"join"}`)))
	if tombstonedInto != "" {
		set("m.room.tombstone", "", map[string]any{"body": "This room has been merged", "replacement_room": tombstonedInto})
	}
}

func (w *repairWorld) portal(t *testing.T, id, room string) networkid.PortalKey {
	t.Helper()
	key := networkid.PortalKey{ID: networkid.PortalID(id), Receiver: repairLogin}
	require.NoError(t, w.br.DB.Portal.Insert(context.Background(), &database.Portal{
		BridgeID: w.br.ID, PortalKey: key, MXID: idRoom(room), RoomType: database.RoomTypeDM, Name: "chat " + id,
		OtherUserID: "1.999", Metadata: map[string]any{},
	}))
	return key
}

func idRoom(room string) id.RoomID { return id.RoomID(room) }

func (w *repairWorld) mapping(t *testing.T, phone, portal string) {
	t.Helper()
	_, err := w.br.DB.Exec(context.Background(),
		"INSERT INTO gmessages_direct_conversation (bridge_id, login_id, phone_number, portal_id, last_message_ts) VALUES ($1,$2,$3,$4,$5)",
		w.br.ID, repairLogin, phone, portal, 1)
	require.NoError(t, err)
}

func (w *repairWorld) mappings(t *testing.T) map[string]string {
	t.Helper()
	rows, err := w.br.DB.Query(context.Background(), "SELECT phone_number, portal_id FROM gmessages_direct_conversation")
	require.NoError(t, err)
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var phone, portal string
		require.NoError(t, rows.Scan(&phone, &portal))
		out[phone] = portal
	}
	return out
}

func (w *repairWorld) portalMXID(t *testing.T, key string) (id.RoomID, bool) {
	t.Helper()
	p, err := w.br.DB.Portal.GetByKey(context.Background(), networkid.PortalKey{ID: networkid.PortalID(key), Receiver: repairLogin})
	require.NoError(t, err)
	if p == nil {
		return "", false
	}
	return p.MXID, true
}

// damaged is the state the bug left in a bridge: the chat with no conversation ID (its room, a message), and the
// chats it swallowed (their portals gone, their rooms tombstoned into it, their phone numbers still mapped to them),
// beside a chat that was never touched. The 5th phone number maps to a chat with no room at all.
func (w *repairWorld) damaged(t *testing.T) {
	t.Helper()
	ctx := context.Background()
	w.withMappingTable(t)
	w.room(t, roomEmpty, "Mixed up", "1.", "", "1.137", "1.139")
	w.room(t, roomContact, "A Contact", "1.81", roomEmpty, "1.137")
	w.room(t, roomSecond, "Short Code", "1.367", roomEmpty, "1.353")
	w.room(t, roomUntouched, "Untouched", "1.99", "", "1.150")
	emptyKey := w.portal(t, "1.", roomEmpty)
	w.portal(t, "1.99", roomUntouched)
	require.NoError(t, w.br.DB.Ghost.Insert(ctx, &database.Ghost{BridgeID: w.br.ID, ID: "1.2", Metadata: map[string]any{}}))
	require.NoError(t, w.br.DB.Message.Insert(ctx, &database.Message{
		BridgeID: w.br.ID, ID: "1.", MXID: "$mixed", Room: emptyKey, SenderID: "1.2", SenderMXID: "@x:courier.local",
		Timestamp: time.Unix(10, 0), Metadata: map[string]any{},
	}))
	w.mapping(t, "+15550000081", "1.81")
	w.mapping(t, "73889", "1.367")
	w.mapping(t, "652056", "1.363")
	w.mapping(t, "+15550000099", "1.99")
	w.mapping(t, "31061", "1.")
}

// The whole story, on a synthetic copy of what it left: the chat with no conversation ID goes with its room and its
// message; the two chats whose rooms were tombstoned are portals again, on those rooms, with the tombstones gone; the
// mapping to a chat that has no room is dropped, and so is the one to the chat with no ID; the untouched chat and its
// mapping stay. A second run finds nothing to do.
func TestRepairRestoresTheChatsTheEmptyIDChatSwallowed(t *testing.T) {
	w := newRepairWorld(t)
	ctx := context.Background()
	w.damaged(t)

	restored, err := w.c.doRepairGoogleMessages(ctx)
	require.NoError(t, err)

	_, hasEmpty := w.portalMXID(t, "1.")
	require.False(t, hasEmpty, "the chat with no conversation ID is gone")
	n, err := w.br.DB.Message.CountMessagesInPortal(ctx, networkid.PortalKey{ID: "1.", Receiver: repairLogin})
	require.NoError(t, err)
	require.Zero(t, n, "and its messages")
	_, ok, err := w.s.GetRoom(ctx, roomEmpty)
	require.NoError(t, err)
	require.False(t, ok, "and its room: nothing is left that pretends to be a real chat")

	room, ok := w.portalMXID(t, "1.81")
	require.True(t, ok, "the contact's chat is back")
	require.Equal(t, id.RoomID(roomContact), room, "on the room it had")
	room, ok = w.portalMXID(t, "1.367")
	require.True(t, ok)
	require.Equal(t, id.RoomID(roomSecond), room)
	for _, r := range []string{roomContact, roomSecond} {
		tomb, err := w.s.RoomIsTombstoned(ctx, r)
		require.NoError(t, err)
		require.False(t, tomb, "the tombstone is off %s", r)
		_, ok, err := w.s.GetRoom(ctx, r)
		require.NoError(t, err)
		require.True(t, ok, "its history is still there")
	}
	back, err := w.br.DB.Portal.GetByKey(ctx, networkid.PortalKey{ID: "1.81", Receiver: repairLogin})
	require.NoError(t, err)
	require.Equal(t, "A Contact", back.Name)
	require.Equal(t, database.RoomTypeDM, back.RoomType)
	require.Equal(t, networkid.UserID("1.137"), back.OtherUserID, "the contact's ghost, from the room's own power levels")
	require.Equal(t, id.ContentURIString("mxc://courier.local/1.81"), back.AvatarMXC)

	require.Equal(t, map[string]string{"+15550000081": "1.81", "73889": "1.367", "+15550000099": "1.99"}, w.mappings(t),
		"the mapping to a chat with no room, and the one to the chat with no ID, are dropped")
	untouched, ok := w.portalMXID(t, "1.99")
	require.True(t, ok)
	require.Equal(t, id.RoomID(roomUntouched), untouched)

	require.ElementsMatch(t, []restoredChat{{ID: "1.81", Receiver: repairLogin}, {ID: "1.367", Receiver: repairLogin}}, restored,
		"the restored chats wait for a resync")

	again, err := w.c.doRepairGoogleMessages(ctx)
	require.NoError(t, err)
	require.Empty(t, again, "a second run is a no-op")
	require.Len(t, w.mappings(t), 3)
}

// A start before the network connector made its tables has no mapping to repair, but the chat with no conversation ID
// still goes. And a bridge with nothing wrong is left alone.
func TestRepairWithoutTheMappingTableAndWithoutDamage(t *testing.T) {
	ctx := context.Background()
	t.Run("no table", func(t *testing.T) {
		w := newRepairWorld(t)
		w.room(t, roomEmpty, "Mixed up", "1.", "")
		w.portal(t, "1.", roomEmpty)
		restored, err := w.c.doRepairGoogleMessages(ctx)
		require.NoError(t, err)
		require.Empty(t, restored)
		_, has := w.portalMXID(t, "1.")
		require.False(t, has)
	})
	t.Run("nothing wrong", func(t *testing.T) {
		w := newRepairWorld(t)
		w.withMappingTable(t)
		w.room(t, roomUntouched, "Untouched", "1.99", "", "1.150")
		w.portal(t, "1.99", roomUntouched)
		w.mapping(t, "+15550000099", "1.99")
		restored, err := w.c.doRepairGoogleMessages(ctx)
		require.NoError(t, err)
		require.Empty(t, restored)
		require.Equal(t, map[string]string{"+15550000099": "1.99"}, w.mappings(t))
		_, has := w.portalMXID(t, "1.99")
		require.True(t, has)
	})
}

// Only another network's start is not ours to repair, and a room another portal already uses is never taken over.
func TestRepairGuards(t *testing.T) {
	ctx := context.Background()
	t.Run("another network", func(t *testing.T) {
		c := newNetworkConnector(t, "whatsapp")
		c.repairGoogleMessages(ctx) // returns at once: no bridge and not its network
	})
	t.Run("a room that has a portal", func(t *testing.T) {
		w := newRepairWorld(t)
		w.withMappingTable(t)
		w.room(t, roomEmpty, "Mixed up", "1.", "")
		w.room(t, roomContact, "A Contact", "1.81", roomEmpty, "1.137")
		w.portal(t, "1.77", roomContact) // another chat holds the tombstoned room
		w.mapping(t, "+15550000081", "1.81")
		restored, err := w.c.doRepairGoogleMessages(ctx)
		require.NoError(t, err)
		require.Empty(t, restored)
		require.Empty(t, w.mappings(t), "no room to give back: the mapping goes")
		_, has := w.portalMXID(t, "1.81")
		require.False(t, has)
	})
	t.Run("a room that is not tombstoned", func(t *testing.T) {
		w := newRepairWorld(t)
		w.withMappingTable(t)
		w.room(t, roomEmpty, "Mixed up", "1.", "")
		w.room(t, roomContact, "A Contact", "1.81", "", "1.137") // never merged: not ours to give back
		w.mapping(t, "+15550000081", "1.81")
		restored, err := w.c.doRepairGoogleMessages(ctx)
		require.NoError(t, err)
		require.Empty(t, restored)
		require.Empty(t, w.mappings(t))
	})
	t.Run("another login's room", func(t *testing.T) {
		w := newRepairWorld(t)
		w.withMappingTable(t)
		w.room(t, roomEmpty, "Mixed up", "1.", "")
		w.room(t, roomContact, "A Contact", "1.81", roomEmpty, "1.137")
		_, err := w.s.SetState(ctx, roomContact, "m.bridge", "gmessages",
			json.RawMessage(`{"channel":{"id":"1.81","fi.mau.receiver":"someone-else"}}`))
		require.NoError(t, err)
		w.mapping(t, "+15550000081", "1.81")
		restored, err := w.c.doRepairGoogleMessages(ctx)
		require.NoError(t, err)
		require.Empty(t, restored)
	})
}

// A start that stopped between making a restored portal's row and taking the tombstone off its room is finished by
// the next one.
func TestRepairFinishesARestoreThatStoppedHalfway(t *testing.T) {
	w := newRepairWorld(t)
	ctx := context.Background()
	w.withMappingTable(t)
	w.room(t, roomEmpty, "Mixed up", "1.", "")
	w.room(t, roomContact, "A Contact", "1.81", roomEmpty, "1.137")
	w.portal(t, "1.81", roomContact)
	w.mapping(t, "+15550000081", "1.81")
	tomb, err := w.s.RoomIsTombstoned(ctx, roomContact)
	require.NoError(t, err)
	require.True(t, tomb)

	restored, err := w.c.doRepairGoogleMessages(ctx)
	require.NoError(t, err)
	require.Empty(t, restored, "the portal is there: nothing to restore")
	tomb, err = w.s.RoomIsTombstoned(ctx, roomContact)
	require.NoError(t, err)
	require.False(t, tomb, "but the room of a live chat is no tombstone")
}

// The portal's resync, queued once its login is connected, brings the contact's ghost back into the restored room and
// asks the network for the chat's latest messages; a chat waits in the list until then, and leaves it once queued.
func TestRestoredChatIsResyncedOnceItsLoginIsConnected(t *testing.T) {
	prevPoll, prevGiveUp := resyncPollInterval, resyncGiveUpAfter
	resyncPollInterval, resyncGiveUpAfter = 10*time.Millisecond, 30*time.Second
	t.Cleanup(func() { resyncPollInterval, resyncGiveUpAfter = prevPoll, prevGiveUp })

	w := newRepairWorld(t)
	ctx := context.Background()
	w.damaged(t)
	login, err := w.net.LoginAs(ctx, w.br, repairLogin, "Me")
	require.NoError(t, err)
	name := "A Contact"
	direct := true
	w.net.SetChat("1.81", fakenet.Chat{Name: &name, Direct: &direct, Members: []string{"1.137"}})
	w.net.SetChat("1.367", fakenet.Chat{Name: &name, Direct: &direct, Members: []string{"1.353"}})

	restored, err := w.c.doRepairGoogleMessages(ctx)
	require.NoError(t, err)
	w.c.addPendingResyncs(ctx, restored)
	require.Len(t, w.c.pendingResyncs(ctx), 2)

	ghost := string(ids.GhostMXID("gmessages", "1.137"))
	members, err := w.s.Members(ctx, roomContact)
	require.NoError(t, err)
	require.NotContains(t, members, ghost, "the ghost left with the tombstone")

	done := make(chan struct{})
	go func() { w.c.resyncRestoredChats(w.br.BackgroundCtx); close(done) }()
	time.Sleep(100 * time.Millisecond)
	require.Len(t, w.c.pendingResyncs(ctx), 2, "the login is not connected yet: the chats wait")

	login.BridgeState.Send(status.BridgeState{StateEvent: status.StateConnected})
	require.Eventually(t, func() bool {
		m, err := w.s.Members(ctx, roomContact)
		_, back := m[ghost]
		return err == nil && back
	}, 10*time.Second, 20*time.Millisecond, "the contact's ghost is back in the room")
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("the resync loop did not end once every chat was queued")
	}
	require.Empty(t, w.c.pendingResyncs(ctx), "queued chats leave the list")
}

// The repair runs as the bridge starts (Connector.Start, before any login is loaded), and what it restored is
// remembered, in the bridge's own database, until its resync is queued: a restart in between does not lose it.
func TestStartRepairsAndRemembersTheRestoredChats(t *testing.T) {
	w := newRepairWorld(t)
	ctx := context.Background()
	w.damaged(t)

	require.NoError(t, w.c.Start(ctx))

	_, has := w.portalMXID(t, "1.")
	require.False(t, has)
	_, has = w.portalMXID(t, "1.81")
	require.True(t, has)
	require.ElementsMatch(t, []restoredChat{{ID: "1.81", Receiver: repairLogin}, {ID: "1.367", Receiver: repairLogin}}, w.c.pendingResyncs(ctx))
	require.NotEmpty(t, w.br.DB.KV.Get(ctx, repairResyncKey))

	require.NoError(t, w.c.Start(ctx)) // the next start: nothing more to repair, the list is as it was
	require.Len(t, w.c.pendingResyncs(ctx), 2)
}

// ghost puts a ghost in the bridge's database, with the phone number the bridge keeps on it.
func (w *repairWorld) ghost(t *testing.T, id, phone string) {
	t.Helper()
	require.NoError(t, w.br.DB.Ghost.Insert(context.Background(), &database.Ghost{
		BridgeID: w.br.ID, ID: networkid.UserID(id), Metadata: map[string]any{"phone": phone},
	}))
}

// A start that stopped between the mapping's move to the contact's new conversation ID and the chat's own move leaves
// a mapping to a chat that has no row, or a row with no room, with the contact's old room (tombstoned, no portal, no
// mapping) still in the store. The repair gives the contact's chat back on that room and points the mapping at it,
// instead of dropping the mapping. The room of another contact is not taken.
func TestRepairRestoresOntoTheOldRoomWhenTheMappingAlreadyMoved(t *testing.T) {
	const phone = "+15550000081"
	setup := func(t *testing.T) *repairWorld {
		w := newRepairWorld(t)
		w.withMappingTable(t)
		w.room(t, roomEmpty, "Mixed up", "1.", "")
		w.room(t, roomContact, "A Contact", "1.81", roomEmpty, "1.137")
		w.room(t, roomSecond, "Someone Else", "1.55", roomEmpty, "1.138")
		w.ghost(t, "1.137", phone)
		w.ghost(t, "1.138", "+15550000055")
		w.mapping(t, phone, "1.90") // moved to the contact's new conversation
		return w
	}
	check := func(t *testing.T, w *repairWorld) {
		ctx := context.Background()
		restored, err := w.c.doRepairGoogleMessages(ctx)
		require.NoError(t, err)
		require.Equal(t, []restoredChat{{ID: "1.81", Receiver: repairLogin}}, restored)
		room, ok := w.portalMXID(t, "1.81")
		require.True(t, ok)
		require.Equal(t, id.RoomID(roomContact), room, "the contact's chat is back on its old room")
		_, newOne := w.portalMXID(t, "1.90")
		require.False(t, newOne, "nothing is left at the new ID: the next sync of the conversation moves the chat there")
		require.Equal(t, map[string]string{phone: "1.81"}, w.mappings(t))
		tomb, err := w.s.RoomIsTombstoned(ctx, roomContact)
		require.NoError(t, err)
		require.False(t, tomb)
		tomb, err = w.s.RoomIsTombstoned(ctx, roomSecond)
		require.NoError(t, err)
		require.True(t, tomb, "another contact's old room is left as it was")
		again, err := w.c.doRepairGoogleMessages(ctx)
		require.NoError(t, err)
		require.Empty(t, again, "a second run is a no-op")
		require.Equal(t, map[string]string{phone: "1.81"}, w.mappings(t))
	}
	t.Run("the new chat has no row", func(t *testing.T) { check(t, setup(t)) })
	t.Run("the new chat has a row with no room", func(t *testing.T) {
		w := setup(t)
		w.portal(t, "1.90", "")
		check(t, w)
	})
	t.Run("no old room: a row with no room and its mapping are left", func(t *testing.T) {
		w := newRepairWorld(t)
		w.withMappingTable(t)
		w.portal(t, "1.90", "")
		w.mapping(t, phone, "1.90")
		restored, err := w.c.doRepairGoogleMessages(context.Background())
		require.NoError(t, err)
		require.Empty(t, restored)
		require.Equal(t, map[string]string{phone: "1.90"}, w.mappings(t), "a chat not made yet is not a chat that is gone")
		_, has := w.portalMXID(t, "1.90")
		require.True(t, has)
	})
}

// Only a tombstone the bug left is taken off: one that points to the room of a chat with no conversation ID, or to no
// room. A tombstone that points to a real room is a real merge of two chats, in the room of a chat that is alive (the
// mapping table lists it) as well as in a room that would be given back.
func TestRepairLeavesRealMergesAlone(t *testing.T) {
	const realRoom = "!real:courier.local"
	ctx := context.Background()
	w := newRepairWorld(t)
	w.withMappingTable(t)
	w.room(t, roomEmpty, "Mixed up", "1.", "")
	w.room(t, realRoom, "The Chat Merged Into", "1.99", "", "1.150")
	w.portal(t, "1.99", realRoom)
	w.mapping(t, "+15550000099", "1.99")
	// a live chat whose room was merged into a real room (not ours); a live chat whose tombstone points to nothing and
	// one that points to the catch-all room (ours).
	w.room(t, roomContact, "Merged", "1.81", realRoom, "1.137")
	w.portal(t, "1.81", roomContact)
	w.mapping(t, "+15550000081", "1.81")
	w.room(t, roomSecond, "Pointing Nowhere", "1.82", "", "1.138")
	_, err := w.s.SetState(ctx, roomSecond, "m.room.tombstone", "", json.RawMessage(`{"body":"merged"}`))
	require.NoError(t, err)
	w.portal(t, "1.82", roomSecond)
	w.mapping(t, "+15550000082", "1.82")
	w.room(t, roomUntouched, "Left By The Bug", "1.83", roomEmpty, "1.139")
	w.portal(t, "1.83", roomUntouched)
	w.mapping(t, "+15550000083", "1.83")
	// a chat with no portal whose old room was merged into a real room: not given back, so its mapping goes
	w.room(t, "!gone:courier.local", "Gone", "1.84", realRoom, "1.140")
	w.mapping(t, "+15550000084", "1.84")

	restored, err := w.c.doRepairGoogleMessages(ctx)
	require.NoError(t, err)
	require.Empty(t, restored)
	for room, want := range map[string]bool{roomContact: true, roomSecond: false, roomUntouched: false, "!gone:courier.local": true} {
		tomb, err := w.s.RoomIsTombstoned(ctx, room)
		require.NoError(t, err)
		require.Equal(t, want, tomb, "the tombstone of %s", room)
	}
	_, has := w.portalMXID(t, "1.84")
	require.False(t, has)
	require.NotContains(t, w.mappings(t), "+15550000084", "no room to give back: the mapping goes")
}

// historyWorld is a damaged bridge whose contact's room (the chat 1.81) already holds three messages, an account
// whose client can be backfilled from a phone that has those three and three newer ones, and the chats the repair
// restored. The room's events aren't the bridge's event IDs (so a re-send would show as a duplicate), except the
// newest one, which is: messages the bridge made have its IDs, and a reply to a message is a reply to its event.
type historyWorld struct {
	*repairWorld
	login    *bridgev2.UserLogin
	client   *backfillClient
	restored []restoredChat
	contact  restoredChat
}

func newHistoryWorld(t *testing.T) *historyWorld {
	t.Helper()
	w := newRepairWorld(t)
	ctx := context.Background()
	w.damaged(t)
	at := func(sec int64) time.Time { return time.Unix(sec, 0) }
	newestEvent := string(ids.EventID(roomContact, networkid.PortalKey{ID: "1.81", Receiver: repairLogin}, "1.m3", ""))
	for i, sec := range []int64{1000, 2000, 3000} {
		eventID := fmt.Sprintf("$old%d", i+1)
		if i == 2 {
			eventID = newestEvent
		}
		_, err := w.s.InsertEvent(ctx, store.Event{
			RoomID: roomContact, EventID: eventID, Sender: string(ids.GhostMXID("gmessages", "1.137")),
			Type: "m.room.message", Content: json.RawMessage(fmt.Sprintf(`{"msgtype":"m.text","body":"old %d"}`, i+1)), TS: at(sec),
		})
		require.NoError(t, err)
	}
	login, err := w.net.LoginAs(ctx, w.br, repairLogin, "Me")
	require.NoError(t, err)
	name, direct := "A Contact", true
	w.net.SetChat("1.81", fakenet.Chat{Name: &name, Direct: &direct, Members: []string{"1.137"}})
	w.net.SetChat("1.367", fakenet.Chat{Name: &name, Direct: &direct, Members: []string{"1.353"}})
	msg := func(id, body string, sec int64, replyTo networkid.MessageID) *bridgev2.BackfillMessage {
		m := &bridgev2.BackfillMessage{
			ID: networkid.MessageID(id), Timestamp: at(sec), Sender: bridgev2.EventSender{Sender: "1.137"},
			ConvertedMessage: &bridgev2.ConvertedMessage{Parts: []*bridgev2.ConvertedMessagePart{{
				Type: event.EventMessage, Content: &event.MessageEventContent{MsgType: event.MsgText, Body: body},
			}}},
		}
		if replyTo != "" {
			m.ReplyTo = &networkid.MessageOptionalPartID{MessageID: replyTo}
		}
		return m
	}
	// What the phone has: the three messages the room holds, and three that came after (the first replies to the
	// newest of the three).
	client := &backfillClient{NetworkAPI: login.Client, messages: []*bridgev2.BackfillMessage{
		msg("1.m1", "old 1", 1000, ""), msg("1.m2", "old 2", 2000, ""), msg("1.m3", "old 3", 3000, ""),
		msg("1.m4", "new 4", 4000, "1.m3"), msg("1.m5", "new 5", 5000, ""), msg("1.m6", "new 6", 6000, ""),
	}}
	login.Client = client
	login.BridgeState.Send(status.BridgeState{StateEvent: status.StateConnected})

	restored, err := w.c.doRepairGoogleMessages(ctx)
	require.NoError(t, err)
	h := &historyWorld{repairWorld: w, login: login, client: client, restored: restored}
	for _, r := range restored {
		if r.ID == "1.81" {
			h.contact = r
		}
	}
	require.Equal(t, int64(3000*1000), h.contact.LastTS, "the restore notes the room's newest message")
	w.c.addPendingResyncs(ctx, restored)
	return h
}

// resync runs the resync loop until the pending chats are queued.
func (h *historyWorld) resync(t *testing.T) {
	t.Helper()
	done := make(chan struct{})
	go func() { h.c.resyncRestoredChats(h.br.BackgroundCtx); close(done) }()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("the resync loop did not end")
	}
}

// replyTarget is the event a message of a room replies to ("" if it replies to none).
func replyTarget(t *testing.T, s *store.Store, room, body string) string {
	t.Helper()
	evs, err := s.Events(context.Background(), room, 100)
	require.NoError(t, err)
	for _, e := range evs {
		var c struct {
			Body      string `json:"body"`
			RelatesTo struct {
				InReplyTo struct {
					EventID string `json:"event_id"`
				} `json:"m.in_reply_to"`
			} `json:"m.relates_to"`
		}
		if json.Unmarshal(e.Content, &c) == nil && c.Body == body {
			return c.RelatesTo.InReplyTo.EventID
		}
	}
	return ""
}

func (h *historyWorld) contactFetches() []bridgev2.FetchMessagesParams {
	var out []bridgev2.FetchMessagesParams
	for _, c := range h.client.fetches() {
		if c.Portal.ID == "1.81" {
			out = append(out, c)
		}
	}
	return out
}

// The room already holds the chat's history. A restored chat has no message rows in the bridge, so a backfill would
// fetch the phone's latest messages and send them again: the room would show them twice. The messages the room holds
// are not sent again, the ones newer than its newest event (what arrived while the chat was merged into the chat with
// no conversation ID) are, and a reply to a message the room holds resolves to that message's event: the message the
// backfill starts from is the phone's own, by its real ID.
func TestRestoredChatGetsOnlyMessagesNewerThanItsRoomHolds(t *testing.T) {
	fastResync(t)
	h := newHistoryWorld(t)
	ctx := context.Background()
	h.resync(t)

	require.Eventually(t, func() bool { return bodiesIn(t, h.s, roomContact)["new 6"] > 0 }, 10*time.Second, 20*time.Millisecond,
		"the messages newer than the room's history arrive")
	bodies := bodiesIn(t, h.s, roomContact)
	require.Equal(t, map[string]int{"old 1": 1, "old 2": 1, "old 3": 1, "new 4": 1, "new 5": 1, "new 6": 1}, bodies,
		"each message once: none of the room's history is sent again")
	anchor, err := h.br.DB.Message.GetFirstPartByID(ctx, repairLogin, "1.m3")
	require.NoError(t, err)
	require.NotNil(t, anchor, "the newest message the room held is a message of the chat, under the phone's own ID")
	newestEvent := string(ids.EventID(roomContact, networkid.PortalKey{ID: "1.81", Receiver: repairLogin}, "1.m3", ""))
	require.Equal(t, newestEvent, string(anchor.MXID))
	require.Equal(t, newestEvent, replyTarget(t, h.s, roomContact, "new 4"), "a reply to it resolves to its event")
	calls := h.contactFetches()
	require.Len(t, calls, 2, "one fetch to find the anchor, one to backfill from it")
	require.Nil(t, calls[0].AnchorMessage)
	require.Equal(t, networkid.MessageID("1.m3"), calls[1].AnchorMessage.ID, "the backfill went forward from it")

	// Again (the bridge restarted before it noted the chat done): nothing is sent twice.
	require.NoError(t, h.c.resyncOne(ctx, h.login, h.contact))
	time.Sleep(200 * time.Millisecond)
	require.Equal(t, bodies, bodiesIn(t, h.s, roomContact), "a second resync changes nothing")
}

// A message comes in live after the chat is restored and before its resync, so it is the chat's last message and the
// backfill would start after it, leaving out what the room is missing from before it. That is sent as messages instead:
// the gap fills, nothing the room holds is sent again, and the live message is there once.
func TestRestoredChatFillsTheGapBehindALiveMessage(t *testing.T) {
	fastResync(t)
	h := newHistoryWorld(t)
	ctx := context.Background()
	h.net.Incoming(h.login, "1.81", "1.137", "1.live", "live message")
	require.Eventually(t, func() bool { return bodiesIn(t, h.s, roomContact)["live message"] > 0 }, 10*time.Second, 20*time.Millisecond)
	live, err := h.br.DB.Message.GetFirstPartByID(ctx, repairLogin, "1.live")
	require.NoError(t, err)
	require.NotNil(t, live, "the live message is the chat's last message")

	h.resync(t)
	require.Eventually(t, func() bool { return bodiesIn(t, h.s, roomContact)["new 6"] > 0 }, 10*time.Second, 20*time.Millisecond,
		"the older messages the room is missing arrive")
	bodies := bodiesIn(t, h.s, roomContact)
	require.Equal(t, map[string]int{"old 1": 1, "old 2": 1, "old 3": 1, "new 4": 1, "new 5": 1, "new 6": 1, "live message": 1}, bodies,
		"each once, the room's history and the live message included")
	newestEvent := string(ids.EventID(roomContact, networkid.PortalKey{ID: "1.81", Receiver: repairLogin}, "1.m3", ""))
	require.Equal(t, newestEvent, replyTarget(t, h.s, roomContact, "new 4"))

	require.NoError(t, h.c.resyncOne(ctx, h.login, h.contact))
	time.Sleep(200 * time.Millisecond)
	require.Equal(t, bodies, bodiesIn(t, h.s, roomContact), "and a second resync changes nothing")
}

// fastResync makes the resync loop's clocks short for a test.
func fastResync(t *testing.T) {
	t.Helper()
	poll, giveUp, first, longest := resyncPollInterval, resyncGiveUpAfter, resyncRetryInitial, resyncRetryMax
	resyncPollInterval, resyncGiveUpAfter, resyncRetryInitial, resyncRetryMax = 10*time.Millisecond, 30*time.Second, 20*time.Millisecond, 160*time.Millisecond
	t.Cleanup(func() {
		resyncPollInterval, resyncGiveUpAfter, resyncRetryInitial, resyncRetryMax = poll, giveUp, first, longest
	})
}

// A resync that fails (the phone doesn't answer) is tried again after 20 ms, then 40, 80 and 160 (the longest), not on
// every poll; it gives up when the time is up, and the chat stays pending for the next start.
func TestRestoredChatResyncBacksOffAndGivesUp(t *testing.T) {
	fastResync(t)
	resyncPollInterval, resyncGiveUpAfter = 5*time.Millisecond, time.Second
	h := newHistoryWorld(t)
	h.client.fail = errors.New("the phone is off")

	start := time.Now()
	h.resync(t)
	require.GreaterOrEqual(t, time.Since(start), 900*time.Millisecond, "it kept trying until the time was up")
	contact := h.client.contactTimes()
	require.GreaterOrEqual(t, len(contact), 5, "tried again and again")
	require.LessOrEqual(t, len(contact), 11, "but not on every 5 ms poll (that would be about 200)")
	for i, wait := range []time.Duration{20, 40, 80, 160, 160} {
		if i+1 < len(contact) {
			// A timer never fires early: each wait is at least the backoff's, allowing for the clock's granularity.
			require.GreaterOrEqual(t, contact[i+1].Sub(contact[i]), wait*time.Millisecond-2*time.Millisecond, "wait %d is at least %d ms", i+1, wait)
		}
	}
	require.Len(t, h.c.pendingResyncs(context.Background()), 2, "both chats are still waiting for the next start")
}

// backfillClient is a login client that can be backfilled from a phone that always has the same messages, as a real
// network sends the newest ones whatever the anchor is (bridgev2 cuts off what the anchor says it has).
type backfillClient struct {
	bridgev2.NetworkAPI
	messages []*bridgev2.BackfillMessage

	// fail, when set, is every fetch's error.
	fail error

	mu    sync.Mutex
	calls []bridgev2.FetchMessagesParams
	times []time.Time
}

func (b *backfillClient) FetchMessages(_ context.Context, p bridgev2.FetchMessagesParams) (*bridgev2.FetchMessagesResponse, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.calls = append(b.calls, p)
	b.times = append(b.times, time.Now())
	if b.fail != nil {
		return nil, b.fail
	}
	if p.Portal.ID != "1.81" { // the phone's messages are the contact's chat's: a message ID is the account's, in one chat
		return &bridgev2.FetchMessagesResponse{Forward: true}, nil
	}
	return &bridgev2.FetchMessagesResponse{Messages: append([]*bridgev2.BackfillMessage(nil), b.messages...), Forward: true}, nil
}

func (b *backfillClient) fetches() []bridgev2.FetchMessagesParams {
	b.mu.Lock()
	defer b.mu.Unlock()
	return append([]bridgev2.FetchMessagesParams(nil), b.calls...)
}

// contactTimes are the times of the fetches for the contact's chat.
func (b *backfillClient) contactTimes() []time.Time {
	b.mu.Lock()
	defer b.mu.Unlock()
	var out []time.Time
	for i, c := range b.calls {
		if c.Portal.ID == "1.81" {
			out = append(out, b.times[i])
		}
	}
	return out
}

// bodiesIn counts a room's message events by their text.
func bodiesIn(t *testing.T, s *store.Store, room string) map[string]int {
	t.Helper()
	evs, err := s.Events(context.Background(), room, 100)
	require.NoError(t, err)
	out := map[string]int{}
	for _, e := range evs {
		var c struct {
			Body string `json:"body"`
		}
		if e.Type == "m.room.message" && json.Unmarshal(e.Content, &c) == nil && c.Body != "" {
			out[c.Body]++
		}
	}
	return out
}

// A number two contacts share, or a room that isn't surely a one-to-one chat, is not given back to the mapping that
// matches its phone number: the rooms and the mapping are left as they are.
func TestRepairLeavesRoomsItIsNotSureOfAlone(t *testing.T) {
	const phone = "+15550000081"
	ctx := context.Background()
	setup := func(t *testing.T) *repairWorld {
		w := newRepairWorld(t)
		w.withMappingTable(t)
		w.room(t, roomEmpty, "Mixed up", "1.", "")
		w.ghost(t, "1.137", phone)
		w.mapping(t, phone, "1.90")
		return w
	}
	check := func(t *testing.T, w *repairWorld, tombstoned ...string) {
		restored, err := w.c.doRepairGoogleMessages(ctx)
		require.NoError(t, err)
		require.Empty(t, restored)
		require.Equal(t, map[string]string{phone: "1.90"}, w.mappings(t), "the mapping is not dropped or moved")
		for _, room := range tombstoned {
			tomb, err := w.s.RoomIsTombstoned(ctx, room)
			require.NoError(t, err)
			require.True(t, tomb, "%s is left as it was", room)
		}
		for _, portal := range []string{"1.81", "1.82"} {
			_, has := w.portalMXID(t, portal)
			require.False(t, has, "no chat is made at %s", portal)
		}
	}
	t.Run("a number two contacts share", func(t *testing.T) {
		w := setup(t)
		w.room(t, roomContact, "First Contact", "1.81", roomEmpty, "1.137")
		w.room(t, roomSecond, "Second Contact", "1.82", roomEmpty, "1.138")
		w.ghost(t, "1.138", phone)
		check(t, w, roomContact, roomSecond)
	})
	t.Run("a group with one other member", func(t *testing.T) {
		w := setup(t)
		w.room(t, roomContact, "A Group", "1.81", roomEmpty, "1.137")
		w.setRoomType(t, roomContact, "group_dm")
		check(t, w, roomContact)
	})
	t.Run("a chat the store calls direct that the bridge named a group", func(t *testing.T) {
		w := setup(t)
		w.room(t, roomContact, "A Group", "1.81", roomEmpty, "1.137")
		w.setRoomType(t, roomContact, "group_dm")
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: roomContact, Network: "gmessages", Name: "A Group", IsDirect: true}))
		check(t, w, roomContact)
	})
	t.Run("a direct chat that has someone else in it", func(t *testing.T) {
		w := setup(t)
		w.room(t, roomContact, "A Contact", "1.81", roomEmpty, "1.137")
		require.NoError(t, w.s.SetMember(ctx, roomContact, "@someone:courier.local", json.RawMessage(`{"membership":"join"}`)))
		check(t, w, roomContact)
	})
	t.Run("a chat that is direct for the bridge but not for the store", func(t *testing.T) {
		w := setup(t)
		w.room(t, roomContact, "A Contact", "1.81", roomEmpty, "1.137")
		require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: roomContact, Network: "gmessages", Name: "A Contact", IsDirect: false}))
		check(t, w, roomContact)
	})
	t.Run("a group and a direct chat that share the number", func(t *testing.T) {
		w := setup(t)
		w.room(t, roomContact, "A Contact", "1.81", roomEmpty, "1.137")
		w.room(t, roomSecond, "A Group", "1.82", roomEmpty, "1.138")
		w.ghost(t, "1.138", phone)
		w.setRoomType(t, roomSecond, "group_dm")
		check(t, w, roomContact, roomSecond)
	})
}

// setRoomType says what kind of chat a room's bridge info names it, and the store whether it is direct.
func (w *repairWorld) setRoomType(t *testing.T, roomID, roomType string) {
	t.Helper()
	ctx := context.Background()
	raw, ok, err := w.s.GetState(ctx, roomID, "m.bridge", "gmessages")
	require.NoError(t, err)
	require.True(t, ok)
	var info map[string]any
	require.NoError(t, json.Unmarshal(raw, &info))
	info["com.beeper.room_type"], info["com.beeper.room_type.v2"] = roomType, roomType
	out, err := json.Marshal(info)
	require.NoError(t, err)
	_, err = w.s.SetState(ctx, roomID, "m.bridge", "gmessages", out)
	require.NoError(t, err)
	require.NoError(t, w.s.UpsertRoom(ctx, store.Room{ID: roomID, Network: "gmessages", IsDirect: roomType == "dm"}))
}
