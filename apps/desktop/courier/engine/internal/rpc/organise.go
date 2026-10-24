// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

// Protocol 2's inbox: one page of a space at a time, and the methods that organise it (spaces, labels, chat states,
// reminders, auto-archive rules). Each handler has the shape of the others: strict params, the required ones
// checked by name, then one store or actions call whose sentinel errors map to their codes (sentinels).

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"time"

	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

const (
	// maxBulkRoomIDs is how many chats one change can name.
	maxBulkRoomIDs = 500
	// maxLookupRoomIDs is how many chats inbox.list's room_ids can name.
	maxLookupRoomIDs = 100
	// maxPageLimit is inbox.list's largest limit.
	maxPageLimit = 500
	// maxPageBytes is what an inbox.list answer stays under (Review Focus 3): a quarter of a frame, so a page is
	// quick to send and read whatever the chats hold. pageSlack is kept back for the envelope and next_cursor.
	maxPageBytes = 1 << 20
	pageSlack    = 4 << 10
)

// allowed is not_entitled unless the plan includes f.
func (d *Deps) allowed(f entitlement.Feature) error {
	if d.Entitlement == nil || d.Entitlement.Allowed(f) {
		return nil
	}
	return newError(CodeNotEntitled)
}

// poke tells the timer loop a reminder or a rule changed.
func (d *Deps) poke() {
	if d.Timers != nil {
		d.Timers.Poke()
	}
}

// linked reports whether network is running with an account of mine: such a network has a space.
func (d *Deps) linked(network string) bool {
	if d.Engine == nil {
		return false
	}
	h, ok := d.Engine.Host(network)
	if !ok {
		return false
	}
	for _, l := range h.Bridge.GetAllCachedUserLogins() {
		if l.UserMXID == ids.Me {
			return true
		}
	}
	return false
}

// hasAccount says, for network's running bridge, whether an account ID (a bridgev2 user login's, as login_state keys
// it: not a sign-in's login_id, Ruling C16) is an account of mine it has now; nil when the network isn't running
// (nothing to ask, so every stored account counts).
func (d *Deps) hasAccount(network string) func(accountID string) bool {
	if d.Engine == nil {
		return nil
	}
	h, ok := d.Engine.Host(network)
	if !ok {
		return nil
	}
	return func(accountID string) bool {
		l := h.Bridge.GetCachedUserLoginByID(networkid.UserLoginID(accountID))
		return l != nil && l.UserMXID == ids.Me
	}
}

// hasSpace reports whether network's account has a space: it is linked, or it isn't running (still starting, or
// failed to start this session) and was linked when the engine last ran (a login of its has a stored state). Without
// the second, every account space would vanish at launch until its bridge is up, and with it a space selected at
// quit; and a linked network that fails to start would lose its space though its chats are still there (Ruling 3).
func (d *Deps) hasSpace(ctx context.Context, network string) (bool, error) {
	if d.linked(network) {
		return true, nil
	}
	if st := d.status(network); !st.Starting && st.NotStarted == "" {
		return false, nil // running and not linked, or a network the engine was never given
	}
	states, err := d.Store.LoginStates(ctx, network)
	if err != nil {
		return false, err
	}
	for _, l := range states {
		if l.LoginID != "" {
			return true, nil
		}
	}
	return false, nil
}

// roomIDList checks a room_ids parameter: there, and 1 to most chats.
func roomIDList(v *[]string, most int) ([]string, error) {
	if v == nil {
		return nil, invalidParams("room_ids is required")
	}
	if n := len(*v); n < 1 || n > most {
		return nil, invalidParams(fmt.Sprintf("room_ids must name 1 to %d chats", most))
	}
	return *v, nil
}

func requiredBool(name string, v *bool) error {
	if v == nil {
		return invalidParams(name + " is required")
	}
	return nil
}

func requiredInt(name string, v *int64) error {
	if v == nil {
		return invalidParams(name + " is required")
	}
	return nil
}

// spaceParam checks an optional space: left out is inbox; given, it must be a space ID.
func spaceParam(v *string) (string, error) {
	if v == nil {
		return "inbox", nil
	}
	if !store.IsSpaceID(*v) {
		return "", invalidParams("space is not a space")
	}
	return *v, nil
}

// roomsChanged is the result of a change to many chats: the ones it changed. Never null.
type roomsChanged struct {
	RoomIDs []string `json:"room_ids"`
}

