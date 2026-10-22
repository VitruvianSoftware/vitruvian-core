// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package actions

import (
	"context"
	"encoding/json"
	"slices"
	"time"

	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// PollFeatures is what a chat allows in a new poll: at most MaxOptions options, each at most OptionMaxLength
// characters.
type PollFeatures struct{ MaxOptions, OptionMaxLength int }

// DisappearingFeatures is the disappearing-message timer a chat takes. Type is when the timer starts,
// "after_send" or "after_read"; Timers are the lengths Courier offers (besides off).
type DisappearingFeatures struct {
	Type   string
	Timers []time.Duration
}

// Features is what a person can do in one chat, as its bridge says (com.beeper.room_features). A level of partial
// or full support counts as supported; unsupported, dropped and rejected don't.
type Features struct {
	// Reply is a plain reply. Thread is a reply in a thread. ReplyIsThread says a reply becomes a thread reply:
	// the chat has threads and no plain replies (Slack, WhatsApp community announcement groups), so bridgev2
	// sends a reply as a reply in the thread of the message replied to (portal.go:1295 of mautrix v0.31.0).
	Reply, Thread, ReplyIsThread bool
	Edit                         bool
	EditMaxAge                   time.Duration // 0 = none
	EditMaxCount                 int           // 0 = none
	// Unsend is deleting my message for everyone. It is false where the network only deletes for me, even
	// though the bridge takes the redaction (Google Messages: see DeleteReachesPhone).
	Unsend       bool
	UnsendMaxAge time.Duration // 0 = none. bridgev2 doesn't check it; the engine must
	// DeleteReachesPhone says Delete for Me is also sent to the network (delete_for_me): Google Messages deletes
	// the message from the phone's own app, and from nowhere else.
	DeleteReachesPhone bool
	// HideDeletedPlaceholder says the network leaves no "deleted" placeholder (delete_hide_placeholder, Telegram).
	HideDeletedPlaceholder bool
	Poll                   *PollFeatures         // nil: no polls
	Disappearing           *DisappearingFeatures // nil: no disappearing timer
	// Formatting is the kinds the chat keeps, in richtext.Kinds order. A kind it doesn't keep is sent in its
	// plain form (richtext.Render).
	Formatting []richtext.Kind
	// MentionRoom says an @room mention reaches everyone in the chat (Slack). Elsewhere it is plain "@room" text.
	MentionRoom   bool
	MaxTextLength int // 0 = none advertised
	// Source is where the features came from: "stored" (the chat's com.beeper.room_features state), "network"
	// (the logged-in client, asked because nothing was stored) or "none" (NoFeatures).
	Source string
}

// The values of Features.Source.
const (
	SourceStored  = "stored"
	SourceNetwork = "network"
	SourceNone    = "none"
)

// NoFeatures is a chat with nothing stored and no logged-in client to ask: only send, reply and Delete for Me
// (which never leaves this Mac) are offered. Formatting is empty, not nil, so the wire always carries a list.
var NoFeatures = Features{Reply: true, Formatting: []richtext.Kind{}, Source: SourceNone}

// SignalTimers are the disappearing-message lengths Courier offers where the bridge advertises a timer type but no
// list (Signal: after_read, any length). Inferred (inventory 01 §5): the caps allow any length, so these are the
// choices Signal's own apps offer.
var SignalTimers = []time.Duration{30 * time.Second, 5 * time.Minute, time.Hour, 8 * time.Hour, 24 * time.Hour, 7 * 24 * time.Hour, 28 * 24 * time.Hour} // Inferred

// formattingKinds maps each formatting feature a bridge advertises to the richtext kind it keeps, in
// richtext.Kinds order.
var formattingKinds = []struct {
	feature event.FormattingFeature
	kind    richtext.Kind
}{
	{event.FmtBold, richtext.Bold},
	{event.FmtItalic, richtext.Italic},
	{event.FmtStrikethrough, richtext.Strike},
	{event.FmtInlineCode, richtext.Code},
	{event.FmtCodeBlock, richtext.Pre},
	{event.FmtBlockquote, richtext.Quote},
	{event.FmtUnorderedList, richtext.Bullets},
	{event.FmtOrderedList, richtext.Numbered},
	{event.FmtInlineLink, richtext.Link},
	{event.FmtUserLink, richtext.Mention},
	{event.FmtSpoiler, richtext.Spoiler},
}

// FeaturesOf reads a bridge's room features. Source is left empty for the caller to set. Nil is NoFeatures.
func FeaturesOf(rf *event.RoomFeatures) Features {
	if rf == nil {
		return NoFeatures
	}
	f := Features{
		Reply:                  rf.Reply.Partial(),
		Thread:                 rf.Thread.Partial(),
		Edit:                   rf.Edit.Partial(),
		EditMaxCount:           rf.EditMaxCount,
		Unsend:                 rf.Delete.Partial() && !rf.DeleteForMe,
		DeleteReachesPhone:     rf.DeleteForMe,
		HideDeletedPlaceholder: rf.DeleteHide,
		Formatting:             []richtext.Kind{},
		MentionRoom:            rf.Formatting[event.FmtAtRoomMention].Partial(),
		MaxTextLength:          rf.MaxTextLength,
	}
	f.ReplyIsThread = !f.Reply && f.Thread
	if rf.EditMaxAge != nil {
		f.EditMaxAge = rf.EditMaxAge.Duration
	}
	if rf.DeleteMaxAge != nil {
		f.UnsendMaxAge = rf.DeleteMaxAge.Duration
	}
	if rf.Poll.Partial() && rf.PollMaxOptions > 0 {
		f.Poll = &PollFeatures{MaxOptions: rf.PollMaxOptions, OptionMaxLength: rf.PollOptionMaxLength}
	}
	if dt := rf.DisappearingTimer; dt != nil && len(dt.Types) > 0 {
		d := &DisappearingFeatures{Type: string(dt.Types[0])}
		for _, t := range dt.Timers {
			d.Timers = append(d.Timers, t.Duration)
		}
		if len(d.Timers) == 0 && dt.Types[0] == event.DisappearingTypeAfterRead {
			d.Timers = slices.Clone(SignalTimers)
		}
		f.Disappearing = d
	}
	for _, m := range formattingKinds {
		if rf.Formatting[m.feature].Partial() {
			f.Formatting = append(f.Formatting, m.kind)
		}
	}
	return f
}

// Keeps reports whether the chat keeps formatting of kind k. It is the keep function richtext.Render takes.
func (f Features) Keeps(k richtext.Kind) bool { return slices.Contains(f.Formatting, k) }

// Features is what a person can do in a chat. It reads the chat's stored com.beeper.room_features state, which
// bridgev2 writes when it makes the room and again whenever the features change (Portal.UpdateCapabilities). Only
// when none is stored does it ask a logged-in client of the chat's network (GetCapabilities). With neither it is
// NoFeatures. An unknown chat is store.ErrNotFound.
func (a *Actions) Features(ctx context.Context, roomID string) (Features, error) {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return Features{}, err
	}
	if !ok {
		return Features{}, store.ErrNotFound
	}
	rf, err := a.storedFeatures(ctx, roomID, room.Network)
	if err != nil {
		return Features{}, err
	}
	if rf != nil {
		f := FeaturesOf(rf)
		f.Source = SourceStored
		return f, nil
	}
	if h, ok := a.eng.Host(room.Network); ok {
		if rf = clientFeatures(ctx, h, roomID); rf != nil {
			f := FeaturesOf(rf)
			f.Source = SourceNetwork
			return f, nil
		}
	}
	return NoFeatures, nil
}

