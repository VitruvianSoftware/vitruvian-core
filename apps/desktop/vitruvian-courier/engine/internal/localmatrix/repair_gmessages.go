// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localmatrix

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"sync"
	"time"

	"github.com/rs/zerolog"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/bridgev2/simplevent"
	"maunium.net/go/mautrix/bridgev2/status"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/ids"
	"github.com/VitruvianSoftware/vitruvian-courier/engine/internal/store"
)

// This file repairs the chats Google Messages mixed up before mautrix-gmessages learned to route by the IDs Google
// nests (tools/go_deps/mautrix-gmessages-nested-conversation-ids.patch). What went wrong, in order:
//
//  1. Google sent some messages and conversation updates with their conversation ID empty. The bridge put every one
//     in a chat whose portal ID is just the login prefix ("1."), with the contact's ghost of whoever wrote last.
//  2. Its one-to-one deduplication saw a contact's phone number on that chat and moved the contact's real chat into
//     it. The real chat's portal row was deleted and its room tombstoned (the history stays in the store, the ghosts
//     leave); the update of the phone number's mapping (gmessages_direct_conversation) that should have followed
//     failed, so the mapping still names a portal that no longer exists.
//
// repairGoogleMessages undoes both, once, as the bridge starts and before any login is loaded (so the bridge reads
// the repaired mapping): the chat with no ID goes (its row, its messages, its room), and a mapping whose portal is
// gone gets its portal back on the room it had, or is dropped when there is no such room, for the next sync to make
// again. A restored chat is then synced from the phone once its login is connected (resyncRestoredChats): that
// brings the ghosts back and the messages that had no real place, which the nested-ID routing now delivers.
//
// It is idempotent (a second run finds nothing) and acts only on those exact conditions.

const (
	gmessagesNetwork = "gmessages"
	// gmessagesMappingTable is mautrix-gmessages' phone number to portal table. It is made when the network
	// connector starts, which is after the Matrix connector, so on the very first start it does not exist yet.
	gmessagesMappingTable = "gmessages_direct_conversation"
	// repairResyncKey is the bridge KV entry holding the restored chats still waiting for their resync.
	repairResyncKey database.Key = "courier_gmessages_repair_resync"
)

// emptyConversationPortalRE is a Google Messages portal ID with nothing after its login prefix.
var emptyConversationPortalRE = regexp.MustCompile(`^[0-9]+\.$`)

// Variables so a test can shorten them.
var (
	resyncPollInterval = 2 * time.Second
	resyncGiveUpAfter  = 30 * time.Minute
	// A resync that fails is tried again after resyncRetryInitial, then after twice as long each time, up to
	// resyncRetryMax (the phone may be off, or Google slow: asking every poll would be a flood).
	resyncRetryInitial = 2 * time.Second
	resyncRetryMax     = 5 * time.Minute
)

// restoredChat is a chat the repair put back, waiting for its resync.
type restoredChat struct {
	ID       networkid.PortalID    `json:"id"`
	Receiver networkid.UserLoginID `json:"receiver"`
	// LastTS is the time of the newest message its room already held when it was restored (Unix milliseconds):
	// the room has those events already, so the resync fetches only what is newer.
	LastTS int64 `json:"last_ts,omitempty"`
}

func (r restoredChat) sameChat(o restoredChat) bool { return r.ID == o.ID && r.Receiver == o.Receiver }

// repairMu serializes a repair's resync bookkeeping (the KV entry) between the bridge start and its resync loop.
var repairMu sync.Mutex

func (c *Connector) repairGoogleMessages(ctx context.Context) {
	if c.network != gmessagesNetwork || c.br == nil || c.br.DB == nil {
		return
	}
	restored, err := c.doRepairGoogleMessages(ctx)
	if err != nil {
		// Best effort: the bridge starts anyway, and the next start tries again.
		c.log.Warn().Err(err).Msg("failed to repair Google Messages chats that were mixed up")
	}
	if len(restored) > 0 {
		c.addPendingResyncs(ctx, restored)
	}
	if len(c.pendingResyncs(ctx)) > 0 {
		go c.resyncRestoredChats(c.br.BackgroundCtx)
	}
}