func changedRooms(ids []string) roomsChanged {
	if ids == nil {
		ids = []string{}
	}
	return roomsChanged{RoomIDs: ids}
}

// The inbox.

type reminderJSON struct {
	DueAt     int64  `json:"due_at"`
	Condition string `json:"condition"`
	Fired     bool   `json:"fired"`
}

type inboxRow struct {
	RoomID           string        `json:"room_id"`
	Network          string        `json:"network"`
	Name             string        `json:"name"`
	RemoteName       string        `json:"remote_name"`
	LocalName        string        `json:"local_name"`
	AvatarPath       string        `json:"avatar_path"`
	LocalAvatarPath  string        `json:"local_avatar_path"`
	MergeID          string        `json:"merge_id"`
	IsDirect         bool          `json:"is_direct"`
	LastTS           int64         `json:"last_ts"`
	Preview          string        `json:"preview"`
	PreviewKind      string        `json:"preview_kind"`
	PreviewMine      bool          `json:"preview_mine"`
	PreviewStatus    string        `json:"preview_status"`
	LoginName        string        `json:"login_name"`
	Unread           int           `json:"unread"`
	Muted            bool          `json:"muted"`
	Pinned           bool          `json:"pinned"`
	Archived         bool          `json:"archived"`
	LowPriority      bool          `json:"low_priority"`
	Hidden           bool          `json:"hidden"`
	MarkedUnread     bool          `json:"marked_unread"`
	Request          bool          `json:"request"`
	Draft            string        `json:"draft"`
	Labels           []int64       `json:"labels"`
	MutedBy          string        `json:"muted_by"`
	MutedByName      string        `json:"muted_by_name"`
	Reminder         *reminderJSON `json:"reminder"`
	Typing           []string      `json:"typing"`
	UnreadMentions   int           `json:"unread_mentions"`
	PreviewMediaPath string        `json:"preview_media_path"`
	PreviewCall      *callJSON     `json:"preview_call"` // null unless preview_kind is call
}

// callJSON is a CallNote: what a bridge's call notice says, as Courier reads it.
type callJSON struct {
	State string `json:"state"`
	Media string `json:"media"`
}

type inboxResult struct {
	Rooms      []inboxRow `json:"rooms"`
	NextCursor *string    `json:"next_cursor"`
}

