// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package rpc

// Protocol 4's message actions: what a chat can do (room.features), its people (room.members), its disappearing
// timer, and edit, unsend, delete for me, forward, undo send, bookmarks, edit history, send later and polls. Each
// handler has the shape of the others: strict params, the required ones checked by name, then one actions or store
// call whose sentinel errors map to their codes (sentinels). Nothing here logs what a message says, nor a name.

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/entitlement"
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/searchtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

const (
	// maxMembersLimit is room.members' largest limit; defaultMembersLimit its default.
	maxMembersLimit     = 50
	defaultMembersLimit = 20
)

// holdWindowsReason is the reason a hold_ms that isn't one of actions.HoldWindows is refused with.
var holdWindowsReason = func() string {
	ms := make([]string, 0, len(actions.HoldWindows))
	for _, h := range actions.HoldWindows {
		ms = append(ms, fmt.Sprint(h.Milliseconds()))
	}
	return "hold_ms must be one of " + strings.Join(ms, ", ")
}()

// hold is hold_ms as an undo-send window: one of actions.HoldWindows, 0 when left out. Above 0 it is part of a
// plan (undo send): not_entitled when the plan doesn't include it, before anything is looked up or stored.
func (d *Deps) hold(ms *int64) (time.Duration, error) {
	if ms == nil {
		return 0, nil
	}
	h := time.Duration(*ms) * time.Millisecond
	if *ms < 0 || !slices.Contains(actions.HoldWindows, h) {
		return 0, invalidParams(holdWindowsReason)
	}
	if h > 0 {
		if err := d.allowed(entitlement.UndoSend); err != nil {
			return 0, err
		}
	}
	return h, nil
}

// textParam checks a message's text, there and at most actions.MaxTextBytes, and its formatting ranges
// (richtext.Check), before anything is looked up: a bad parameter is -32602 whatever the message or chat. An empty
// text is the action's to refuse (there is nothing to send).
func textParam(text *string, ents []richtext.Entity) error {
	if text == nil {
		return invalidParams("text is required")
	}
	if len(*text) > actions.MaxTextBytes {
		return invalidParams("text is too long")
	}
	if richtext.Check(*text, ents) != nil {
		return invalidParams("entities don't fit the text")
	}
	return nil
}

// replyAndThread checks that the message a new one replies to, and the thread it goes in, are in roomID.
func (d *Deps) replyAndThread(ctx context.Context, roomID, replyTo, threadRoot string) error {
	for _, id := range []string{replyTo, threadRoot} {
		if id == "" {
			continue
		}
		if err := d.eventIn(ctx, roomID, id); err != nil {
			return err
		}
	}
	return nil
}

func nonNilEntities(ents []richtext.Entity) []richtext.Entity {
	if ents == nil {
		return []richtext.Entity{}
	}
	return ents
}

