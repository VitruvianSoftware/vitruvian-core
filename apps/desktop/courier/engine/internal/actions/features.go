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
	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// GroupCapabilities reports which of the six bridgev2 group and chat-management interfaces a NetworkAPI implements.
type GroupCapabilities struct {
	SetName     bool
	SetTopic    bool
	SetAvatar   bool
	Membership  bool
	PowerLevels bool
	DeleteChat  bool
}

// GroupCapabilitiesOf derives group and chat-management support solely by type-asserting api against the six
// bridgev2 interfaces.
func GroupCapabilitiesOf(api bridgev2.NetworkAPI) GroupCapabilities {
	if api == nil {
		return GroupCapabilities{}
	}
	_, hasName := api.(bridgev2.RoomNameHandlingNetworkAPI)
	_, hasTopic := api.(bridgev2.RoomTopicHandlingNetworkAPI)
	_, hasAvatar := api.(bridgev2.RoomAvatarHandlingNetworkAPI)
	_, hasMembership := api.(bridgev2.MembershipHandlingNetworkAPI)
	_, hasPL := api.(bridgev2.PowerLevelHandlingNetworkAPI)
	_, hasDelete := api.(bridgev2.DeleteChatHandlingNetworkAPI)
	return GroupCapabilities{
		SetName:     hasName,
		SetTopic:    hasTopic,
		SetAvatar:   hasAvatar,
		Membership:  hasMembership,
		PowerLevels: hasPL,
		DeleteChat:  hasDelete,
	}
}

// PollFeatures is what a chat allows in a new poll: at most MaxOptions options, each at most OptionMaxLength
// characters.
type PollFeatures struct {
	MaxOptions      int `json:"max_options"`
	OptionMaxLength int `json:"option_max_length"`
}

// DisappearingFeatures is the disappearing-message timer a chat takes. Type is when the timer starts,
// "after_send" or "after_read"; Timers are the lengths Courier offers (besides off).
type DisappearingFeatures struct {
	Type   string          `json:"type"`
	Timers []time.Duration `json:"timers_ms"`
}

// DisappearingTimer is the disappearing-message timer currently active in a chat.
type DisappearingTimer struct {
	Type    string `json:"type"`
	TimerMS int64  `json:"timer_ms"`
}

// FileKindFeatures summarizes a bridge's event.FileFeatures for one media kind.
type FileKindFeatures struct {
	Supported        bool     `json:"supported"`
	MimeTypes        []string `json:"mime_types,omitempty"`
	Caption          bool     `json:"caption"`
	MaxCaptionLength int      `json:"max_caption_length,omitempty"`
	MaxSize          int64    `json:"max_size,omitempty"`
	MaxDurationSec   int      `json:"max_duration_sec,omitempty"`
}

// MediaCapFeature summarizes sticker or GIF capabilities from a bridge's event.RoomFeatures.File map.
type MediaCapFeature struct {
	Supported        bool     `json:"supported"`
	MimeTypes        []string `json:"mime_types"`
	Captions         bool     `json:"captions"`
	MaxCaptionLength int      `json:"max_caption_length,omitempty"`
	MaxSize          int64    `json:"max_size,omitempty"`
}