func inboxList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Space   *string   `json:"space"`
		Filters *[]string `json:"filters"`
		Sort    *string   `json:"sort"`
		Cursor  *string   `json:"cursor"`
		Limit   *int      `json:"limit"`
		RoomIDs *[]string `json:"room_ids"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	var q store.InboxQuery
	if p.RoomIDs != nil {
		if p.Space != nil || p.Filters != nil || p.Sort != nil {
			return nil, invalidParams("room_ids can't be given with space, filters or sort")
		}
		ids, err := roomIDList(p.RoomIDs, maxLookupRoomIDs)
		if err != nil {
			return nil, err
		}
		q.RoomIDs = ids
	}
	if p.Space != nil {
		space, err := spaceParam(p.Space)
		if err != nil {
			return nil, err
		}
		q.Space = space
	}
	if p.Filters != nil {
		// Ruling 11: All is no filters. There is no "all" filter, and FilterNames has none.
		names := store.FilterNames()
		for _, f := range *p.Filters {
			if !slices.Contains(names, f) {
				return nil, invalidParams("filters names a filter there isn't")
			}
		}
		q.Filters = *p.Filters
	}
	if p.Sort != nil {
		if !slices.Contains(store.SortNames(), *p.Sort) {
			return nil, invalidParams("sort is not a sort")
		}
		q.Sort = *p.Sort
	}
	if p.Limit != nil {
		if *p.Limit < 1 || *p.Limit > maxPageLimit {
			return nil, invalidParams(fmt.Sprintf("limit must be 1 to %d", maxPageLimit))
		}
		q.Limit = *p.Limit
	}
	if p.Cursor != nil {
		q.After = *p.Cursor // the store refuses a cursor of another query: ErrBadCursor
	}
	rows, next, err := d.inboxPage(ctx, q)
	if err != nil {
		return nil, err
	}
	res := inboxResult{Rooms: rows}
	if next != "" {
		res.NextCursor = &next
	}
	return res, nil
}

// inboxPage is one page of q, as it goes on the wire. It stays under maxPageBytes: a page that would pass it is
// asked for again with only the rows that fit, so the store hands out the cursor after the last of them and the
// next page carries on from there. A draft is sent whole (the composer takes it), and 500 rows of long drafts
// would otherwise make a frame of megabytes. Each pass asks for fewer rows, and a page always has at least one.
func (d *Deps) inboxPage(ctx context.Context, q store.InboxQuery) ([]inboxRow, string, error) {
	for {
		rows, next, err := d.Store.InboxPage(ctx, q)
		if err != nil {
			return nil, "", err
		}
		out, err := d.toRows(ctx, rows)
		if err != nil {
			return nil, "", err
		}
		n := fitting(out, maxPageBytes-pageSlack)
		if n == len(out) {
			return out, next, nil
		}
		q.Limit = n
	}
}

// fitting is how many of rows, from the first, encode to at most budget bytes as a JSON list; never fewer than one.
// json.Marshal escapes <, > and & as six bytes each, which the wire does not, so this overcounts if anything.
func fitting[T any](rows []T, budget int) int {
	total := 2 // the list's brackets
	for i, r := range rows {
		b, err := json.Marshal(r)
		if err != nil {
			return max(i, 1) // can't happen: the row is plain data
		}
		total += len(b) + 1 // and its comma
		if total > budget && i > 0 {
			return i
		}
	}
	return len(rows)
}

// toRows turns the store's rows into the wire's. Each network's accounts are read once per page, for the rows'
// account tags (accountNames).
func (d *Deps) toRows(ctx context.Context, rows []store.InboxRow) ([]inboxRow, error) {
	out := make([]inboxRow, 0, len(rows))
	names := map[string]string{} // user ID → profile name, across the page
	accounts := map[string]map[string]string{}
	for _, r := range rows {
		typing, err := d.typingNames(ctx, r.ID, names)
		if err != nil {
			return nil, err
		}
		tags, ok := accounts[r.Network]
		if !ok {
			if tags, err = d.accountNames(ctx, r.Network); err != nil {
				return nil, err
			}
			accounts[r.Network] = tags
		}
		labels := r.Labels
		if labels == nil {
			labels = []int64{}
		}
		row := inboxRow{
			RoomID: r.ID, Network: r.Network, Name: r.Name, RemoteName: r.RemoteName, LocalName: r.LocalName,
			AvatarPath: d.path(r.AvatarURI), LocalAvatarPath: d.path(r.LocalAvatarURI), MergeID: r.MergeID,
			IsDirect: r.IsDirect, LastTS: ms(r.LastTS), Preview: r.Preview, PreviewKind: r.PreviewKind,
			PreviewMine: r.PreviewMine, PreviewStatus: r.PreviewStatus, LoginName: tags[r.LoginID], Unread: r.Unread,
			Muted: r.Muted, Pinned: !r.PinnedAt.IsZero(), Archived: r.Archived, LowPriority: r.LowPriority,
			Hidden: r.Hidden, MarkedUnread: r.MarkedUnread, Request: r.Request, Draft: r.Draft, Labels: labels,
			MutedBy: r.MutedBy, MutedByName: r.MutedByName, Typing: typing, UnreadMentions: r.UnreadMentions,
			PreviewMediaPath: d.path(r.PreviewMediaURI),
		}
		if rm := r.Reminder; rm != nil {
			row.Reminder = &reminderJSON{DueAt: ms(rm.DueAt), Condition: rm.Condition, Fired: !rm.FiredAt.IsZero()}
		}
		if call := r.PreviewCall; call != nil {
			row.PreviewCall = &callJSON{State: string(call.State), Media: string(call.Media)}
		}
		out = append(out, row)
	}
	return out, nil
}

// accountNames is the name of each of network's accounts, by account ID, for an inbox row's account tag
// (login_name): only when the network has more than one account (accounts.list's logins), so the tag never shows for
// one. A chat every account shares (login ID "") has no tag, since "" is no account's.
func (d *Deps) accountNames(ctx context.Context, network string) (map[string]string, error) {
	logins, err := d.accountLogins(ctx, network)
	if err != nil || len(logins) < 2 {
		return nil, err
	}
	out := make(map[string]string, len(logins))
	for _, l := range logins {
		out[l.LoginID] = d.remoteName(network, l)
	}
	return out, nil
}

// typingNames is who is typing in roomID, by name (personName: their display name in the chat, else their
// profile's, else their ID's localpart); in the order of their IDs. profiles caches profile names across a page.
func (d *Deps) typingNames(ctx context.Context, roomID string, profiles map[string]string) ([]string, error) {
	users := d.Store.TypingIn(roomID)
	out := make([]string, 0, len(users))
	if len(users) == 0 {
		return out, nil
	}
	members, err := d.Store.Members(ctx, roomID)
	if err != nil {
		return nil, err
	}
	for _, u := range users {
		name, err := d.personName(ctx, u, members[u], profiles)
		if err != nil {
			return nil, err
		}
		out = append(out, name)
	}
	return out, nil
}

// inboxMarkAllRead marks read every unread chat space lists. It finds them all first, a page at a time, then reads
// them: reading takes a chat out of the Unread filter, which must not shift the pages under the search.
func inboxMarkAllRead(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Space *string `json:"space"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	space, err := spaceParam(p.Space)
	if err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	var unread []store.Room
	q := store.InboxQuery{Space: space, Filters: []string{"unread"}, Limit: maxPageLimit}
	for {
		rows, next, err := d.Store.InboxPage(ctx, q)
		if err != nil {
			return nil, err
		}
		for _, r := range rows {
			unread = append(unread, r.Room)
		}
		if next == "" {
			break
		}
		q.After = next
	}
	read := make([]string, 0, len(unread))
	for _, r := range unread {
		if err := d.markRead(ctx, r); err != nil {
			return nil, err
		}
		read = append(read, r.ID)
	}
	return changedRooms(read), nil
}