// storedFeatures is the chat's com.beeper.room_features state, or nil when none is stored. bridgev2 keys it by
// its bridge ID, which is the network's name (host.Start), or by "" when no_bridge_info_state_key is set.
//
// A row that doesn't read as features (JSON null, or something unreadable) counts as none, so the client is
// asked rather than the chat losing every action until the bridge writes it again.
func (a *Actions) storedFeatures(ctx context.Context, roomID, network string) (*event.RoomFeatures, error) {
	for _, key := range []string{network, ""} {
		raw, ok, err := a.s.GetState(ctx, roomID, event.StateBeeperRoomFeatures.Type, key)
		if err != nil {
			return nil, err
		}
		if !ok {
			continue
		}
		var rf *event.RoomFeatures
		if json.Unmarshal(raw, &rf) == nil && rf != nil {
			return rf, nil
		}
	}
	return nil, nil
}

// clientFeatures asks a logged-in client of h's network what the chat's portal can do: the portal's own login
// first, as bridgev2 asks it. Nil when the bridge has no portal for the room or no login is logged in.
func clientFeatures(ctx context.Context, h *host.Host, roomID string) *event.RoomFeatures {
	portal, err := h.Bridge.GetPortalByMXID(ctx, id.RoomID(roomID))
	if err != nil || portal == nil {
		return nil
	}
	var pick *bridgev2.UserLogin
	for _, l := range myLogins(h) {
		if !l.Client.IsLoggedIn() {
			continue
		}
		if pick == nil || l.ID == portal.Receiver {
			pick = l
		}
	}
	if pick == nil {
		return nil
	}
	return pick.Client.GetCapabilities(ctx, portal)
}