// optional is s as a string|null: null when it is "".
func optional(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// What a chat can do.

type pollFeaturesJSON struct {
	MaxOptions      int `json:"max_options"`
	OptionMaxLength int `json:"option_max_length"`
}

type disappearingFeaturesJSON struct {
	Type     string  `json:"type"`
	TimersMS []int64 `json:"timers_ms"`
}

type disappearingTimerJSON struct {
	Type    string `json:"type"`
	TimerMS int64  `json:"timer_ms"`
}

type chatFeatures struct {
	Reply                  bool                      `json:"reply"`
	Thread                 bool                      `json:"thread"`
	ReplyIsThread          bool                      `json:"reply_is_thread"`
	Edit                   bool                      `json:"edit"`
	EditMaxAgeMS           int64                     `json:"edit_max_age_ms"`
	EditMaxCount           int                       `json:"edit_max_count"`
	Unsend                 bool                      `json:"unsend"`
	UnsendMaxAgeMS         int64                     `json:"unsend_max_age_ms"`
	DeleteReachesPhone     bool                      `json:"delete_reaches_phone"`
	HideDeletedPlaceholder bool                      `json:"hide_deleted_placeholder"`
	Poll                   *pollFeaturesJSON         `json:"poll"`
	Disappearing           *disappearingFeaturesJSON `json:"disappearing"`
	CurrentTimer           *disappearingTimerJSON    `json:"current_timer"`
	Formatting             []string                  `json:"formatting"`
	MentionRoom            bool                      `json:"mention_room"`
	MaxTextLength          int                       `json:"max_text_length"`
	Source                 string                    `json:"source"`
}

func roomFeatures(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if _, err := d.room(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	f, err := d.Actions.Features(ctx, *p.RoomID)
	if err != nil {
		return nil, err
	}
	out := chatFeatures{
		Reply: f.Reply, Thread: f.Thread, ReplyIsThread: f.ReplyIsThread, Edit: f.Edit,
		EditMaxAgeMS: f.EditMaxAge.Milliseconds(), EditMaxCount: f.EditMaxCount, Unsend: f.Unsend,
		UnsendMaxAgeMS: f.UnsendMaxAge.Milliseconds(), DeleteReachesPhone: f.DeleteReachesPhone,
		HideDeletedPlaceholder: f.HideDeletedPlaceholder, Formatting: []string{}, MentionRoom: f.MentionRoom,
		// Ruling 24: the engine's own limit, in UTF-8 bytes, which is what it refuses by. A network's own (shorter)
		// limit is enforced by the network failing the message.
		MaxTextLength: actions.MaxTextBytes, Source: f.Source,
	}
	if f.Poll != nil {
		out.Poll = &pollFeaturesJSON{MaxOptions: f.Poll.MaxOptions, OptionMaxLength: f.Poll.OptionMaxLength}
	}
	if f.Disappearing != nil {
		dj := &disappearingFeaturesJSON{Type: f.Disappearing.Type, TimersMS: []int64{}}
		for _, t := range f.Disappearing.Timers {
			dj.TimersMS = append(dj.TimersMS, t.Milliseconds())
		}
		out.Disappearing = dj
	}
	for _, k := range f.Formatting {
		out.Formatting = append(out.Formatting, string(k))
	}
	if out.CurrentTimer, err = d.currentTimer(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	return out, nil
}

// currentTimer is the chat's stored com.beeper.disappearing_timer state, the timer Send gives new messages; nil
// when it has none, or one that is off.
func (d *Deps) currentTimer(ctx context.Context, roomID string) (*disappearingTimerJSON, error) {
	raw, ok, err := d.Store.GetState(ctx, roomID, event.StateBeeperDisappearingTimer.Type, "")
	if err != nil || !ok {
		return nil, err
	}
	var t event.BeeperDisappearingTimer
	if json.Unmarshal(raw, &t) != nil || t.Type == "" || t.Type == event.DisappearingTypeNone || t.Timer.Duration <= 0 {
		return nil, nil
	}
	return &disappearingTimerJSON{Type: string(t.Type), TimerMS: t.Timer.Milliseconds()}, nil
}

type memberJSON struct {
	UserID     string `json:"user_id"`
	Name       string `json:"name"`
	AvatarPath string `json:"avatar_path"`
}

// roomMembers lists the people in a chat whose name matches query, for a mention: the network's people only (not
// me, not the bridge's bot), in the chat (not left or banned), by name. Each word of the query, folded as search
// folds it (accents, case), must begin a word of the name; an empty query matches everyone.
func roomMembers(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
		Query  *string `json:"query"`
		Limit  *int    `json:"limit"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.Query == nil {
		return nil, invalidParams("query is required")
	}
	limit := defaultMembersLimit
	if p.Limit != nil {
		if *p.Limit < 1 || *p.Limit > maxMembersLimit {
			return nil, invalidParams(fmt.Sprintf("limit must be 1 to %d", maxMembersLimit))
		}
		limit = *p.Limit
	}
	r, err := d.room(ctx, *p.RoomID)
	if err != nil {
		return nil, err
	}
	members, err := d.Store.Members(ctx, r.ID)
	if err != nil {
		return nil, err
	}
	want := searchtext.Words(searchtext.Normalize(*p.Query))
	type found struct {
		m   memberJSON
		key string
	}
	var all []found
	for userID, content := range members {
		if _, ghost := ids.ParseGhostMXID(r.Network, id.UserID(userID)); !ghost {
			continue
		}
		var m struct {
			Membership  string `json:"membership"`
			DisplayName string `json:"displayname"`
			AvatarURL   string `json:"avatar_url"`
		}
		_ = json.Unmarshal(content, &m) // a row we can't read still says they're in the chat
		if m.Membership == "leave" || m.Membership == "ban" {
			continue
		}
		name, avatar := m.DisplayName, m.AvatarURL
		if name == "" || avatar == "" {
			pn, pa, _, err := d.Store.GetProfile(ctx, userID)
			if err != nil {
				return nil, err
			}
			name, avatar = cmp.Or(name, pn), cmp.Or(avatar, pa)
		}
		if name == "" {
			name = localpart(userID)
		}
		words := searchtext.Words(searchtext.Normalize(name))
		if !everyWordBegins(want, words) {
			continue
		}
		all = append(all, found{memberJSON{UserID: userID, Name: name, AvatarPath: d.path(avatar)}, strings.Join(words, " ")})
	}
	slices.SortFunc(all, func(a, b found) int {
		if c := strings.Compare(a.key, b.key); c != 0 {
			return c
		}
		return strings.Compare(a.m.UserID, b.m.UserID)
	})
	out := make([]memberJSON, 0, min(len(all), limit))
	for _, f := range all[:min(len(all), limit)] {
		out = append(out, f.m)
	}
	return map[string]any{"members": out}, nil
}

// everyWordBegins reports whether each of want begins one of words.
func everyWordBegins(want, words []string) bool {
	for _, w := range want {
		if !slices.ContainsFunc(words, func(n string) bool { return strings.HasPrefix(n, w) }) {
			return false
		}
	}
	return true
}

func roomSetDisappearing(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID  *string `json:"room_id"`
		Type    *string `json:"type"`
		TimerMS *int64  `json:"timer_ms"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.Type == nil {
		return nil, invalidParams("type is required")
	}
	if err := requiredInt("timer_ms", p.TimerMS); err != nil {
		return nil, err
	}
	if *p.TimerMS < 0 {
		return nil, invalidParams("timer_ms must not be negative")
	}
	if _, err := d.sendableRoom(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	return nil, d.Actions.SetDisappearing(ctx, *p.RoomID, *p.Type, time.Duration(*p.TimerMS)*time.Millisecond)
}

// Changing a message.

func messageEdit(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		EventID  *string           `json:"event_id"`
		Text     *string           `json:"text"`
		Entities []richtext.Entity `json:"entities"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("event_id", p.EventID); err != nil {
		return nil, err
	}
	if err := textParam(p.Text, p.Entities); err != nil {
		return nil, err
	}
	e, err := d.eventByID(ctx, *p.EventID)
	if err != nil {
		return nil, err
	}
	if _, err := d.sendableRoom(ctx, e.RoomID); err != nil {
		return nil, err
	}
	eventID, err := d.Actions.Edit(ctx, e.EventID, *p.Text, p.Entities)
	if err != nil {
		return nil, err
	}
	return sent{EventID: eventID}, nil
}

func messageUnsend(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	e, err := d.event(ctx, raw)
	if err != nil {
		return nil, err
	}
	if _, err := d.sendableRoom(ctx, e.RoomID); err != nil {
		return nil, err
	}
	eventID, err := d.Actions.Unsend(ctx, e.EventID)
	if err != nil {
		return nil, err
	}
	return sent{EventID: eventID}, nil
}

func messageDeleteForMe(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	e, err := d.event(ctx, raw)
	if err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	return nil, d.Actions.DeleteForMe(ctx, e.EventID)
}

type forwarded struct {
	RoomID  string `json:"room_id"`
	EventID string `json:"event_id"`
}

type forwardFailure struct {
	RoomID string `json:"room_id"`
	Code   int    `json:"code"`
}

type forwardResult struct {
	Sent   []forwarded      `json:"sent"`
	Failed []forwardFailure `json:"failed"`
}

// messageForward sends a copy of a message to 1 to actions.MaxForwardRooms chats, each named once (a chat named
// twice gets one copy). More is one -32602, before anything is sent. Each chat that can't take a copy fails on its
// own, with the code it would have got alone; a message that can't be forwarded at all (a poll, a deleted message)
// is -32023 for the whole call.
func messageForward(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		EventID *string   `json:"event_id"`
		RoomIDs *[]string `json:"room_ids"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("event_id", p.EventID); err != nil {
		return nil, err
	}
	if p.RoomIDs == nil {
		return nil, invalidParams("room_ids is required")
	}
	var rooms []string
	for _, r := range *p.RoomIDs {
		if !slices.Contains(rooms, r) {
			rooms = append(rooms, r)
		}
	}
	if len(rooms) < 1 || len(rooms) > actions.MaxForwardRooms {
		return nil, invalidParams(fmt.Sprintf("room_ids must name 1 to %d chats", actions.MaxForwardRooms))
	}
	e, err := d.eventByID(ctx, *p.EventID)
	if err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	failed := map[string]int{}
	var sendable []string
	for _, r := range rooms {
		if _, err := d.sendableRoom(ctx, r); err != nil {
			failed[r] = toError(err).Code
			continue
		}
		sendable = append(sendable, r)
	}
	res := actions.ForwardResult{Sent: map[string]string{}, Failed: map[string]error{}}
	if len(sendable) > 0 {
		res = d.Actions.Forward(ctx, e.EventID, sendable)
	}
	out := forwardResult{Sent: []forwarded{}, Failed: []forwardFailure{}}
	for _, r := range rooms {
		if code, ok := failed[r]; ok {
			out.Failed = append(out.Failed, forwardFailure{RoomID: r, Code: code})
			continue
		}
		if id, ok := res.Sent[r]; ok {
			out.Sent = append(out.Sent, forwarded{RoomID: r, EventID: id})
			continue
		}
		err := res.Failed[r]
		if errors.Is(err, actions.ErrNotSupported) {
			return nil, newError(CodeNotSupported) // the message itself can't be forwarded: nothing was sent anywhere
		}
		ce, unknown := classify(err)
		if unknown {
			d.Log.Error().Str("method", "message.forward").Err(err).Msg("a copy failed inside the engine")
		}
		out.Failed = append(out.Failed, forwardFailure{RoomID: r, Code: ce.Code})
	}
	return out, nil
}

// Undo send.

type draftJSON struct {
	Text       string            `json:"text"`
	Entities   []richtext.Entity `json:"entities"`
	ReplyTo    *string           `json:"reply_to"`
	ThreadRoot *string           `json:"thread_root"`
}

// messageUndo takes back a held message before its window ends and gives the composer back what was typed. Once it
// has gone it is -32025. Undo needs no plan: a lapsed one never strands a held message.
func messageUndo(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	e, err := d.event(ctx, raw)
	if err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	held, err := d.Actions.Undo(ctx, e.EventID)
	if err != nil {
		return nil, err
	}
	src, ok := actions.SourceOf(held.Content)
	if !ok { // held without what was typed (not by this engine): its plain body is the next best thing
		var c struct {
			Body string `json:"body"`
		}
		_ = json.Unmarshal(held.Content, &c)
		src.Text = c.Body
	}
	return draftJSON{Text: src.Text, Entities: nonNilEntities(src.Entities), ReplyTo: optional(src.ReplyTo), ThreadRoot: optional(src.ThreadRoot)}, nil
}

// messageSendHeld sends the messages held in a chat now, or with no room_id every chat's, without waiting for their
// windows to end.
func messageSendHeld(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if p.RoomID != nil {
		if err := required("room_id", p.RoomID); err != nil {
			return nil, err
		}
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	if p.RoomID != nil {
		return nil, d.Actions.SendHeldNow(ctx, *p.RoomID)
	}
	claimed, err := d.Store.ClaimHeld(ctx, "")
	if err != nil {
		return nil, err
	}
	for _, e := range claimed {
		d.Actions.HandOff(ctx, e)
	}
	return nil, nil
}

// Bookmarks and edit history.

func messageSetBookmarked(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		EventID *string `json:"event_id"`
		On      *bool   `json:"on"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("event_id", p.EventID); err != nil {
		return nil, err
	}
	if err := requiredBool("on", p.On); err != nil {
		return nil, err
	}
	return nil, d.Store.SetBookmarked(ctx, *p.EventID, *p.On) // unknown or deleted: store.ErrNotFound
}

type versionJSON struct {
	Body          string `json:"body"`
	FormattedBody string `json:"formatted_body"`
	TS            int64  `json:"ts"`
}

func messageHistory(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	e, err := d.event(ctx, raw)
	if err != nil {
		return nil, err
	}
	versions, err := d.Store.EditHistory(ctx, e.EventID) // a deleted message: store.ErrNotFound
	if err != nil {
		return nil, err
	}
	out := make([]versionJSON, 0, len(versions))
	for _, v := range versions {
		out = append(out, versionJSON{Body: v.Body, FormattedBody: v.FormattedBody, TS: ms(v.TS)})
	}
	return map[string]any{"versions": out}, nil
}

// Send later.

type scheduledJSON struct {
	OutboxID   int64             `json:"outbox_id"`
	RoomID     string            `json:"room_id"`
	Text       string            `json:"text"`
	Entities   []richtext.Entity `json:"entities"`
	ReplyTo    *string           `json:"reply_to"`
	ThreadRoot *string           `json:"thread_root"`
	DueAt      int64             `json:"due_at"`
	Condition  string            `json:"condition"`
	State      string            `json:"state"`
	SetAt      int64             `json:"set_at"`
}

// toScheduled is a scheduled message on the wire, with what was typed (actions.SourceOf), not what it renders to.
func toScheduled(sc store.Scheduled) scheduledJSON {
	src, ok := actions.SourceOf(sc.Content)
	if !ok {
		var c struct {
			Body string `json:"body"`
		}
		_ = json.Unmarshal(sc.Content, &c)
		src.Text = c.Body
	}
	return scheduledJSON{
		OutboxID: sc.ID, RoomID: sc.RoomID, Text: src.Text, Entities: nonNilEntities(src.Entities),
		ReplyTo: optional(src.ReplyTo), ThreadRoot: optional(src.ThreadRoot), DueAt: ms(sc.DueAt),
		Condition: sc.Condition, State: sc.State, SetAt: ms(sc.SetAt),
	}
}

func messageSchedule(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID     *string           `json:"room_id"`
		Text       *string           `json:"text"`
		Entities   []richtext.Entity `json:"entities"`
		ReplyTo    string            `json:"reply_to"`
		ThreadRoot string            `json:"thread_root"`
		DueAt      *int64            `json:"due_at"`
		Condition  *string           `json:"condition"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if err := textParam(p.Text, p.Entities); err != nil {
		return nil, err
	}
	if err := requiredInt("due_at", p.DueAt); err != nil {
		return nil, err
	}
	if err := required("condition", p.Condition); err != nil {
		return nil, err
	}
	if err := d.allowed(entitlement.SendLater); err != nil {
		return nil, err
	}
	if _, err := d.room(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	if err := d.replyAndThread(ctx, *p.RoomID, p.ReplyTo, p.ThreadRoot); err != nil {
		return nil, err
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	o := actions.SendOptions{Entities: p.Entities, ReplyTo: p.ReplyTo, ThreadRoot: p.ThreadRoot}
	sc, err := d.Actions.Schedule(ctx, *p.RoomID, *p.Text, o, time.UnixMilli(*p.DueAt), *p.Condition)
	if err != nil {
		return nil, err
	}
	d.poke() // Ruling 22: one due before the loop next wakes on its own is sent on time
	return toScheduled(sc), nil
}

// scheduledList lists a chat's scheduled messages, or with no room_id every chat's, in any state, soonest first. The
// answer stays under maxPageBytes: there is no next page, and in the rare case of more than fits, the soonest are
// the ones listed.
func scheduledList(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID *string `json:"room_id"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	roomID := ""
	if p.RoomID != nil {
		if err := required("room_id", p.RoomID); err != nil {
			return nil, err
		}
		if _, err := d.room(ctx, *p.RoomID); err != nil {
			return nil, err
		}
		roomID = *p.RoomID
	}
	all, err := d.Store.ScheduledIn(ctx, roomID)
	if err != nil {
		return nil, err
	}
	out := make([]scheduledJSON, 0, len(all))
	for _, sc := range all {
		out = append(out, toScheduled(sc))
	}
	return map[string]any{"scheduled": out[:fitting(out, maxPageBytes-pageSlack)]}, nil
}

// outboxID reads an OutboxIDParams-shaped request's outbox_id.
func outboxID(raw json.RawMessage) (int64, error) {
	var p struct {
		OutboxID *int64 `json:"outbox_id"`
	}
	if err := decode(raw, &p); err != nil {
		return 0, err
	}
	if err := requiredInt("outbox_id", p.OutboxID); err != nil {
		return 0, err
	}
	return *p.OutboxID, nil
}

// scheduled finds scheduled message id, in any state, or not_found.
func (d *Deps) scheduled(ctx context.Context, id int64) (store.Scheduled, error) {
	all, err := d.Store.ScheduledIn(ctx, "")
	if err != nil {
		return store.Scheduled{}, err
	}
	for _, sc := range all {
		if sc.ID == id {
			return sc, nil
		}
	}
	return store.Scheduled{}, errNotFound
}

// scheduledUpdate changes a scheduled message: its time, its text (with its ranges), the ranges of the text it has,
// or its condition. It needs no plan: a lapsed one never strands a scheduled message, which can still be moved,
// changed, sent now or deleted.
func scheduledUpdate(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		OutboxID  *int64            `json:"outbox_id"`
		DueAt     *int64            `json:"due_at"`
		Text      *string           `json:"text"`
		Entities  []richtext.Entity `json:"entities"`
		Condition *string           `json:"condition"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := requiredInt("outbox_id", p.OutboxID); err != nil {
		return nil, err
	}
	if p.Text != nil {
		if err := textParam(p.Text, p.Entities); err != nil {
			return nil, err
		}
	}
	if d.Actions == nil {
		return nil, errMissing
	}
	var due *time.Time
	if p.DueAt != nil {
		t := time.UnixMilli(*p.DueAt)
		due = &t
	}
	sc, err := d.Actions.UpdateScheduled(ctx, *p.OutboxID, due, p.Text, p.Entities, p.Condition)
	if err != nil {
		return nil, err
	}
	d.poke() // Ruling 22: a message moved sooner is sent on time
	return toScheduled(sc), nil
}

// scheduledSendNow sends a scheduled message now, whatever its state. Its chat's network must be running and
// linked, so Send Now is refused rather than turned into a failed message.
func scheduledSendNow(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	id, err := outboxID(raw)
	if err != nil {
		return nil, err
	}
	sc, err := d.scheduled(ctx, id)
	if err != nil {
		return nil, err
	}
	r, err := d.sendableRoom(ctx, sc.RoomID)
	if err != nil {
		return nil, err
	}
	if !d.linked(r.Network) {
		return nil, newError(CodeNotLinked)
	}
	return nil, d.Actions.SendScheduledNow(ctx, id)
}

func scheduledDelete(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	id, err := outboxID(raw)
	if err != nil {
		return nil, err
	}
	return nil, d.Store.DeleteScheduled(ctx, id)
}

// Polls.

func pollCreate(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		RoomID   *string   `json:"room_id"`
		Question *string   `json:"question"`
		Options  *[]string `json:"options"`
		Multiple *bool     `json:"multiple"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("room_id", p.RoomID); err != nil {
		return nil, err
	}
	if p.Question == nil {
		return nil, invalidParams("question is required")
	}
	if p.Options == nil {
		return nil, invalidParams("options is required")
	}
	if err := requiredBool("multiple", p.Multiple); err != nil {
		return nil, err
	}
	if _, err := d.sendableRoom(ctx, *p.RoomID); err != nil {
		return nil, err
	}
	eventID, err := d.Actions.CreatePoll(ctx, *p.RoomID, *p.Question, *p.Options, *p.Multiple)
	if err != nil {
		return nil, err
	}
	return sent{EventID: eventID}, nil
}

func pollVote(ctx context.Context, d *Deps, raw json.RawMessage) (any, error) {
	var p struct {
		EventID   *string   `json:"event_id"`
		OptionIDs *[]string `json:"option_ids"`
	}
	if err := decode(raw, &p); err != nil {
		return nil, err
	}
	if err := required("event_id", p.EventID); err != nil {
		return nil, err
	}
	if p.OptionIDs == nil {
		return nil, invalidParams("option_ids is required")
	}
	e, err := d.eventByID(ctx, *p.EventID)
	if err != nil {
		return nil, err
	}
	if _, err := d.sendableRoom(ctx, e.RoomID); err != nil {
		return nil, err
	}
	eventID, err := d.Actions.Vote(ctx, e.EventID, *p.OptionIDs)
	if err != nil {
		return nil, err
	}
	return sent{EventID: eventID}, nil
}