func inboxArchiveMatching(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Space       *string `json:"space"`
		ReadOnly    *bool   `json:"read_only"`
		OlderThanMS *int64  `json:"older_than_ms"`
		DryRun      *bool   `json:"dry_run"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	space, err := spaceParam(p.Space)
	if err != nil {
		return nil, err
	}
	if err := requiredBool("read_only", p.ReadOnly); err != nil {
		return nil, err
	}
	if err := requiredInt("older_than_ms", p.OlderThanMS); err != nil {
		return nil, err
	}
	if err := requiredBool("dry_run", p.DryRun); err != nil {
		return nil, err
	}
	age := time.Duration(*p.OlderThanMS) * time.Millisecond
	if age != 0 && !slices.Contains(store.OlderThanDurations(), age) {
		return nil, newError(CodeBadValue) // only the ages the app offers
	}
	ids, err := d.Store.ArchiveMatching(ctx, store.ArchiveMatch{Space: space, ReadOnly: *p.ReadOnly, OlderThan: age, DryRun: *p.DryRun})
	if err != nil {
		return nil, err
	}
	return changedRooms(ids), nil
}

// Spaces and labels.

type spaceJSON struct {
	SpaceID     string `json:"space_id"`
	Kind        string `json:"kind"`
	Title       string `json:"title"`
	Network     string `json:"network"`
	LabelID     int64  `json:"label_id"`
	Color       int    `json:"color"`
	Icon        string `json:"icon"`
	Hidden      bool   `json:"hidden"`
	Muted       bool   `json:"muted"`
	ShowInInbox string `json:"show_in_inbox"`
	Chats       int    `json:"chats"`
	UnreadChats int    `json:"unread_chats"`
	// AttentionChats is the Dock badge: the inbox's unread chats that nothing mutes. 0 for every other space.
	AttentionChats int `json:"attention_chats"`
}

func spacesList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	var linked []string // in display order, as hello lists networks
	for _, n := range d.Networks {
		ok, err := d.hasSpace(ctx, n.Name)
		if err != nil {
			return nil, err
		}
		if ok {
			linked = append(linked, n.Name)
		}
	}
	spaces, err := d.Store.Spaces(ctx, linked)
	if err != nil {
		return nil, err
	}
	out := make([]spaceJSON, 0, len(spaces))
	for _, s := range spaces {
		out = append(out, spaceJSON{
			SpaceID: s.ID, Kind: s.Kind, Title: s.Title, Network: s.Network, LabelID: s.LabelID, Color: s.Color,
			Icon: s.Icon, Hidden: s.Hidden, Muted: s.Muted, ShowInInbox: s.ShowInInbox, Chats: s.Chats,
			UnreadChats: s.UnreadChats, AttentionChats: s.AttentionChats,
		})
	}
	return map[string]any{"spaces": out}, nil
}

func spacesSetLayout(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Order  *[]string `json:"order"`
		Hidden *[]string `json:"hidden"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if p.Order == nil {
		return nil, invalidParams("order is required")
	}
	if p.Hidden == nil {
		return nil, invalidParams("hidden is required")
	}
	return nil, d.Store.SetSpaceLayout(ctx, *p.Order, *p.Hidden)
}