// doRepairGoogleMessages is the repair; it returns the chats it restored. The chat with no conversation ID goes last:
// its room is what the tombstones of the chats it swallowed point to, which is how they are told from a real merge,
// so everything that reads them comes first, and a start that stops halfway finds the same state again.
func (c *Connector) doRepairGoogleMessages(ctx context.Context) ([]restoredChat, error) {
	var restored []restoredChat
	var firstErr error
	keep := func(err error) {
		if err != nil && firstErr == nil {
			firstErr = err
		}
	}

	empty, err := c.emptyConversationPortals(ctx)
	keep(err)
	catchAll, err := c.catchAllRooms(ctx, empty)
	keep(err)

	hasMapping, err := c.hasTable(ctx, gmessagesMappingTable)
	if err != nil {
		return restored, errors.Join(firstErr, err)
	}
	if hasMapping {
		restored, err = c.repairMappings(ctx, catchAll, restored)
		keep(err)
		keep(c.liftTombstonesOfMappedChats(ctx, catchAll))
	}
	for _, p := range empty {
		keep(c.removeEmptyConversationPortal(ctx, p))
	}
	if hasMapping {
		// What pointed at the chats just removed has nothing left to point at.
		restored, err = c.repairMappings(ctx, catchAll, restored)
		keep(err)
	}
	return restored, firstErr
}

// repairMappings restores or drops each mapping that has no usable chat.
func (c *Connector) repairMappings(ctx context.Context, catchAll map[string]bool, restored []restoredChat) ([]restoredChat, error) {
	var firstErr error
	broken, err := c.brokenMappings(ctx)
	if err != nil {
		return restored, err
	}
	for _, m := range broken {
		chat, ok, err := c.restoreOrDropMapping(ctx, m, catchAll)
		if err != nil && firstErr == nil {
			firstErr = err
		}
		if ok {
			restored = append(restored, chat)
		}
	}
	return restored, firstErr
}

// catchAllRooms are the rooms of the chats with no conversation ID: those of the portals given, and any room of
// the store whose bridge info names such a chat. A tombstone pointing to one of them is what the bug left.
func (c *Connector) catchAllRooms(ctx context.Context, empty []*database.Portal) (map[string]bool, error) {
	out := map[string]bool{}
	for _, p := range empty {
		if p.MXID != "" {
			out[string(p.MXID)] = true
		}
	}
	rooms, err := c.store.ChannelRooms(ctx, c.network, "")
	if err != nil {
		return out, err
	}
	for _, r := range rooms {
		if emptyConversationPortalRE.MatchString(r.ChannelID) {
			out[r.RoomID] = true
		}
	}
	return out, nil
}

// liftable says a tombstone was left by the bug: it points to a chat with no conversation ID, or to nothing. Any
// other tombstone is a real merge of two chats, which is not ours to undo.
func liftable(replacement string, catchAll map[string]bool) bool {
	return replacement == "" || catchAll[replacement]
}