// Features is what a person can do in one chat, as its bridge says (com.beeper.room_features). A level of partial
// or full support counts as supported; unsupported, dropped and rejected don't.
type Features struct {
	// Reply is a plain reply. Thread is a reply in a thread. ReplyIsThread says a reply becomes a thread reply:
	// the chat has threads and no plain replies (Slack, WhatsApp community announcement groups), so bridgev2
	// sends a reply as a reply in the thread of the message replied to (portal.go:1295 of mautrix v0.31.0).
	Reply         bool          `json:"reply"`
	Thread        bool          `json:"thread"`
	ReplyIsThread bool          `json:"reply_is_thread"`
	Edit          bool          `json:"edit"`
	EditMaxAge    time.Duration `json:"edit_max_age_ms"` // 0 = none
	EditMaxCount  int           `json:"edit_max_count"`  // 0 = none
	// Unsend is deleting my message for everyone. It is false where the network only deletes for me, even
	// though the bridge takes the redaction (Google Messages: see DeleteReachesPhone).
	Unsend       bool          `json:"unsend"`
	UnsendMaxAge time.Duration `json:"unsend_max_age_ms"` // 0 = none. bridgev2 doesn't check it; the engine must
	// DeleteReachesPhone says Delete for Me is also sent to the network (delete_for_me): Google Messages deletes
	// the message from the phone's own app, and from nowhere else.
	DeleteReachesPhone bool `json:"delete_reaches_phone"`
	// HideDeletedPlaceholder says the network leaves no "deleted" placeholder (delete_hide_placeholder, Telegram).
	HideDeletedPlaceholder bool                  `json:"hide_deleted_placeholder"`
	Poll                   *PollFeatures         `json:"poll"`          // nil: no polls
	Disappearing           *DisappearingFeatures `json:"disappearing"`  // nil: no disappearing timer
	CurrentTimer           *DisappearingTimer    `json:"current_timer"` // nil: off
	// Formatting is the kinds the chat keeps, in richtext.Kinds order. A kind it doesn't keep is sent in its
	// plain form (richtext.Render).
	Formatting []richtext.Kind `json:"formatting"`
	// MentionRoom says an @room mention reaches everyone in the chat (Slack). Elsewhere it is plain "@room" text.
	MentionRoom   bool `json:"mention_room"`
	MaxTextLength int  `json:"max_text_length"` // 0 = none advertised
	// Source is where the features came from: "stored" (the chat's com.beeper.room_features state), "network"
	// (the logged-in client, asked because nothing was stored) or "none" (NoFeatures).
	Source string `json:"source"`

	CanSetName        bool `json:"can_set_name"`
	CanSetTopic       bool `json:"can_set_topic"`
	CanSetAvatar      bool `json:"can_set_avatar"`
	CanInvite         bool `json:"can_invite"`
	CanKick           bool `json:"can_kick"`
	CanSetAdmin       bool `json:"can_set_admin"`
	CanLeave          bool `json:"can_leave"`
	CanDelete         bool `json:"can_delete"`
	DeleteLeavesGroup bool `json:"delete_leaves_group"`

	ImageFeatures         *FileKindFeatures `json:"image_features,omitempty"`
	VideoFeatures         *FileKindFeatures `json:"video_features,omitempty"`
	AudioFeatures         *FileKindFeatures `json:"audio_features,omitempty"`
	VoiceFeatures         *FileKindFeatures `json:"voice_features,omitempty"`
	FileFeatures          *FileKindFeatures `json:"file_features,omitempty"`
	GIFFeatures           *FileKindFeatures `json:"gif_features,omitempty"`
	StickerFeatures       *FileKindFeatures `json:"sticker_features,omitempty"`
	Sticker               MediaCapFeature   `json:"sticker"`
	GIF                   MediaCapFeature   `json:"gif"`
	LocationSupported     bool              `json:"location_supported"`
	LinkPreviewsSupported bool              `json:"link_previews_supported"`
}

// The values of Features.Source.
const (
	SourceStored  = "stored"
	SourceNetwork = "network"
	SourceNone    = "none"
)

// NoFeatures is a chat with nothing stored and no logged-in client to ask: only send, reply and Delete for Me
// (which never leaves this Mac) are offered. Formatting is empty, not nil, so the wire always carries a list.
var NoFeatures = Features{
	Reply:      true,
	Formatting: []richtext.Kind{},
	Source:     SourceNone,
	Sticker:    MediaCapFeature{MimeTypes: []string{}},
	GIF:        MediaCapFeature{MimeTypes: []string{}},
}

// deleteLeavesGroup lists the bridges whose HandleMatrixDeleteChat leaves a group chat before deleting it:
//   - mautrix-whatsapp v0.2609.0 pkg/connector/handlematrix.go:670-693 calls wa.Client.LeaveGroup when
//     chatJID.Server == types.GroupServer and the user is still joined.
//   - mautrix-signal v0.2609.0 pkg/connector/handlematrix.go:731 sends a sync delete message only and does not leave.
//   - mautrix-telegram v0.2609.0 pkg/connector/handlematrix.go:1176 deletes history or the chat without leaving first.
var deleteLeavesGroup = map[string]bool{
	"whatsapp": true,
}