func spacesUpdate(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		SpaceID     *string `json:"space_id"`
		Muted       *bool   `json:"muted"`
		ShowInInbox *string `json:"show_in_inbox"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("space_id", p.SpaceID); err != nil {
		return nil, err
	}
	return nil, d.Store.UpdateSpace(ctx, *p.SpaceID, p.Muted, p.ShowInInbox)
}

func labelsCreate(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Title *string `json:"title"`
		Color *int    `json:"color"`
		Icon  *string `json:"icon"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	// A title or an icon that is there but empty is the store's to refuse (bad_value), like one too long.
	if p.Title == nil {
		return nil, invalidParams("title is required")
	}
	if p.Color == nil {
		return nil, invalidParams("color is required")
	}
	if p.Icon == nil {
		return nil, invalidParams("icon is required")
	}
	l, err := d.Store.CreateLabel(ctx, *p.Title, *p.Color, *p.Icon)
	if err != nil {
		return nil, err
	}
	return map[string]int64{"label_id": l.ID}, nil
}

func labelsUpdate(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		LabelID *int64  `json:"label_id"`
		Title   *string `json:"title"`
		Color   *int    `json:"color"`
		Icon    *string `json:"icon"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := requiredInt("label_id", p.LabelID); err != nil {
		return nil, err
	}
	return nil, d.Store.UpdateLabel(ctx, *p.LabelID, store.LabelUpdate{Title: p.Title, Color: p.Color, Icon: p.Icon})
}

// labelID reads params that are just a label_id.
func labelID(raw json.RawMessage) (int64, error) {
	var p struct {
		LabelID *int64 `json:"label_id"`
	}
	if err := decode(raw, &p); err != nil {
		return 0, err
	}
	if err := requiredInt("label_id", p.LabelID); err != nil {
		return 0, err
	}
	return *p.LabelID, nil
}

func labelsDelete(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	id, err := labelID(raw)
	if err != nil {
		return nil, err
	}
	return nil, d.Store.DeleteLabel(ctx, id)
}

// Chat states.

func roomSetPinned(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Pinned *bool   `json:"pinned"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := requiredBool("pinned", p.Pinned); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.SetPinned(ctx, *p.RoomID, *p.Pinned)
}

func roomSetArchived(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomIDs  *[]string `json:"room_ids"`
		Archived *bool     `json:"archived"`
		MarkRead bool      `json:"mark_read"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	ids, err := roomIDList(p.RoomIDs, maxBulkRoomIDs)
	if err != nil {
		return nil, err
	}
	if err := requiredBool("archived", p.Archived); err != nil {
		return nil, err
	}
	if p.MarkRead && d.Actions == nil {
		return nil, errMissing // before anything changes
	}
	changed, err := d.Store.SetArchived(ctx, ids, *p.Archived) // all pinned: store.ErrPinned
	if err != nil {
		return nil, err
	}
	if p.MarkRead {
		for _, id := range changed {
			r, err := d.room(ctx, id)
			if err != nil {
				return nil, err
			}
			if err = d.markRead(ctx, r); err != nil {
				return nil, err
			}
		}
	}
	return changedRooms(changed), nil
}

// roomsFlag reads RoomsFlagParams.
func roomsFlag(raw json.RawMessage) ([]string, bool, error) {
	var p struct {
		RoomIDs *[]string `json:"room_ids"`
		On      *bool     `json:"on"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, false, err
	}
	ids, err := roomIDList(p.RoomIDs, maxBulkRoomIDs)
	if err != nil {
		return nil, false, err
	}
	if err := requiredBool("on", p.On); err != nil {
		return nil, false, err
	}
	return ids, *p.On, nil
}