func (c *Connector) hasTable(ctx context.Context, name string) (bool, error) {
	var one int
	err := c.br.DB.QueryRow(ctx, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = $1", name).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

// emptyConversationPortals lists the bridge's portals whose ID is just a login prefix.
func (c *Connector) emptyConversationPortals(ctx context.Context) ([]*database.Portal, error) {
	rows, err := c.br.DB.Query(ctx, "SELECT id, receiver FROM portal WHERE bridge_id = $1 AND id LIKE '%.'", c.br.ID)
	if err != nil {
		return nil, err
	}
	var keys []networkid.PortalKey
	for rows.Next() {
		var key networkid.PortalKey
		if err := rows.Scan(&key.ID, &key.Receiver); err != nil {
			rows.Close()
			return nil, err
		}
		if emptyConversationPortalRE.MatchString(string(key.ID)) {
			keys = append(keys, key)
		}
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	out := make([]*database.Portal, 0, len(keys))
	for _, key := range keys {
		p, err := c.br.DB.Portal.GetByKey(ctx, key)
		if err != nil {
			return nil, err
		}
		if p != nil {
			out = append(out, p)
		}
	}
	return out, nil
}

// removeEmptyConversationPortal deletes a chat with no conversation ID: its room (a chat of mixed up messages that
// the right chats get again from the phone), then its messages and its row. In that order: a start that stops
// halfway then still finds the portal, and finishes.
func (c *Connector) removeEmptyConversationPortal(ctx context.Context, p *database.Portal) error {
	log := c.log.With().Str("portal_id", string(p.ID)).Logger()
	if p.MXID != "" {
		room, ok, err := c.store.GetRoom(ctx, string(p.MXID))
		if err != nil {
			return err
		}
		// Only this network's own room: never one of another bridge's, whatever the row says.
		if ok && room.Network == c.network {
			if err = c.store.DeleteRoom(ctx, string(p.MXID)); err != nil {
				return fmt.Errorf("retiring the room of the chat with no conversation ID: %w", err)
			}
		}
	}
	if err := c.br.DB.Message.DeleteInChunks(ctx, p.PortalKey); err != nil {
		return fmt.Errorf("deleting the messages of the chat with no conversation ID: %w", err)
	}
	if err := c.br.DB.Portal.Delete(ctx, p.PortalKey); err != nil {
		return fmt.Errorf("deleting the chat with no conversation ID: %w", err)
	}
	log.Warn().Msg("removed a Google Messages chat with no conversation ID (events Google sent without their IDs were mixed into it)")
	return nil
}

// dmMapping is one row of the phone number to portal table. hasRow says its portal has a row (without a room).
type dmMapping struct {
	login         networkid.UserLoginID
	phone         string
	portal        networkid.PortalID
	lastMessageTS sql.NullInt64
	hasRow        bool
}

// brokenMappings lists the mappings whose portal has no row, or a row with no room.
func (c *Connector) brokenMappings(ctx context.Context) ([]dmMapping, error) {
	rows, err := c.br.DB.Query(ctx, `SELECT dc.login_id, dc.phone_number, dc.portal_id, dc.last_message_ts, p.id IS NOT NULL
		FROM `+gmessagesMappingTable+` dc
		LEFT JOIN portal p ON p.bridge_id = dc.bridge_id AND p.id = dc.portal_id AND p.receiver = dc.login_id
		WHERE dc.bridge_id = $1 AND (p.id IS NULL OR p.mxid IS NULL OR p.mxid = '')`, c.br.ID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []dmMapping
	for rows.Next() {
		var m dmMapping
		if err := rows.Scan(&m.login, &m.phone, &m.portal, &m.lastMessageTS, &m.hasRow); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (c *Connector) dropMapping(ctx context.Context, m dmMapping) error {
	_, err := c.br.DB.Exec(ctx, "DELETE FROM "+gmessagesMappingTable+
		" WHERE bridge_id = $1 AND login_id = $2 AND phone_number = $3 AND portal_id = $4", c.br.ID, m.login, m.phone, m.portal)
	return err
}

// restoreOrDropMapping gives a mapping with no usable chat its chat back, on the room it had. That room is one the
// bug tombstoned (liftable) that nobody else uses, found two ways: it was made for the mapped chat itself (the chat's
// row was deleted and the mapping never moved), or, when the mapping had already moved to a new conversation ID that
// never got its portal (a start that stopped between the two), it is the room of an old chat of the same contact
// that has no portal and no mapping. Otherwise the mapping goes, and the next sync makes the chat and its mapping
// again; but only when its chat has no row: a row with no room yet is a chat that isn't made yet, and stays. The
// phone number and the chat's name are never logged.
func (c *Connector) restoreOrDropMapping(ctx context.Context, m dmMapping, catchAll map[string]bool) (restoredChat, bool, error) {
	log := c.log.With().Str("portal_id", string(m.portal)).Logger()
	if emptyConversationPortalRE.MatchString(string(m.portal)) {
		log.Warn().Msg("dropped a Google Messages contact's mapping to a chat with no conversation ID")
		return restoredChat{}, false, c.dropMapping(ctx, m)
	}
	room, oldPortal, found, doubt, err := c.oldRoomFor(ctx, m, catchAll)
	if err != nil {
		return restoredChat{}, false, err
	}
	if doubt {
		// Not sure whose room it is (a number two contacts share, or a room that isn't surely one-to-one): giving the
		// wrong person's history to this chat is worse than leaving both as they are.
		log.Warn().Msg("left a Google Messages contact's mapping and the old rooms that might be its chat as they are: not sure which room is its chat")
		return restoredChat{}, false, nil
	}
	if !found {
		if m.hasRow {
			return restoredChat{}, false, nil
		}
		log.Warn().Msg("dropped a Google Messages contact's mapping to a chat that is gone; the next sync makes the chat again")
		return restoredChat{}, false, c.dropMapping(ctx, m)
	}
	key := networkid.PortalKey{ID: oldPortal, Receiver: m.login}
	if oldPortal != m.portal {
		// The mapping moves to the old chat first: a start that stops after it finds that chat's mapping with its
		// room tombstoned, and restores it as above. A row with no room at the new ID goes (the next sync of the
		// contact's conversation moves the chat there, after its mapping is stored).
		err := c.br.DB.DoTxn(ctx, nil, func(ctx context.Context) error {
			if err := c.dropMapping(ctx, m); err != nil {
				return err
			}
			_, err := c.br.DB.Exec(ctx, "INSERT INTO "+gmessagesMappingTable+
				" (bridge_id, login_id, phone_number, portal_id, last_message_ts) VALUES ($1, $2, $3, $4, $5)",
				c.br.ID, m.login, m.phone, oldPortal, m.lastMessageTS)
			if err != nil {
				return err
			}
			if m.hasRow {
				return c.br.DB.Portal.Delete(ctx, networkid.PortalKey{ID: m.portal, Receiver: m.login})
			}
			return nil
		})
		if err != nil {
			return restoredChat{}, false, err
		}
	}
	if oldPortal == m.portal && m.hasRow {
		// Its row has no room: the room is given back by making the row again.
		if err := c.br.DB.Portal.Delete(ctx, key); err != nil {
			return restoredChat{}, false, err
		}
	}
	lastTS, err := c.store.RoomLastTS(ctx, room.RoomID)
	if err != nil {
		return restoredChat{}, false, err
	}
	if err := c.restorePortal(ctx, key, id.RoomID(room.RoomID)); err != nil {
		return restoredChat{}, false, err
	}
	log.Warn().Str("room_id", room.RoomID).
		Msg("restored a Google Messages chat that was merged into a chat with no conversation ID; it will be synced from the phone")
	return restoredChat{ID: key.ID, Receiver: key.Receiver, LastTS: lastTS}, true, nil
}

// oldRoomFor finds the room a broken mapping's chat had. The room of the mapped chat itself is found by its ID. One
// of the contact's old chat is found by the contact's phone number, and only when that is certain: exactly one
// candidate has it (doubt otherwise: two contacts can share a number), and that room is surely one-to-one (oneToOne).
func (c *Connector) oldRoomFor(ctx context.Context, m dmMapping, catchAll map[string]bool) (room store.ChannelRoom, portal networkid.PortalID, found, doubt bool, err error) {
	usable := func(r store.ChannelRoom) (bool, error) {
		if !r.Tombstoned || !liftable(r.Replacement, catchAll) {
			return false, nil
		}
		taken, err := c.br.DB.Portal.GetByMXID(ctx, id.RoomID(r.RoomID))
		return taken == nil, err
	}
	own, err := c.store.RoomsForChannel(ctx, c.network, string(m.portal), string(m.login))
	if err != nil {
		return room, "", false, false, err
	}
	for _, r := range own {
		if ok, err := usable(r); err != nil || ok {
			return r, m.portal, ok, false, err
		}
	}
	all, err := c.store.ChannelRooms(ctx, c.network, string(m.login))
	if err != nil {
		return room, "", false, false, err
	}
	type candidate struct {
		room  store.ChannelRoom
		ghost networkid.UserID
		old   networkid.PortalID
	}
	var matches []candidate
	for _, r := range all {
		if r.ChannelID == "" || r.ChannelID == string(m.portal) || emptyConversationPortalRE.MatchString(r.ChannelID) {
			continue
		}
		if ok, err := usable(r); err != nil {
			return room, "", false, false, err
		} else if !ok {
			continue
		}
		old := networkid.PortalKey{ID: networkid.PortalID(r.ChannelID), Receiver: m.login}
		if p, err := c.br.DB.Portal.GetByKey(ctx, old); err != nil {
			return room, "", false, false, err
		} else if p != nil {
			continue
		}
		var mapped int
		err := c.br.DB.QueryRow(ctx, "SELECT COUNT(*) FROM "+gmessagesMappingTable+" WHERE bridge_id = $1 AND login_id = $2 AND portal_id = $3",
			c.br.ID, m.login, old.ID).Scan(&mapped)
		if err != nil {
			return room, "", false, false, err
		}
		if mapped > 0 {
			continue
		}
		if ghost := c.theOtherGhost(ctx, id.RoomID(r.RoomID)); ghost != "" && m.phone != "" && c.ghostPhone(ctx, ghost) == m.phone {
			matches = append(matches, candidate{r, ghost, old.ID})
		}
	}
	switch {
	case len(matches) == 0:
		return room, "", false, false, nil
	case len(matches) > 1:
		return room, "", false, true, nil
	}
	only := matches[0]
	surely, err := c.oneToOne(ctx, only.room, only.ghost)
	if err != nil || !surely {
		return room, "", false, true, err
	}
	return only.room, only.old, true, false, nil
}

// oneToOne reports whether a room is surely a one-to-one chat with ghost: its bridge info says it is a direct chat (and
// never a group), the store says it is direct, and nobody is in it but the user, the bridge bot and that ghost (the
// ghost itself left with the tombstone).
func (c *Connector) oneToOne(ctx context.Context, r store.ChannelRoom, ghost networkid.UserID) (bool, error) {
	room, ok, err := c.store.GetRoom(ctx, r.RoomID)
	if err != nil || !ok || !room.IsDirect {
		return false, err
	}
	raw, ok, err := c.store.GetState(ctx, r.RoomID, "m.bridge", c.network)
	if err != nil || !ok {
		return false, err
	}
	var info struct {
		RoomType   string `json:"com.beeper.room_type"`
		RoomTypeV2 string `json:"com.beeper.room_type.v2"`
	}
	if json.Unmarshal(raw, &info) != nil || info.RoomTypeV2 != "dm" || (info.RoomType != "" && info.RoomType != "dm") {
		return false, nil
	}
	members, err := c.store.Members(ctx, r.RoomID)
	if err != nil {
		return false, err
	}
	allowed := map[string]bool{
		string(ids.Me): true, string(id.NewUserID(c.network+"bot", ids.ServerName)): true, string(ids.GhostMXID(c.network, ghost)): true,
	}
	for member := range members {
		if !allowed[member] {
			return false, nil
		}
	}
	return true, nil
}

// ghostPhone is the phone number the bridge keeps on a ghost ("" when it has none).
func (c *Connector) ghostPhone(ctx context.Context, ghost networkid.UserID) string {
	var phone sql.NullString
	err := c.br.DB.QueryRow(ctx, "SELECT json_extract(metadata, '$.phone') FROM ghost WHERE bridge_id = $1 AND id = $2",
		c.br.ID, ghost).Scan(&phone)
	if err != nil {
		return ""
	}
	return phone.String
}

// restorePortal makes key's portal row again, pointing at room, and takes the tombstone off the room. The row is
// first, so a start that stops between the two finds a portal whose room still carries a tombstone, which
// liftTombstonesOfMappedChats fixes. What the row holds comes from the room's own state (its name, its picture, who
// is in it); the next sync of the chat sets the rest.
func (c *Connector) restorePortal(ctx context.Context, key networkid.PortalKey, room id.RoomID) error {
	p := &database.Portal{
		BridgeID:  c.br.ID,
		PortalKey: key,
		MXID:      room,
		RoomType:  database.RoomTypeDM,
		Metadata:  map[string]any{},
	}
	var name struct {
		Name string `json:"name"`
	}
	if raw, ok, err := c.store.GetState(ctx, string(room), event.StateRoomName.Type, ""); err != nil {
		return err
	} else if ok && json.Unmarshal(raw, &name) == nil && name.Name != "" {
		p.Name, p.NameSet = name.Name, true
	}
	var avatar struct {
		URL id.ContentURIString `json:"url"`
	}
	if raw, ok, err := c.store.GetState(ctx, string(room), event.StateRoomAvatar.Type, ""); err != nil {
		return err
	} else if ok && json.Unmarshal(raw, &avatar) == nil && avatar.URL != "" {
		p.AvatarMXC, p.AvatarSet = avatar.URL, true
	}
	p.OtherUserID = c.theOtherGhost(ctx, room)
	if err := c.br.DB.Portal.Insert(ctx, p); err != nil {
		return fmt.Errorf("restoring the chat: %w", err)
	}
	if _, err := c.store.ClearTombstone(ctx, string(room)); err != nil {
		return fmt.Errorf("taking the tombstone off the restored chat's room: %w", err)
	}
	return nil
}

// theOtherGhost is the one ghost a one-to-one room's power levels name (a bridge gives a chat's ghosts power level
// 50), or "" when there isn't exactly one: the chat's next sync says.
func (c *Connector) theOtherGhost(ctx context.Context, room id.RoomID) networkid.UserID {
	raw, ok, err := c.store.GetState(ctx, string(room), event.StatePowerLevels.Type, "")
	if err != nil || !ok {
		return ""
	}
	var pl struct {
		Users map[string]int `json:"users"`
	}
	if json.Unmarshal(raw, &pl) != nil {
		return ""
	}
	var found networkid.UserID
	for user := range pl.Users {
		g, isGhost := ids.ParseGhostMXID(c.network, id.UserID(user))
		if !isGhost {
			continue
		}
		if found != "" {
			return ""
		}
		found = g
	}
	return found
}

// liftTombstonesOfMappedChats takes the tombstone off the room of every one-to-one chat the mapping table lists, when
// the bug left it (liftable): a chat that has a portal row is live, whatever its room says. It only matters after a
// repair that stopped between making a portal row and clearing its room's tombstone. A tombstone that points
// anywhere else is a real merge, and stays.
func (c *Connector) liftTombstonesOfMappedChats(ctx context.Context, catchAll map[string]bool) error {
	rows, err := c.br.DB.Query(ctx, `SELECT p.mxid FROM portal p
		JOIN `+gmessagesMappingTable+` dc ON dc.bridge_id = p.bridge_id AND dc.portal_id = p.id AND dc.login_id = p.receiver
		WHERE p.bridge_id = $1 AND p.mxid IS NOT NULL AND p.mxid <> ''`, c.br.ID)
	if err != nil {
		return err
	}
	var rooms []string
	for rows.Next() {
		var room string
		if err := rows.Scan(&room); err != nil {
			rows.Close()
			return err
		}
		rooms = append(rooms, room)
	}
	if err := rows.Close(); err != nil {
		return err
	}
	for _, room := range rooms {
		tombstoned, replacement, err := c.store.TombstoneReplacement(ctx, room)
		if err != nil {
			return err
		}
		if !tombstoned || !liftable(replacement, catchAll) {
			continue
		}
		if lifted, err := c.store.ClearTombstone(ctx, room); err != nil {
			return err
		} else if lifted {
			c.log.Warn().Str("room_id", room).Msg("took a tombstone off the room of a live Google Messages chat")
		}
	}
	return nil
}

// pendingResyncs is the restored chats still waiting for their resync.
func (c *Connector) pendingResyncs(ctx context.Context) []restoredChat {
	repairMu.Lock()
	defer repairMu.Unlock()
	return c.loadPendingResyncs(ctx)
}

func (c *Connector) loadPendingResyncs(ctx context.Context) []restoredChat {
	raw := c.br.DB.KV.Get(ctx, repairResyncKey)
	if raw == "" {
		return nil
	}
	var chats []restoredChat
	if err := json.Unmarshal([]byte(raw), &chats); err != nil {
		c.log.Warn().Err(err).Msg("ignoring an unreadable list of restored chats waiting for a resync")
		return nil
	}
	return chats
}

func (c *Connector) storePendingResyncs(ctx context.Context, chats []restoredChat) {
	if len(chats) == 0 {
		c.br.DB.KV.Delete(ctx, repairResyncKey)
		return
	}
	raw, err := json.Marshal(chats)
	if err != nil {
		return
	}
	c.br.DB.KV.Set(ctx, repairResyncKey, string(raw))
}

func (c *Connector) addPendingResyncs(ctx context.Context, add []restoredChat) {
	repairMu.Lock()
	defer repairMu.Unlock()
	chats := c.loadPendingResyncs(ctx)
	for _, a := range add {
		dup := false
		for _, have := range chats {
			dup = dup || have.sameChat(a)
		}
		if !dup {
			chats = append(chats, a)
		}
	}
	c.storePendingResyncs(ctx, chats)
}

func (c *Connector) donePendingResync(ctx context.Context, done restoredChat) {
	repairMu.Lock()
	defer repairMu.Unlock()
	var left []restoredChat
	for _, have := range c.loadPendingResyncs(ctx) {
		if !have.sameChat(done) {
			left = append(left, have)
		}
	}
	c.storePendingResyncs(ctx, left)
}

// resyncRestoredChats syncs each restored chat from the network once its login is connected: the chat's info (which
// brings its ghosts back into the room) and the messages the room doesn't have (resyncOne). A chat stays in the
// pending list until its resync is queued, so a start that ends first (the phone was off) tries again at the next
// one. It gives up after resyncGiveUpAfter, again leaving the list as it is.
func (c *Connector) resyncRestoredChats(ctx context.Context) {
	if ctx == nil {
		return
	}
	type retry struct {
		next  time.Time
		delay time.Duration
	}
	retries := map[string]*retry{}
	deadline := time.NewTimer(resyncGiveUpAfter)
	defer deadline.Stop()
	tick := time.NewTicker(resyncPollInterval)
	defer tick.Stop()
	for {
		pending := c.pendingResyncs(ctx)
		if len(pending) == 0 {
			return
		}
		for _, chat := range pending {
			login := c.br.GetCachedUserLoginByID(chat.Receiver)
			if login == nil || login.Client == nil || login.BridgeState.GetPrev().StateEvent != status.StateConnected {
				continue
			}
			key := string(chat.Receiver) + "|" + string(chat.ID)
			if r := retries[key]; r != nil && time.Now().Before(r.next) {
				continue
			}
			if err := c.resyncOne(ctx, login, chat); err != nil {
				r := retries[key]
				if r == nil {
					r = &retry{delay: resyncRetryInitial / 2}
					retries[key] = r
				}
				r.delay = min(r.delay*2, resyncRetryMax)
				r.next = time.Now().Add(r.delay)
				c.log.Warn().Err(err).Str("portal_id", string(chat.ID)).Dur("retry_in", r.delay).
					Msg("couldn't resync a restored Google Messages chat yet; trying again later")
				continue
			}
			delete(retries, key)
			c.donePendingResync(ctx, chat)
		}
		select {
		case <-ctx.Done():
			return
		case <-deadline.C:
			c.log.Warn().Msg("restored Google Messages chats are still waiting for their resync; trying again at the next start")
			return
		case <-tick.C:
		}
	}
}

// resyncOne queues one restored chat's resync. The chat's room already holds its old history, but the bridge has no
// message rows for it, so a backfill would send the latest messages all over again. So first the newest message the
// phone has that the room already holds (not newer than the room's newest event when it was restored) is put in as a
// message of the chat (a real one: replies to it resolve), and the backfill (bridgev2 drops everything not newer than
// the chat's last message) sends only what came after. When a message came in live before this, it is the chat's last
// message and the backfill would start after it, so what the room is missing before it is sent as messages instead.
// An error means "not yet": the chat stays pending.
func (c *Connector) resyncOne(ctx context.Context, login *bridgev2.UserLogin, chat restoredChat) error {
	key := networkid.PortalKey{ID: chat.ID, Receiver: chat.Receiver}
	portal, err := c.br.GetExistingPortalByKey(ctx, key)
	if err != nil {
		return err
	}
	if portal == nil {
		return nil // the chat was deleted meanwhile: nothing to resync
	}
	var anchor networkid.MessageID
	var gap []*bridgev2.BackfillMessage
	if api, ok := login.Client.(bridgev2.BackfillingNetworkAPI); ok {
		if anchor, gap, err = c.seedBackfillAnchor(ctx, api, portal, chat.LastTS); err != nil {
			return err
		}
	}
	c.queueResync(login, key, anchor)
	for _, m := range gap {
		c.queueMissedMessage(login, key, m)
	}
	return nil
}

// seedBackfillAnchor makes the newest message of the phone's latest ones that is not newer than lastTS (the newest
// event the room held before the chat was restored) a message of the chat, and returns its ID ("" when there is none
// to make: lastTS is 0, none of the phone's is that old, or the chat can't be backfilled). It also returns the
// messages the room is missing, when a live message has already become the chat's last message: those newer than
// lastTS that the bridge doesn't have.
func (c *Connector) seedBackfillAnchor(ctx context.Context, api bridgev2.BackfillingNetworkAPI, portal *bridgev2.Portal, lastTS int64) (networkid.MessageID, []*bridgev2.BackfillMessage, error) {
	limit := c.br.Config.Backfill.MaxInitialMessages
	if !c.br.Config.Backfill.Enabled || limit <= 0 {
		return "", nil, nil
	}
	resp, err := api.FetchMessages(ctx, bridgev2.FetchMessagesParams{Portal: portal, Forward: true, Count: limit})
	if err != nil {
		return "", nil, err
	}
	if resp == nil {
		return "", nil, nil
	}
	var newest *bridgev2.BackfillMessage
	for _, m := range resp.Messages {
		if m != nil && m.ID != "" && lastTS > 0 && m.Timestamp.UnixMilli() <= lastTS && (newest == nil || m.Timestamp.After(newest.Timestamp)) {
			newest = m
		}
	}
	var anchor networkid.MessageID
	if newest != nil {
		if anchor, err = c.insertAnchor(ctx, portal, newest); err != nil {
			return "", nil, err
		}
	}
	latest, err := c.br.DB.Message.GetLastPartAtOrBeforeTime(ctx, portal.PortalKey, time.Now().Add(10*time.Second))
	if err != nil {
		return "", nil, err
	}
	if latest == nil || (anchor != "" && latest.ID == anchor) {
		return anchor, nil, nil
	}
	var gap []*bridgev2.BackfillMessage
	for _, m := range resp.Messages {
		if m == nil || m.ID == "" || m.ConvertedMessage == nil || m.Timestamp.UnixMilli() <= lastTS {
			continue
		}
		have, err := c.br.DB.Message.GetFirstPartByID(ctx, portal.Receiver, m.ID)
		if err != nil {
			return "", nil, err
		}
		if have == nil {
			gap = append(gap, m)
		}
	}
	return anchor, gap, nil
}

// insertAnchor makes m (a message of the phone's that the room holds) a message of the chat, with the event the room
// has it under (the bridge's own event IDs are made from the message's ID, so a reply to it is a reply to that event).
// It returns m's ID, or "" when there is no sender to give it.
func (c *Connector) insertAnchor(ctx context.Context, portal *bridgev2.Portal, m *bridgev2.BackfillMessage) (networkid.MessageID, error) {
	if have, err := c.br.DB.Message.GetFirstPartByID(ctx, portal.Receiver, m.ID); err != nil || have != nil {
		return m.ID, err
	}
	sender := m.Sender.Sender
	if sender == "" {
		sender = portal.OtherUserID
	}
	if sender == "" {
		return "", nil
	}
	if _, err := c.br.GetGhostByID(ctx, sender); err != nil { // the message's sender must be a ghost the bridge has
		return "", err
	}
	senderMXID := ids.GhostMXID(c.network, sender)
	if m.Sender.IsFromMe {
		senderMXID = ids.Me
	}
	err := c.br.DB.Message.Insert(ctx, &database.Message{
		BridgeID:   c.br.ID,
		ID:         m.ID,
		MXID:       c.GenerateDeterministicEventID(portal.MXID, portal.PortalKey, m.ID, ""),
		Room:       portal.PortalKey,
		SenderID:   sender,
		SenderMXID: senderMXID,
		Timestamp:  m.Timestamp,
		Metadata:   map[string]any{},
	})
	if err != nil {
		return "", err
	}
	return m.ID, nil
}

// queueMissedMessage sends one message the room is missing as the network would have delivered it. A message the
// bridge got meanwhile is ignored. (Its reactions are not sent: a backfill would, this does not.)
func (c *Connector) queueMissedMessage(login *bridgev2.UserLogin, key networkid.PortalKey, m *bridgev2.BackfillMessage) {
	c.br.QueueRemoteEvent(login, &simplevent.Message[*bridgev2.BackfillMessage]{
		EventMeta: simplevent.EventMeta{
			Type:      bridgev2.RemoteEventMessage,
			PortalKey: key,
			Sender:    m.Sender,
			Timestamp: m.Timestamp,
		},
		Data: m,
		ID:   m.ID,
		ConvertMessageFunc: func(_ context.Context, _ *bridgev2.Portal, _ bridgev2.MatrixAPI, data *bridgev2.BackfillMessage) (*bridgev2.ConvertedMessage, error) {
			return data.ConvertedMessage, nil
		},
		HandleExistingFunc: func(context.Context, *bridgev2.Portal, bridgev2.MatrixAPI, []*database.Message, *bridgev2.BackfillMessage) (bridgev2.UpsertResult, error) {
			return bridgev2.UpsertResult{}, nil
		},
	})
}

func (c *Connector) queueResync(login *bridgev2.UserLogin, key networkid.PortalKey, anchor networkid.MessageID) {
	c.br.QueueRemoteEvent(login, &simplevent.ChatResync{
		EventMeta: simplevent.EventMeta{
			Type:      bridgev2.RemoteEventChatResync,
			PortalKey: key,
			LogContext: func(zc zerolog.Context) zerolog.Context {
				return zc.Str("action", "resync a restored chat")
			},
		},
		GetChatInfoFunc: func(ctx context.Context, portal *bridgev2.Portal) (*bridgev2.ChatInfo, error) {
			return login.Client.GetChatInfo(ctx, portal)
		},
		// Backfill from the anchor, or from nothing when the chat has no message at all. A chat that has messages of
		// its own by now (one came in since) is left to the usual syncs.
		CheckNeedsBackfillFunc: func(_ context.Context, latest *database.Message) (bool, error) {
			return latest == nil || (anchor != "" && latest.ID == anchor), nil
		},
	})
}
