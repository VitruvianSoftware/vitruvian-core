// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"context"
	"encoding/json"
	"path/filepath"
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
	cfg := &bridgeconfig.BridgeConfig{CommandPrefix: "!gm", Permissions: bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin}}
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
		"bridgebot": "@gmessagesbot:courier.local",
		"channel":   map[string]any{"id": channel, "displayname": name, "fi.mau.receiver": repairLogin},
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