// roomSetLowPriority moves chats to Low priority, which is part of a plan, or back, which never is: nothing is
// kept from someone whose plan ended.
func roomSetLowPriority(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	ids, on, err := roomsFlag(raw)
	if err != nil {
		return nil, err
	}
	if on {
		if err := d.allowed(entitlement.LowPriority); err != nil {
			return nil, err
		}
	}
	changed, err := d.Store.SetLowPriority(ctx, ids, on)
	if err != nil {
		return nil, err
	}
	d.poke() // a low-priority chat is out of the inbox place, which pending auto-archives look at
	return changedRooms(changed), nil
}

func roomSetHidden(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	ids, on, err := roomsFlag(raw)
	if err != nil {
		return nil, err
	}
	changed, err := d.Store.SetHidden(ctx, ids, on)
	if err != nil {
		return nil, err
	}
	return changedRooms(changed), nil
}

// roomSetMarkedUnread goes through Actions, which keeps the mark on this Mac (Ruling 18).
func roomSetMarkedUnread(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	ids, on, err := roomsFlag(raw)
	if err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	changed, err := d.Actions.SetMarkedUnread(ctx, ids, on)
	if err != nil {
		return nil, err
	}
	return changedRooms(changed), nil
}

func roomSetLabel(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomIDs *[]string `json:"room_ids"`
		LabelID *int64    `json:"label_id"`
		On      *bool     `json:"on"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	ids, err := roomIDList(p.RoomIDs, maxBulkRoomIDs)
	if err != nil {
		return nil, err
	}
	if err := requiredInt("label_id", p.LabelID); err != nil {
		return nil, err
	}
	if err := requiredBool("on", p.On); err != nil {
		return nil, err
	}
	changed, err := d.Store.SetLabel(ctx, ids, *p.LabelID, *p.On)
	if err != nil {
		return nil, err
	}
	return changedRooms(changed), nil
}

func roomSetDraft(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Text   *string `json:"text"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.Text == nil {
		return nil, invalidParams("text is required") // "" is a draft cleared
	}
	return nil, d.Store.SetDraft(ctx, *p.RoomID, *p.Text)
}

func roomAcceptRequest(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.AcceptRequest(ctx, *p.RoomID) // a network that can't: actions.ErrNotSupported
}

// Reminders.

func reminderSet(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomIDs   *[]string `json:"room_ids"`
		DueAt     *int64    `json:"due_at"`
		Condition *string   `json:"condition"`
		Archive   bool      `json:"archive"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	ids, err := roomIDList(p.RoomIDs, maxBulkRoomIDs)
	if err != nil {
		return nil, err
	}
	if err := requiredInt("due_at", p.DueAt); err != nil {
		return nil, err
	}
	if p.Condition == nil {
		return nil, invalidParams("condition is required")
	}
	if err := d.allowed(entitlement.Reminders); err != nil {
		return nil, err
	}
	if err := d.Store.SetReminder(ctx, ids, time.UnixMilli(*p.DueAt), *p.Condition); err != nil {
		return nil, err
	}
	d.poke()
	if p.Archive {
		// "Remind me and archive": the reminder brings the chats back. A pinned chat is never archived, and
		// that's no error here: the reminder is set either way.
		if _, err := d.Store.SetArchived(ctx, ids, true); err != nil && !errors.Is(err, store.ErrPinned) {
			return nil, err
		}
	}
	return nil, nil
}

// roomsParam reads RoomsParams.
func roomsParam(raw json.RawMessage) ([]string, error) {
	var p struct {
		RoomIDs *[]string `json:"room_ids"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	return roomIDList(p.RoomIDs, maxBulkRoomIDs)
}

func reminderClear(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	ids, err := roomsParam(raw)
	if err != nil {
		return nil, err
	}
	// The store clears what it finds; a chat it doesn't have is not_found here, as for every other change.
	for _, id := range ids {
		if _, err := d.room(ctx, id); err != nil {
			return nil, err
		}
	}
	if err := d.Store.ClearReminders(ctx, ids); err != nil {
		return nil, err
	}
	d.poke()
	return nil, nil
}

func reminderClearAll(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	if err := d.Store.ClearReminders(ctx, nil); err != nil {
		return nil, err
	}
	d.poke()
	return nil, nil
}

// Auto-archive rules.