// groupDeleteNeedsEveryone lists the bridges whose HandleMatrixDeleteChat refuses group or channel deletion unless
// DeleteForEveryone is set (which Courier never sets):
//   - mautrix-telegram v0.2609.0 pkg/connector/handlematrix.go:1176-1211 returns an error for PeerTypeChat and
//     PeerTypeChannel when !msg.Content.DeleteForEveryone.
var groupDeleteNeedsEveryone = map[string]bool{
	"telegram": true,
}

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
	if rf.File != nil {
		f.ImageFeatures = convertFileFeatures(rf.File[event.MsgImage])
		f.VideoFeatures = convertFileFeatures(rf.File[event.MsgVideo])
		f.AudioFeatures = convertFileFeatures(rf.File[event.MsgAudio])
		f.VoiceFeatures = convertFileFeatures(rf.File[event.CapMsgVoice])
		f.FileFeatures = convertFileFeatures(rf.File[event.MsgFile])
		f.GIFFeatures = convertFileFeatures(rf.File[event.CapMsgGIF])
		f.StickerFeatures = convertFileFeatures(rf.File[event.CapMsgSticker])
	}
	f.Sticker = mediaCapFromFileKind(f.StickerFeatures)
	f.GIF = mediaCapFromFileKind(f.GIFFeatures)
	f.LocationSupported = rf.LocationMessage.Partial()
	f.LinkPreviewsSupported = rf.Formatting[event.FmtInlineLink].Partial()
	return f
}

func mediaCapFromFileKind(fk *FileKindFeatures) MediaCapFeature {
	if fk == nil || !fk.Supported || len(fk.MimeTypes) == 0 {
		return MediaCapFeature{MimeTypes: []string{}}
	}
	return MediaCapFeature{
		Supported:        fk.Supported,
		MimeTypes:        slices.Clone(fk.MimeTypes),
		Captions:         fk.Caption,
		MaxCaptionLength: fk.MaxCaptionLength,
		MaxSize:          fk.MaxSize,
	}
}

func convertFileFeatures(ff *event.FileFeatures) *FileKindFeatures {
	if ff == nil {
		return nil
	}
	var mimes []string
	for mime, cap := range ff.MimeTypes {
		if cap >= event.CapLevelPartialSupport {
			mimes = append(mimes, mime)
		}
	}
	if len(mimes) == 0 {
		return nil
	}
	slices.Sort(mimes)
	out := &FileKindFeatures{
		Supported:        true,
		MimeTypes:        mimes,
		Caption:          ff.Caption >= event.CapLevelPartialSupport,
		MaxCaptionLength: ff.MaxCaptionLength,
		MaxSize:          min(ff.MaxSize, MaxFileCeiling),
	}
	if ff.MaxDuration != nil {
		out.MaxDurationSec = int(ff.MaxDuration.Seconds())
	}
	return out
}

// networkFileCeiling returns the per-network file size ceiling: 2 GiB for bridges that stream uploads from disk via
// Bot.DownloadMediaToFile (Telegram), and 100 MiB (MaxInMemoryFileCeiling) for bridges that call Bot.DownloadMedia
// into an in-memory []byte (WhatsApp, Signal, Google Messages, Slack).
func networkFileCeiling(network string) int64 {
	if network == "telegram" {
		return MaxFileCeiling
	}
	return MaxInMemoryFileCeiling
}

func (f *Features) capMaxSizes(ceiling int64) {
	for _, fk := range []*FileKindFeatures{
		f.ImageFeatures,
		f.VideoFeatures,
		f.AudioFeatures,
		f.VoiceFeatures,
		f.FileFeatures,
		f.GIFFeatures,
		f.StickerFeatures,
	} {
		if fk != nil && fk.MaxSize > ceiling {
			fk.MaxSize = ceiling
		}
	}
	f.Sticker = mediaCapFromFileKind(f.StickerFeatures)
	f.GIF = mediaCapFromFileKind(f.GIFFeatures)
}

// Keeps reports whether the chat keeps formatting of kind k. It is the keep function richtext.Render takes.
func (f Features) Keeps(k richtext.Kind) bool { return slices.Contains(f.Formatting, k) }

