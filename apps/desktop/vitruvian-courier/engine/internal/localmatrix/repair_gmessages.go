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
)

// restoredChat is a chat the repair put back, waiting for its resync.
type restoredChat struct {
	ID       networkid.PortalID    `json:"id"`
	Receiver networkid.UserLoginID `json:"receiver"`
}

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

// doRepairGoogleMessages is the repair; it returns the chats it restored.
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
	for _, p := range empty {
		keep(c.removeEmptyConversationPortal(ctx, p))
	}

	hasMapping, err := c.hasTable(ctx, gmessagesMappingTable)
	if err != nil {
		return restored, errors.Join(firstErr, err)
	}
	if !hasMapping {
		return restored, firstErr
	}
	dangling, err := c.danglingMappings(ctx)
	keep(err)
	for _, m := range dangling {
		chat, ok, err := c.restoreOrDropMapping(ctx, m)
		keep(err)
		if ok {
			restored = append(restored, chat)
		}
	}
	keep(c.liftTombstonesOfMappedChats(ctx))
	return restored, firstErr
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

// dmMapping is one row of the phone number to portal table.
type dmMapping struct {
	login  networkid.UserLoginID
	phone  string
	portal networkid.PortalID
}

// danglingMappings lists the mappings whose portal has no row.
func (c *Connector) danglingMappings(ctx context.Context) ([]dmMapping, error) {
	rows, err := c.br.DB.Query(ctx, `SELECT dc.login_id, dc.phone_number, dc.portal_id
		FROM `+gmessagesMappingTable+` dc
		LEFT JOIN portal p ON p.bridge_id = dc.bridge_id AND p.id = dc.portal_id AND p.receiver = dc.login_id
		WHERE dc.bridge_id = $1 AND p.id IS NULL`, c.br.ID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []dmMapping
	for rows.Next() {
		var m dmMapping
		if err := rows.Scan(&m.login, &m.phone, &m.portal); err != nil {
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

// restoreOrDropMapping puts a mapping's portal back on the room it had, when that room is in the store tombstoned
// and nobody else uses it; otherwise the mapping goes, and the next sync makes the chat and its mapping again. The
// phone number and the chat's name are never logged.
func (c *Connector) restoreOrDropMapping(ctx context.Context, m dmMapping) (restoredChat, bool, error) {
	log := c.log.With().Str("portal_id", string(m.portal)).Logger()
	if emptyConversationPortalRE.MatchString(string(m.portal)) {
		log.Warn().Msg("dropped a Google Messages contact's mapping to a chat with no conversation ID")
		return restoredChat{}, false, c.dropMapping(ctx, m)
	}
	rooms, err := c.store.RoomsForChannel(ctx, c.network, string(m.portal), string(m.login))
	if err != nil {
		return restoredChat{}, false, err
	}
	for _, r := range rooms {
		if !r.Tombstoned {
			continue
		}
		taken, err := c.br.DB.Portal.GetByMXID(ctx, id.RoomID(r.RoomID))
		if err != nil {
			return restoredChat{}, false, err
		}
		if taken != nil {
			continue
		}
		key := networkid.PortalKey{ID: m.portal, Receiver: m.login}
		if err := c.restorePortal(ctx, key, id.RoomID(r.RoomID)); err != nil {
			return restoredChat{}, false, err
		}
		log.Warn().Str("room_id", r.RoomID).
			Msg("restored a Google Messages chat that was merged into a chat with no conversation ID; it will be synced from the phone")
		return restoredChat{ID: key.ID, Receiver: key.Receiver}, true, nil
	}
	log.Warn().Msg("dropped a Google Messages contact's mapping to a chat that is gone; the next sync makes the chat again")
	return restoredChat{}, false, c.dropMapping(ctx, m)
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

// liftTombstonesOfMappedChats takes the tombstone off the room of every one-to-one chat the mapping table lists:
// a chat that has a portal row is live, whatever its room says. It only matters after a repair that stopped
// between making a portal row and clearing its room's tombstone.
func (c *Connector) liftTombstonesOfMappedChats(ctx context.Context) error {
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
		lifted, err := c.store.ClearTombstone(ctx, room)
		if err != nil {
			return err
		}
		if lifted {
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
			dup = dup || have == a
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
		if have != done {
			left = append(left, have)
		}
	}
	c.storePendingResyncs(ctx, left)
}

// resyncRestoredChats syncs each restored chat from the network once its login is connected: the chat's info (which
// brings its ghosts back into the room) and, as it has no messages of its own any more, its latest messages. A chat
// stays in the pending list until its resync is queued, so a start that ends first (the phone was off) tries again
// at the next one. It gives up after resyncGiveUpAfter, again leaving the list as it is.
func (c *Connector) resyncRestoredChats(ctx context.Context) {
	if ctx == nil {
		return
	}
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
			c.queueResync(login, networkid.PortalKey{ID: chat.ID, Receiver: chat.Receiver})
			c.donePendingResync(ctx, chat)
		}
		select {
		case <-ctx.Done():
			return
		case <-deadline.C:
			c.log.Warn().Msg("restored Google Messages chats are still waiting for their login to connect; trying again at the next start")
			return
		case <-tick.C:
		}
	}
}

func (c *Connector) queueResync(login *bridgev2.UserLogin, key networkid.PortalKey) {
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
		// The restored chat has no messages of its own: it takes the latest ones from the network. One that has
		// some by now (a message came in since) is left to the usual syncs.
		CheckNeedsBackfillFunc: func(_ context.Context, latest *database.Message) (bool, error) {
			return latest == nil, nil
		},
	})
}