type ruleJSON struct {
	RuleID     int64  `json:"rule_id"`
	Scope      string `json:"scope"`
	Trigger    string `json:"trigger"`
	ChatType   string `json:"chat_type"`
	DurationMS int64  `json:"duration_ms"`
	Enabled    bool   `json:"enabled"`
}

func toRuleJSON(r store.Rule) ruleJSON {
	return ruleJSON{
		RuleID: r.ID, Scope: r.Scope, Trigger: r.Trigger, ChatType: r.ChatType,
		DurationMS: r.Duration.Milliseconds(), Enabled: r.Enabled,
	}
}

func autoArchiveList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	rules, err := d.Store.Rules(ctx)
	if err != nil {
		return nil, err
	}
	out := make([]ruleJSON, 0, len(rules))
	for _, r := range rules {
		out = append(out, toRuleJSON(r))
	}
	return map[string]any{"rules": out}, nil
}

func autoArchiveSet(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RuleID     *int64  `json:"rule_id"`
		Scope      *string `json:"scope"`
		Trigger    *string `json:"trigger"`
		ChatType   *string `json:"chat_type"`
		DurationMS *int64  `json:"duration_ms"`
		Enabled    *bool   `json:"enabled"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := requiredInt("rule_id", p.RuleID); err != nil {
		return nil, err
	}
	for _, f := range []struct {
		name string
		v    *string
	}{{"scope", p.Scope}, {"trigger", p.Trigger}, {"chat_type", p.ChatType}} {
		if f.v == nil {
			return nil, invalidParams(f.name + " is required")
		}
	}
	if err := requiredInt("duration_ms", p.DurationMS); err != nil {
		return nil, err
	}
	if err := requiredBool("enabled", p.Enabled); err != nil {
		return nil, err
	}
	if err := d.allowed(entitlement.AutoArchive); err != nil {
		return nil, err
	}
	r, err := d.Store.SetRule(ctx, store.Rule{
		ID: *p.RuleID, Scope: *p.Scope, Trigger: *p.Trigger, ChatType: *p.ChatType,
		Duration: time.Duration(*p.DurationMS) * time.Millisecond, Enabled: *p.Enabled,
	})
	if err != nil {
		return nil, err
	}
	d.poke()
	return toRuleJSON(r), nil
}

func autoArchiveDelete(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RuleID *int64 `json:"rule_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := requiredInt("rule_id", p.RuleID); err != nil {
		return nil, err
	}
	if err := d.Store.DeleteRule(ctx, *p.RuleID); err != nil {
		return nil, err
	}
	d.poke()
	return nil, nil
}

// Merged chats.

func mergeCreate(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		Name    *string   `json:"name"`
		RoomIDs *[]string `json:"room_ids"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if p.Name == nil {
		return nil, invalidParams("name is required")
	}
	if p.RoomIDs == nil {
		return nil, invalidParams("room_ids is required")
	}
	return d.Store.CreateMergedChat(ctx, *p.Name, *p.RoomIDs)
}

func mergeUpdate(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		MergeID    *string   `json:"merge_id"`
		Name       *string   `json:"name"`
		RoomIDs    *[]string `json:"room_ids"`
		LastRoomID *string   `json:"last_room_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("merge_id", p.MergeID); err != nil {
		return nil, err
	}
	if p.Name == nil {
		return nil, invalidParams("name is required")
	}
	if p.RoomIDs == nil {
		return nil, invalidParams("room_ids is required")
	}
	lastRoomID := ""
	if p.LastRoomID != nil {
		lastRoomID = *p.LastRoomID
	}
	return d.Store.UpdateMergedChat(ctx, *p.MergeID, *p.Name, *p.RoomIDs, lastRoomID)
}

func mergeDelete(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		MergeID *string `json:"merge_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("merge_id", p.MergeID); err != nil {
		return nil, err
	}
	return nil, d.Store.DeleteMergedChat(ctx, *p.MergeID)
}

func mergeList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	list, err := d.Store.ListMergedChats(ctx)
	if err != nil {
		return nil, err
	}
	return map[string]any{"merged_chats": list}, nil
}

func mergeSuggest(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	if err := decode(raw, &struct{}{}); err != nil {
		return nil, err
	}
	suggestions, err := d.Store.SuggestMergedChats(ctx)
	if err != nil {
		return nil, err
	}
	return map[string]any{"suggestions": suggestions}, nil
}