// Features is what a person can do in a chat. It reads the chat's stored com.beeper.room_features state, which
// bridgev2 writes when it makes the room and again whenever the features change (Portal.UpdateCapabilities). Only
// when none is stored does it ask the chat's own login's client, logged in (clientFeatures, GetCapabilities). With
// neither it is NoFeatures. An unknown chat is store.ErrNotFound.
func (a *Actions) Features(ctx context.Context, roomID string) (Features, error) {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil {
		return Features{}, err
	}
	if !ok {
		return Features{}, store.ErrNotFound
	}
	f := NoFeatures
	rf, err := a.storedFeatures(ctx, roomID, room.Network)
	if err != nil {
		return Features{}, err
	}
	if rf != nil {
		f = FeaturesOf(rf)
		f.Source = SourceStored
	} else if h, ok := a.eng.Host(room.Network); ok {
		if rf = a.clientFeatures(ctx, h, roomID); rf != nil {
			f = FeaturesOf(rf)
			f.Source = SourceNetwork
		}
	}
	f.capMaxSizes(networkFileCeiling(room.Network))
	if portal, login := a.portalAndLogin(ctx, roomID); portal != nil && login != nil {
		pl, err := portal.Bridge.Matrix.GetPowerLevels(ctx, id.RoomID(roomID))
		if err != nil || pl == nil {
			pl = &event.PowerLevelsEventContent{}
		}
		myLevel := pl.GetUserLevel(ids.Me)
		caps := GroupCapabilitiesOf(login.Client)
		f.CanSetName = !room.IsDirect && caps.SetName && myLevel >= pl.GetEventLevel(event.StateRoomName)
		f.CanSetTopic = !room.IsDirect && caps.SetTopic && myLevel >= pl.GetEventLevel(event.StateTopic)
		f.CanSetAvatar = !room.IsDirect && caps.SetAvatar && myLevel >= pl.GetEventLevel(event.StateRoomAvatar)
		f.CanInvite = !room.IsDirect && caps.Membership && myLevel >= pl.Invite()
		f.CanKick = !room.IsDirect && caps.Membership && myLevel >= pl.Kick()
		f.CanLeave = !room.IsDirect && caps.Membership
		f.CanSetAdmin = !room.IsDirect && caps.PowerLevels && myLevel >= pl.GetEventLevel(event.StatePowerLevels)
		f.CanDelete = caps.DeleteChat && (room.IsDirect || !groupDeleteNeedsEveryone[room.Network])
		f.DeleteLeavesGroup = !room.IsDirect && f.CanDelete && deleteLeavesGroup[room.Network]
	}
	return f, nil
}

// portalAndLogin returns the bridgev2 Portal and live logged-in UserLogin for roomID, or (nil, nil) if the room is
// not bound to a live logged-in portal/login.
func (a *Actions) portalAndLogin(ctx context.Context, roomID string) (*bridgev2.Portal, *bridgev2.UserLogin) {
	room, ok, err := a.s.GetRoom(ctx, roomID)
	if err != nil || !ok {
		return nil, nil
	}
	h, ok := a.eng.Host(room.Network)
	if !ok || h == nil {
		return nil, nil
	}
	portal, err := h.Bridge.GetPortalByMXID(ctx, id.RoomID(roomID))
	if err != nil || portal == nil {
		return nil, nil
	}
	login := loginOf(ctx, h, room)
	if login == nil || login.Client == nil || !login.Client.IsLoggedIn() {
		return nil, nil
	}
	return portal, login
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

// clientFeatures asks the chat's own login's client (loginFor) what the chat's portal can do, while it is logged in:
// for a chat every login shares, whichever of mine is. Never another account's client: what one account's chats can
// do says nothing about another's (a Slack workspace's settings, say: Review Focus 5). Nil when the bridge has no
// portal for the room or that login isn't logged in.
func (a *Actions) clientFeatures(ctx context.Context, h *host.Host, roomID string) *event.RoomFeatures {
	portal, err := h.Bridge.GetPortalByMXID(ctx, id.RoomID(roomID))
	if err != nil || portal == nil {
		return nil
	}
	pick, ok := a.loginFor(ctx, h, roomID)
	if !ok || !pick.Client.IsLoggedIn() {
		return nil
	}
	return pick.Client.GetCapabilities(ctx, portal)
}
