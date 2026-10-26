// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package networks

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	gmessages "go.mau.fi/mautrix-gmessages/pkg/connector"
	"go.mau.fi/mautrix-gmessages/pkg/libgm/gmproto"
	slack "go.mau.fi/mautrix-slack/pkg/connector"
	"go.mau.fi/mautrix-slack/pkg/slackid"
	telegram "go.mau.fi/mautrix-telegram/pkg/connector"
	telegramids "go.mau.fi/mautrix-telegram/pkg/connector/ids"
	whatsapp "go.mau.fi/mautrix-whatsapp/pkg/connector"
	"go.mau.fi/mautrix-whatsapp/pkg/waid"
	"gopkg.in/yaml.v3"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/database"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/engine"
	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/richtext"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func fmtConfig(t *testing.T, data any) string {
	t.Helper()
	out, err := yaml.Marshal(data)
	require.NoError(t, err)
	return string(out)
}

func TestRegistryNamesAreSafeGhostPrefixes(t *testing.T) {
	for _, n := range All() {
		require.Regexp(t, `^[a-z]+$`, n.Name, "network names become ghost-ID prefixes and must not contain '_'")
		require.NotEmpty(t, n.DisplayName, n.Name)
		require.NotEmpty(t, n.Flows, n.Name)
		require.NotNil(t, n.Spec, n.Name)
	}
	for _, name := range []string{"whatsapp", "telegram", "gmessages", "slack"} {
		_, ok := Get(name)
		require.True(t, ok, name)
	}
	_, ok := Get("nonesuch")
	require.False(t, ok)
}

func TestRegistryFlowsMatchWhatEachBridgeOffers(t *testing.T) {
	want := map[string][]string{
		"whatsapp":  {"qr"},
		"telegram":  {"qr", "phone"},
		"gmessages": {"google"}, // upstream disabled QR login; its GetLoginFlows lists only google
		"slack":     {"email", "token", "app"},
	}
	for name, flows := range want {
		n, ok := Get(name)
		require.True(t, ok, name)
		require.Equal(t, flows, n.Flows, name)
	}
}

// A flow the CLI offers has to be one the bridge really has, or login fails with "invalid flow" at run time.
func TestEveryOfferedFlowExistsInTheBridge(t *testing.T) {
	t.Setenv("COURIER_TELEGRAM_API_ID", "424242")
	t.Setenv("COURIER_TELEGRAM_API_HASH", "0123456789abcdef0123456789abcdef")
	for _, n := range All() {
		spec, err := n.Spec()
		require.NoError(t, err, n.Name)
		nc, err := spec.Connector()
		require.NoError(t, err, n.Name)
		have := map[string]bool{}
		for _, f := range nc.GetLoginFlows() {
			have[f.ID] = true
		}
		for _, f := range n.Flows {
			require.True(t, have[f], "%s offers flow %q, which its bridge does not have", n.Name, f)
		}
	}
}

func TestSpecsUseTheirRegistryName(t *testing.T) {
	t.Setenv("COURIER_TELEGRAM_API_ID", "424242")
	t.Setenv("COURIER_TELEGRAM_API_HASH", "0123456789abcdef0123456789abcdef")
	for _, n := range All() {
		spec, err := n.Spec()
		require.NoError(t, err, n.Name)
		require.Equal(t, n.Name, spec.Name)
	}
}

func TestTelegramWithoutCredentialsSaysWhereToGetThem(t *testing.T) {
	t.Setenv("COURIER_TELEGRAM_API_ID", "")
	t.Setenv("COURIER_TELEGRAM_API_HASH", "")
	tg, _ := Get("telegram")
	_, err := tg.Spec()
	require.Error(t, err)
	require.True(t, strings.Contains(err.Error(), "my.telegram.org"), err.Error())
	require.Contains(t, err.Error(), "COURIER_TELEGRAM_API_ID")
	require.Contains(t, err.Error(), "COURIER_TELEGRAM_API_HASH")
}

func TestTelegramCredentialsReachTheConnectorConfig(t *testing.T) {
	t.Setenv("COURIER_TELEGRAM_API_ID", "424242")
	t.Setenv("COURIER_TELEGRAM_API_HASH", "0123456789abcdef0123456789abcdef")
	tg, _ := Get("telegram")
	spec, err := tg.Spec()
	require.NoError(t, err)
	nc, err := spec.Connector()
	require.NoError(t, err)
	_, data, _ := nc.GetConfig()
	require.NoError(t, spec.Configure(data))
	cfg := fmtConfig(t, data)
	require.Contains(t, cfg, "424242")
	require.Contains(t, cfg, "0123456789abcdef0123456789abcdef")
}

// YAML reads a number with a leading zero as octal, so the id has to reach the config as the decimal number the
// user typed: 0042 is 42, never 34.
func TestTelegramAPIIDWithLeadingZerosIsDecimal(t *testing.T) {
	for in, want := range map[string]int{"0042": 42, "000000424242": 424242, "010": 10, "424242": 424242} {
		t.Run(in, func(t *testing.T) {
			t.Setenv("COURIER_TELEGRAM_API_ID", in)
			t.Setenv("COURIER_TELEGRAM_API_HASH", "0123456789abcdef0123456789abcdef")
			tg, _ := Get("telegram")
			spec, err := tg.Spec()
			require.NoError(t, err)
			nc, err := spec.Connector()
			require.NoError(t, err)
			_, data, _ := nc.GetConfig()
			require.NoError(t, spec.Configure(data))
			require.Equal(t, want, nc.(*telegram.TelegramConnector).Config.APIID)
		})
	}
}

// Credentials are secrets: a malformed one is rejected, and the message must not repeat what was typed.
func TestTelegramRejectsMalformedCredentialsWithoutEchoingThem(t *testing.T) {
	const goodHash = "0123456789abcdef0123456789abcdef"
	for name, c := range map[string]struct{ id, hash string }{
		"id not a number":    {"not-a-number-77", goodHash},
		"id zero":            {"0", goodHash},
		"id negative":        {"-424242", goodHash},
		"id overflows":       {"99999999999", goodHash},
		"id over 31 bits":    {"2147483648", goodHash},
		"hash too short":     {"424242", "abc123short"},
		"hash not hex":       {"424242", "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"},
		"hash has a newline": {"424242", "0123456789abcdef0123456789abcde\n"},
	} {
		t.Run(name, func(t *testing.T) {
			t.Setenv("COURIER_TELEGRAM_API_ID", c.id)
			t.Setenv("COURIER_TELEGRAM_API_HASH", c.hash)
			tg, _ := Get("telegram")
			_, err := tg.Spec()
			require.Error(t, err)
			require.Contains(t, err.Error(), "my.telegram.org")
			for _, secret := range []string{strings.TrimSpace(c.id), strings.TrimSpace(c.hash)} {
				require.NotContains(t, err.Error(), secret, "the error must not repeat a credential")
			}
		})
	}
}

// A network whose spec can't be built (Telegram without its app credentials) still reaches the engine, under its own
// name, so the engine keeps why it isn't running for the app (Ruling C30).
func TestASpecThatCantBeBuiltIsNotStartedWithItsReason(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	nets := []Network{{Name: "fakebad", Spec: func() (engine.Spec, error) { return engine.Spec{}, errors.New("needs its own app credentials") }}}
	specs := Specs(nets)
	require.Len(t, specs, 1)
	require.Equal(t, "fakebad", specs[0].Name)

	eng, errs := Start(ctx, dir, s, &media.Store{Dir: filepath.Join(dir, "media")}, nets, zerolog.Nop())
	defer eng.Stop()
	require.ErrorContains(t, errs["fakebad"], "needs its own app credentials")
	require.Equal(t, engine.Status{NotStarted: "needs its own app credentials"}, eng.Status("fakebad"))
}

// WhatsApp tags a chat archived on the phone with its archive_tag, which the example config leaves empty. Courier
// sets it to m.lowpriority, the tag the store reads as archived, so such a chat arrives archived.
func TestWhatsAppArchivedChatsArriveArchived(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	wa, ok := Get("whatsapp")
	require.True(t, ok)
	spec, err := wa.Spec()
	require.NoError(t, err)
	require.NotNil(t, spec.Configure, "WhatsApp needs its archive tag set")
	nc, err := spec.Connector()
	require.NoError(t, err)
	h, err := host.Start(ctx, dir, spec.Name, s, &media.Store{Dir: filepath.Join(dir, "media")}, nc, zerolog.Nop(),
		host.WithConfigure(spec.Configure))
	require.NoError(t, err)
	defer h.Stop()

	cfg := nc.(*whatsapp.WhatsAppConnector).Config
	require.Equal(t, event.RoomTagLowPriority, cfg.ArchiveTag)
	require.Equal(t, event.RoomTagFavourite, cfg.PinnedTag, "pins keep the example's tag")
	require.Contains(t, h.Bridge.Config.OnlyBridgeTags, cfg.ArchiveTag, "the bridge takes the tag in")
	require.True(t, cfg.ExtEvPolls, "polls arrive as polls (TestPollsArriveAsPolls), after the example config is read")
	require.Equal(t, "{{or .BusinessName .PushName .Phone .RedactedPhone \"Unknown user\"}} (WA)", cfg.DisplaynameTemplate,
		"every other setting keeps the example's value")
}

// The "sent" rows of the plan's per-network table (what Courier sends each network), and the bridgev2 interfaces
// each pinned bridge's client implements, which is what they rest on. A bridge bump that adds or drops one of
// these handlers fails here, so the table (and what Courier tells people reaches each network) is looked at again.
//
// The two differ in one place: WhatsApp's client takes unread marks, but its bridge inverts them, so Courier never
// sends one (actions.SyncsOf; TestWhatsAppBridgeVersionIsTheOneCheckedForUnreadMarks).
func TestNetworkSyncTableMatchesTheBridges(t *testing.T) {
	rows := map[string]platformClient{
		"whatsapp":  {client: (*whatsapp.WhatsAppClient)(nil), sent: []string{"pin", "mute"}, implements: []string{"pin", "mute", "unread"}},
		"telegram":  {client: (*telegram.TelegramClient)(nil), sent: []string{"pin", "mute"}, implements: []string{"pin", "mute"}},
		"gmessages": {client: (*gmessages.GMClient)(nil), sent: []string{}, implements: []string{}},
		"slack":     {client: (*slack.SlackClient)(nil), sent: []string{}, implements: []string{}},
	}
	for name, c := range platformClients() {
		rows[name] = c
	}
	var registered []string
	for _, n := range All() {
		registered = append(registered, n.Name)
	}
	require.ElementsMatch(t, registered, keys(rows), "every registered network has a row")
	for name, r := range rows {
		require.Equal(t, r.sent, actions.SyncsOf(r.client), "what Courier sends %s", name)
		_, pin := r.client.(bridgev2.TagHandlingNetworkAPI)
		_, mute := r.client.(bridgev2.MuteHandlingNetworkAPI)
		_, unread := r.client.(bridgev2.MarkedUnreadHandlingNetworkAPI)
		_, accept := r.client.(bridgev2.MessageRequestAcceptingNetworkAPI)
		require.Equal(t, r.implements, pick(pin, "pin", mute, "mute", unread, "unread", accept, "accept_request"),
			"what %s's bridge implements", name)
	}
}

// WhatsApp's bridge inverts unread marks at the version Courier pins: HandleMarkedUnread passes Content.Unread as
// whatsmeow's BuildMarkChatAsRead(target, read, ...) (pkg/connector/handlematrix.go:667 at v0.2609.0; still so at
// :696 in v0.2610.0). So Courier sends it none (actions.SyncsOf). This fails when the pin moves, to make whoever
// bumps it read that handler again before letting unread marks reach WhatsApp.
func TestWhatsAppBridgeVersionIsTheOneCheckedForUnreadMarks(t *testing.T) {
	// The engine's go.mod, a data dependency of this test, is what pins the bridge.
	raw, err := os.ReadFile("../../go.mod")
	require.NoError(t, err)
	m := regexp.MustCompile(`(?m)^\s*go\.mau\.fi/mautrix-whatsapp\s+(\S+)`).FindStringSubmatch(string(raw))
	require.NotNil(t, m, "go.mod no longer requires mautrix-whatsapp")
	require.Equal(t, "v0.2609.0", m[1],
		"mautrix-whatsapp moved off v0.2609.0. Re-check HandleMarkedUnread in its pkg/connector/handlematrix.go: if it "+
			"no longer passes Content.Unread as BuildMarkChatAsRead's \"read\" argument, unread marks can go to WhatsApp "+
			"again (actions.SyncsOf and the plan's sync table). Then update this version.")
}

// Google Messages tells of a person it has no phone number for with a plain error, "phone number of ghost %s not
// known" (pkg/connector/startchat.go:85-87 at v0.2609.0), which actions.startFailure reads by its text to answer
// Reply Privately "can't reach them" instead of "the network refused". This fails when the pin moves, to make whoever
// bumps it check that text (and its ErrResolveIdentifierTryNext and M_INVALID_PARAM cases, :82-84, :101-104) again.
func TestGoogleMessagesBridgeVersionIsTheOneCheckedForUnreachablePeople(t *testing.T) {
	raw, err := os.ReadFile("../../go.mod")
	require.NoError(t, err)
	m := regexp.MustCompile(`(?m)^\s*go\.mau\.fi/mautrix-gmessages\s+(\S+)`).FindStringSubmatch(string(raw))
	require.NotNil(t, m, "go.mod no longer requires mautrix-gmessages")
	require.Equal(t, "v0.2609.0", m[1],
		"mautrix-gmessages moved off v0.2609.0. Re-check ResolveIdentifier in its pkg/connector/startchat.go: if the "+
			"unknown-phone error's text changed, actions.startFailure no longer recognises it. Then update this version.")
}

type platformClient struct {
	client     bridgev2.NetworkAPI
	sent       []string // what Courier sends the network (actions.SyncsOf)
	implements []string // the chat-change interfaces the bridge's client implements
}

func keys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

// pick lists the names whose flag is set, in order: pick(true, "a", false, "b") is ["a"].
func pick(pairs ...any) []string {
	out := []string{}
	for i := 0; i < len(pairs); i += 2 {
		if pairs[i].(bool) {
			out = append(out, pairs[i+1].(string))
		}
	}
	return out
}

// actionRow is one chat type of one network in the plan's "What each action reaches" table: the bridge's own
// client, a portal built with the bridge's own metadata type, and what Courier reads from the room features the
// client gives that portal.
type actionRow struct {
	client bridgev2.NetworkAPI
	portal *bridgev2.Portal
	want   actions.Features
}

// handlerRow is which message actions a network's client takes at all (the bridgev2 interfaces it implements):
// "edit", "remove" (redactions), "poll" (polls and votes) and "timer" (disappearing timers).
type handlerRow struct {
	client  bridgev2.NetworkAPI
	handles []string
}

func portalOf(roomType database.RoomType, portalID networkid.PortalID, meta any) *bridgev2.Portal {
	return &bridgev2.Portal{Portal: &database.Portal{
		PortalKey: networkid.PortalKey{ID: portalID, Receiver: "me"}, RoomType: roomType, Metadata: meta,
	}}
}

// slackChannel is a Slack channel in a workspace whose team portal says meta (edit and delete settings).
func slackChannel(meta *slackid.PortalMetadata) *bridgev2.Portal {
	p := portalOf(database.RoomTypeDefault, "T1-C1", &slackid.PortalMetadata{})
	p.Parent = portalOf(database.RoomTypeSpace, "T1", meta)
	return p
}

func ptrTo[T any](v T) *T { return &v }

// The formatting each network keeps: the plan's formatting table.
var (
	noSpoiler = []richtext.Kind{
		richtext.Bold, richtext.Italic, richtext.Strike, richtext.Code, richtext.Pre,
		richtext.Quote, richtext.Bullets, richtext.Numbered, richtext.Link, richtext.Mention,
	}
	everyKind = richtext.Kinds
	noKind    = []richtext.Kind{}
)

const day = 24 * time.Hour

// messageActionRows are the rows of TestMessageActionTableMatchesTheBridges: each chat type the plan's tables tell
// apart, as the pinned bridge's own client and a portal built with its own metadata type, and each network's client.
func messageActionRows() (map[string]actionRow, map[string]handlerRow) {
	wa := actions.Features{
		Reply: true, Edit: true, EditMaxAge: 15 * time.Minute, Unsend: true, UnsendMaxAge: 2 * day,
		Poll: &actions.PollFeatures{MaxOptions: 12, OptionMaxLength: 100},
		Disappearing: &actions.DisappearingFeatures{
			Type:   "after_send",
			Timers: []time.Duration{day, 7 * day, 90 * day},
		},
		Formatting: noSpoiler, MaxTextLength: 65536,
	}
	waCAG := wa
	waCAG.Reply, waCAG.Thread, waCAG.ReplyIsThread = false, true, true

	const month, year = 31 * day, 365 * day
	tg := actions.Features{
		Reply: true, Edit: true, Unsend: true, HideDeletedPlaceholder: true,
		Disappearing: &actions.DisappearingFeatures{Type: "after_send", Timers: []time.Duration{
			day, 2 * day, 3 * day, 4 * day, 5 * day, 6 * day, 7 * day, 14 * day, 21 * day,
			month, 2 * month, 3 * month, 4 * month, 5 * month, 6 * month, year,
		}},
		Formatting: everyKind, MaxTextLength: 4096,
	}
	gmRCS := actions.Features{Reply: true, DeleteReachesPhone: true, Formatting: noKind}
	gmSMS := actions.Features{DeleteReachesPhone: true, Formatting: noKind}
	sl := actions.Features{
		Thread: true, ReplyIsThread: true, Edit: true, Unsend: true,
		Formatting: noSpoiler, MentionRoom: true, MaxTextLength: 40000,
	}
	slEditLimit := sl
	slEditLimit.EditMaxAge = 10 * time.Minute
	slNoEdit := sl
	slNoEdit.Edit = false
	slNoDelete := sl
	slNoDelete.Unsend = false

	tgClient := &telegram.TelegramClient{}
	// An empty AllowedReactions list ("no reactions") keeps GetCapabilities from asking Telegram for its list.
	tgMeta := func() any { return &telegram.PortalMetadata{AllowedReactions: []string{}} }
	rows := map[string]actionRow{
		"whatsapp dm":    {(*whatsapp.WhatsAppClient)(nil), portalOf(database.RoomTypeDM, "1@s.whatsapp.net", &waid.PortalMetadata{}), wa},
		"whatsapp group": {(*whatsapp.WhatsAppClient)(nil), portalOf(database.RoomTypeDefault, "1@g.us", &waid.PortalMetadata{}), wa},
		"whatsapp community announcement group": {
			(*whatsapp.WhatsAppClient)(nil),
			portalOf(database.RoomTypeDefault, "2@g.us", &waid.PortalMetadata{CommunityAnnouncementGroup: true}), waCAG,
		},
		"telegram dm":    {tgClient, portalOf(database.RoomTypeDM, telegramids.MakePortalID(telegramids.PeerTypeUser, 1), tgMeta()), tg},
		"telegram group": {tgClient, portalOf(database.RoomTypeDefault, telegramids.MakePortalID(telegramids.PeerTypeChat, 2), tgMeta()), tg},
		"gmessages rcs": {
			(*gmessages.GMClient)(nil),
			portalOf(database.RoomTypeDM, "1", &gmessages.PortalMetadata{Type: gmproto.ConversationType_RCS}), gmRCS,
		},
		"gmessages sms": {
			(*gmessages.GMClient)(nil),
			portalOf(database.RoomTypeDM, "2", &gmessages.PortalMetadata{Type: gmproto.ConversationType_SMS}), gmSMS,
		},
		"slack channel":                   {(*slack.SlackClient)(nil), slackChannel(&slackid.PortalMetadata{}), sl},
		"slack dm":                        {(*slack.SlackClient)(nil), portalOf(database.RoomTypeDM, "T1-D1", &slackid.PortalMetadata{}), sl},
		"slack workspace with edit limit": {(*slack.SlackClient)(nil), slackChannel(&slackid.PortalMetadata{EditMaxAge: ptrTo(10)}), slEditLimit},
		"slack workspace without edits":   {(*slack.SlackClient)(nil), slackChannel(&slackid.PortalMetadata{EditMaxAge: ptrTo(0)}), slNoEdit},
		"slack workspace without deletes": {(*slack.SlackClient)(nil), slackChannel(&slackid.PortalMetadata{AllowDelete: ptrTo(false)}), slNoDelete},
	}
	handlers := map[string]handlerRow{
		"whatsapp":  {(*whatsapp.WhatsAppClient)(nil), []string{"edit", "remove", "poll", "timer"}},
		"telegram":  {tgClient, []string{"edit", "remove", "timer"}},
		"gmessages": {(*gmessages.GMClient)(nil), []string{"remove"}},
		"slack":     {(*slack.SlackClient)(nil), []string{"edit", "remove"}},
	}
	platformRows, platformHandlers := platformActionRows()
	for name, r := range platformRows {
		rows[name] = r
	}
	for name, h := range platformHandlers {
		handlers[name] = h
	}
	return rows, handlers
}

// The plan's "What each action reaches" table, read from the pinned bridges themselves: each client's real
// GetCapabilities, through actions.FeaturesOf, for every chat type the table tells apart. A bridge bump that
// changes any cell fails here, so the table, and what Courier offers and tells people, is looked at again.
//
// It pins the surprises the table rests on: Google Messages has no unsend, only a delete that reaches the phone
// (1); Slack and WhatsApp community announcement groups have no plain replies, so a reply becomes a thread reply
// (2); Google Messages SMS chats have no replies (7). Telegram's 16 timers and Signal's after-read timer with no
// list (Courier offers actions.SignalTimers) are here too, and no network ends polls or hides their results.
//
// Each row also has to agree with the handlers its client implements: an action the features allow is one the
// bridge can carry out.
func TestMessageActionTableMatchesTheBridges(t *testing.T) {
	rows, handlers := messageActionRows()
	var registered []string
	for _, n := range All() {
		registered = append(registered, n.Name)
	}
	require.ElementsMatch(t, registered, keys(handlers), "every registered network has a row")

	ctx := context.Background()
	for name, r := range rows {
		rf := r.client.GetCapabilities(ctx, r.portal)
		require.NotNil(t, rf, name)
		gotFeatures := actions.FeaturesOf(rf)
		gotFeatures.ImageFeatures = nil
		gotFeatures.VideoFeatures = nil
		gotFeatures.AudioFeatures = nil
		gotFeatures.VoiceFeatures = nil
		gotFeatures.FileFeatures = nil
		gotFeatures.GIFFeatures = nil
		gotFeatures.StickerFeatures = nil
		gotFeatures.Sticker = actions.MediaCapFeature{}
		gotFeatures.GIF = actions.MediaCapFeature{}
		gotFeatures.LocationSupported = false
		gotFeatures.LinkPreviewsSupported = false
		require.Equal(t, r.want, gotFeatures, "what Courier offers in a %s", name)
		require.False(t, rf.PollEnd.Partial(), "%s: no network ends polls", name)
		require.False(t, rf.PollHiddenVotes.Partial(), "%s: no network hides poll results", name)

		network := strings.Fields(name)[0]
		h, ok := handlers[network]
		require.True(t, ok, name)
		got := handled(r.client)
		require.Equal(t, got, handled(h.client), "%s: the row's client is %s's", name, network)
		if r.want.Edit {
			require.Contains(t, got, "edit", "%s: edits are offered, so the bridge must take them", name)
		}
		if r.want.Unsend || r.want.DeleteReachesPhone {
			require.Contains(t, got, "remove", "%s: deletes reach the network, so the bridge must take them", name)
		}
		if r.want.Poll != nil {
			require.Contains(t, got, "poll", "%s: polls are offered, so the bridge must take them", name)
		}
		if r.want.Disappearing != nil {
			require.Contains(t, got, "timer", "%s: a timer is offered, so the bridge must take it", name)
		}
	}
	for name, h := range handlers {
		require.Equal(t, h.handles, handled(h.client), "what %s's bridge implements", name)
	}
}

// handled lists the message-action interfaces a client implements, out of "edit", "remove", "poll" and "timer".
func handled(c bridgev2.NetworkAPI) []string {
	_, edit := c.(bridgev2.EditHandlingNetworkAPI)
	_, remove := c.(bridgev2.RedactionHandlingNetworkAPI)
	_, poll := c.(bridgev2.PollHandlingNetworkAPI)
	_, timer := c.(bridgev2.DisappearTimerChangingNetworkAPI)
	return pick(edit, "edit", remove, "remove", poll, "poll", timer, "timer")
}

// WhatsApp and Signal bridge a poll as a poll (org.matrix.msc3381.poll.start, with votes) only with extev_polls
// on; their example configs leave it off, and a poll then arrives as text asking people to vote on the phone.
// Courier turns it on for both. Telegram's bridge has no setting: its polls stay text.
func TestPollsArriveAsPolls(t *testing.T) {
	checks := map[string]func(data any) bool{
		"whatsapp": func(data any) bool { return data.(*whatsapp.Config).ExtEvPolls },
	}
	for name, check := range platformPollChecks() {
		checks[name] = check
	}
	for name, check := range checks {
		n, ok := Get(name)
		require.True(t, ok, name)
		spec, err := n.Spec()
		require.NoError(t, err, name)
		require.NotNil(t, spec.Configure, "%s needs extev_polls set", name)
		nc, err := spec.Connector()
		require.NoError(t, err, name)
		_, data, _ := nc.GetConfig()
		require.NoError(t, spec.Configure(data), name)
		require.True(t, check(data), "%s bridges polls as polls", name)
	}
}

// The protocol's networks.json lists every network the engine runs, with the name a person reads; the app's
// NetworkNames checks against the same file (ChatFeaturesTests), so the engine's names and the app's can't drift,
// for all five networks, not only the ones the accounts example shows.
func TestRegistryMatchesTheProtocolsNetworkList(t *testing.T) {
	const rel = "apps/desktop/courier/protocol/networks.json"
	var tried []string
	if srcdir := os.Getenv("TEST_SRCDIR"); srcdir != "" {
		ws := os.Getenv("TEST_WORKSPACE")
		if ws == "" {
			ws = "_main"
		}
		tried = append(tried, filepath.Join(srcdir, ws, rel), filepath.Join(srcdir, rel))
	}
	tried = append(tried, filepath.Join("..", "..", "..", "protocol", "networks.json"))
	var raw []byte
	for _, path := range tried {
		if b, err := os.ReadFile(path); err == nil {
			raw = b
			break
		}
	}
	require.NotNil(t, raw, "networks.json not found; tried %v", tried)
	var list struct {
		Networks []struct {
			Name        string `json:"name"`
			DisplayName string `json:"display_name"`
			MacOSOnly   bool   `json:"macos_only"`
		} `json:"networks"`
	}
	require.NoError(t, json.Unmarshal(raw, &list))

	want := map[string]string{}
	for _, n := range list.Networks {
		if n.MacOSOnly && runtime.GOOS != "darwin" {
			continue
		}
		want[n.Name] = n.DisplayName
	}
	got := map[string]string{}
	for _, n := range All() {
		got[n.Name] = n.DisplayName
	}
	require.Equal(t, want, got)
}

// receiptNetwork is one network's column of the plan's receipts, typing and accounts table, as far as the pinned
// bridge shows it without a network: its connector (the bridge-wide capabilities) and its client (the interfaces it
// implements).
type receiptNetwork struct {
	connector bridgev2.NetworkConnector
	client    bridgev2.NetworkAPI
	// sends lists what of mine reaches the network, out of "read_receipts" (ReadReceiptHandlingNetworkAPI) and
	// "typing" (TypingHandlingNetworkAPI): the "My read receipts sent" and "My typing sent (out)" rows.
	sends []string
	// replyPrivately lists how a one-to-one chat with a group member is made, out of "resolve_identifier"
	// (IdentifierResolvingNetworkAPI) and "create_chat_with_ghost" (GhostDMCreatingNetworkAPI): the client
	// implements these; the table's "Reply Privately" row names the one Courier uses.
	replyPrivately []string
	// implicitReads is surprise 7: replying marks the chat read on the network whatever Courier does
	// (NetworkGeneralCapabilities.ImplicitReadReceipts).
	implicitReads bool
}

// readReceiptsByRow is, for each portal of messageActionRows, whether the client's room features for it say read
// receipts go (RoomFeatures.ReadReceipts): every network's chats but Slack's, whose receipts are my own reads from
// another Slack client (surprise 1), so Courier shows no "Seen" there.
var readReceiptsByRow = map[string]bool{
	"whatsapp dm": true, "whatsapp group": true, "whatsapp community announcement group": true,
	"telegram dm": true, "telegram group": true,
	"gmessages rcs": true, "gmessages sms": true,
	"slack channel": false, "slack dm": false, "slack workspace with edit limit": false,
	"slack workspace without edits": false, "slack workspace without deletes": false,
	"signal dm": true, "signal group": true, "signal note to self": true,
}

// pinnedBridges are the module versions the plan's receipts, typing and accounts table was read at (go.mod).
var pinnedBridges = map[string]string{
	"maunium.net/go/mautrix":      "v0.31.0",
	"go.mau.fi/mautrix-whatsapp":  "v0.2609.0",
	"go.mau.fi/mautrix-signal":    "v0.2609.0",
	"go.mau.fi/mautrix-telegram":  "v0.2609.0",
	"go.mau.fi/mautrix-gmessages": "v0.2609.0",
	"go.mau.fi/mautrix-slack":     "v0.2609.1",
}

// The plan's "What each action reaches" table for receipts, typing and second accounts (Global Constraints), read
// from the pinned bridges as far as the code shows it without a network (Ruling P4). Pinned here, so a bump that
// changes one fails:
//   - "My read receipts sent" and "My typing sent (out)": the client implements ReadReceiptHandlingNetworkAPI and
//     TypingHandlingNetworkAPI (every network: yes).
//   - "Reply Privately": the client implements GhostDMCreatingNetworkAPI or IdentifierResolvingNetworkAPI.
//   - "Seen" shown, as far as the room features say it: RoomFeatures.ReadReceipts on every portal of 4.3's table
//     (false on every Slack chat: surprise 1).
//   - Surprise 7: ImplicitReadReceipts on WhatsApp and Signal only.
//   - "A second account", where an ID function is exported: Google Messages keys every chat to its login (each
//     chat is per account); a Slack login's ID is its workspace and user, "T-U" (slackid/id.go:66–68), so the same
//     user of the same workspace signed in again is the same account and another workspace is another (the table
//     cites slackid/id.go:116–120, where a chat's key takes that login as its receiver). WhatsApp's own rule
//     (one-to-one chats per account, groups shared: surprise 8) is unexported (makeWAPortalKey); the half Courier
//     controls, split_portals off, is pinned by the host package's tests.
//
// The other cells are cited facts only, checked by reading the pinned source at the file:line the table gives, and
// held here by the version pins alone: which receipts come in and show as "Seen" (one-to-one or groups, Telegram's
// and Google Messages' group rules, Slack's own-sender receipts), "Delivered" (bridgev2 drops it in groups:
// surprise 2), the incoming typing timeouts, which networks never send a typing stop (surprise 4), and whether a
// second account is allowed at all (each bridge's login.go). A bump of any pinned module fails here until whoever
// moves it reads those cells again at the new version.
//
// Two rules of Courier's own sit beside the table and are tested where they are built: a receipt from any of my
// logins counts as my own read, never as "Seen" (localmatrix's MarkRead, through the connector's isMe), so a
// one-to-one chat between two of my own accounts never shows "Seen"; and only one-to-one chats show "Delivered".
func TestReceiptsTypingAndAccountsTableMatchTheBridges(t *testing.T) {
	ctx := context.Background()
	tgClient := &telegram.TelegramClient{}
	columns := map[string]receiptNetwork{
		"whatsapp": {
			connector: &whatsapp.WhatsAppConnector{}, client: (*whatsapp.WhatsAppClient)(nil),
			sends: []string{"read_receipts", "typing"}, replyPrivately: []string{"resolve_identifier", "create_chat_with_ghost"},
			implicitReads: true,
		},
		"telegram": {
			connector: &telegram.TelegramConnector{}, client: tgClient,
			sends: []string{"read_receipts", "typing"}, replyPrivately: []string{"resolve_identifier"},
		},
		"gmessages": {
			connector: &gmessages.GMConnector{}, client: (*gmessages.GMClient)(nil),
			sends: []string{"read_receipts", "typing"}, replyPrivately: []string{"resolve_identifier"},
		},
		"slack": {
			connector: &slack.SlackConnector{}, client: (*slack.SlackClient)(nil),
			sends: []string{"read_receipts", "typing"}, replyPrivately: []string{"resolve_identifier", "create_chat_with_ghost"},
		},
	}
	for name, c := range platformReceiptColumns() {
		columns[name] = c
	}
	var registered []string
	for _, n := range All() {
		registered = append(registered, n.Name)
	}
	require.ElementsMatch(t, registered, keys(columns), "every registered network has a column")

	for name, c := range columns {
		_, reads := c.client.(bridgev2.ReadReceiptHandlingNetworkAPI)
		_, typing := c.client.(bridgev2.TypingHandlingNetworkAPI)
		require.Equal(t, c.sends, pick(reads, "read_receipts", typing, "typing"), "what of mine reaches %s", name)
		_, resolve := c.client.(bridgev2.IdentifierResolvingNetworkAPI)
		_, ghostDM := c.client.(bridgev2.GhostDMCreatingNetworkAPI)
		require.Equal(t, c.replyPrivately, pick(resolve, "resolve_identifier", ghostDM, "create_chat_with_ghost"),
			"how %s makes a one-to-one chat", name)
		require.Equal(t, c.implicitReads, c.connector.GetCapabilities().ImplicitReadReceipts,
			"whether replying on %s marks the chat read (surprise 7)", name)
	}

	rows, _ := messageActionRows()
	var cells []string
	for name := range readReceiptsByRow {
		if slices.Contains(registered, strings.Fields(name)[0]) {
			cells = append(cells, name)
		}
	}
	require.ElementsMatch(t, keys(rows), cells, "every chat type of 4.3's table has a cell")
	for name, r := range rows {
		rf := r.client.GetCapabilities(ctx, r.portal)
		require.NotNil(t, rf, name)
		require.Equal(t, readReceiptsByRow[name], rf.ReadReceipts, "whether a %s takes read receipts", name)
	}

	// Google Messages: every chat is its account's own (id.go:79).
	gm := &gmessages.GMClient{
		UserLogin: &bridgev2.UserLogin{UserLogin: &database.UserLogin{ID: "account-a"}},
		Meta:      &gmessages.UserLoginMetadata{IDPrefix: "1"},
	}
	require.Equal(t, networkid.UserLoginID("account-a"), gm.MakePortalKey("conversation").Receiver)
	// Slack: a login's ID is its workspace and user (slackid/id.go:66–68): one account per workspace and user.
	require.Equal(t, networkid.UserLoginID("T1-U1"), slackid.MakeUserLoginID("T1", "U1"))
	require.Equal(t, slackid.MakeUserLoginID("T1", "U1"), slackid.MakeUserLoginID("T1", "U1"), "signed in again, the same account")
	require.NotEqual(t, slackid.MakeUserLoginID("T1", "U1"), slackid.MakeUserLoginID("T2", "U1"), "another workspace, another account")
	require.Equal(t, networkid.PortalKey{ID: slackid.MakePortalID("T1", "C1"), Receiver: "T1-U1"},
		slackid.MakePortalKey("T1", "C1", "T1-U1", true), "a chat of that account is keyed to it (slackid/id.go:116–120)")

	raw, err := os.ReadFile("../../go.mod")
	require.NoError(t, err)
	for module, version := range pinnedBridges {
		m := regexp.MustCompile(`(?m)^\s*` + regexp.QuoteMeta(module) + `\s+(\S+)`).FindStringSubmatch(string(raw))
		require.NotNil(t, m, "go.mod no longer requires %s", module)
		require.Equal(t, version, m[1],
			"%s moved off %s. Read the cited cells of the plan's receipts, typing and accounts table again at the new "+
				"version (the file:line each gives), fix what Courier shows and sends where one changed, then update "+
				"pinnedBridges.", module, version)
	}
}

func TestGroupAndChatManagementTableMatchesTheBridges(t *testing.T) {
	want := map[string]actions.GroupCapabilities{
		"whatsapp": {
			SetName: true, SetTopic: true, SetAvatar: true,
			Membership: true, PowerLevels: false, DeleteChat: true,
		},
		"signal": {
			SetName: true, SetTopic: true, SetAvatar: true,
			Membership: true, PowerLevels: true, DeleteChat: true,
		},
		"telegram": {
			SetName: true, SetTopic: false, SetAvatar: true,
			// TelegramClient implements DeleteChatHandlingNetworkAPI (1:1 chats), while actions/features.go
			// groupDeleteNeedsEveryone disables CanDelete on groups (handlematrix.go:1176 requires DeleteForEveryone).
			Membership: true, PowerLevels: false, DeleteChat: true,
		},
		"gmessages": {
			SetName: false, SetTopic: false, SetAvatar: false,
			Membership: false, PowerLevels: false, DeleteChat: true,
		},
		"slack": {
			SetName: true, SetTopic: true, SetAvatar: false,
			Membership: true, PowerLevels: false, DeleteChat: false,
		},
	}

	clients := map[string]bridgev2.NetworkAPI{
		"whatsapp":  (*whatsapp.WhatsAppClient)(nil),
		"telegram":  (*telegram.TelegramClient)(nil),
		"gmessages": (*gmessages.GMClient)(nil),
		"slack":     (*slack.SlackClient)(nil),
	}
	for name, pc := range platformClients() {
		clients[name] = pc.client
	}

	var registered []string
	for _, n := range All() {
		registered = append(registered, n.Name)
	}
	require.ElementsMatch(t, registered, keys(clients), "every registered network has a client")

	for name, api := range clients {
		expected, ok := want[name]
		require.True(t, ok, "missing expected capabilities for %s", name)
		require.Equal(t, expected, actions.GroupCapabilitiesOf(api), "group and chat management capabilities for %s", name)
	}
}

func TestMediaCapabilitiesTableMatchesTheBridges(t *testing.T) {
	ctx := context.Background()
	rows, _ := messageActionRows()

	for name, r := range rows {
		rf := r.client.GetCapabilities(ctx, r.portal)
		require.NotNil(t, rf, name)
		f := actions.FeaturesOf(rf)
		network := strings.Fields(name)[0]

		switch network {
		case "whatsapp":
			const waMax = int64(2000 * 1024 * 1024)
			require.NotNil(t, f.ImageFeatures, name)
			require.Equal(t, waMax, f.ImageFeatures.MaxSize, name)
			require.True(t, f.ImageFeatures.Caption, name)
			require.Equal(t, 65536, f.ImageFeatures.MaxCaptionLength, name)
			require.NotNil(t, f.VideoFeatures, name)
			require.Equal(t, waMax, f.VideoFeatures.MaxSize, name)
			require.NotNil(t, f.AudioFeatures, name)
			require.Equal(t, waMax, f.AudioFeatures.MaxSize, name)
			require.False(t, f.AudioFeatures.Caption, name)
			require.NotNil(t, f.VoiceFeatures, name)
			require.Equal(t, []string{"audio/ogg; codecs=opus"}, f.VoiceFeatures.MimeTypes, name)
			require.False(t, f.VoiceFeatures.Caption, name)
			require.Equal(t, waMax, f.VoiceFeatures.MaxSize, name)
			require.NotNil(t, f.FileFeatures, name)
			require.Equal(t, waMax, f.FileFeatures.MaxSize, name)
			require.True(t, f.FileFeatures.Caption, name)
			require.NotNil(t, f.GIFFeatures, name)
			require.Equal(t, waMax, f.GIFFeatures.MaxSize, name)
			require.NotNil(t, f.StickerFeatures, name)
			require.Contains(t, f.StickerFeatures.MimeTypes, "image/webp", name)
			require.False(t, f.StickerFeatures.Caption, name)
			require.Equal(t, waMax, f.StickerFeatures.MaxSize, name)
			require.True(t, f.LocationSupported, name)
			require.True(t, f.LinkPreviewsSupported, name)

		case "signal":
			const sigMax = int64(100 * 1024 * 1024)
			require.NotNil(t, f.ImageFeatures, name)
			require.Equal(t, sigMax, f.ImageFeatures.MaxSize, name)
			require.True(t, f.ImageFeatures.Caption, name)
			require.Equal(t, 2000, f.ImageFeatures.MaxCaptionLength, name)
			require.NotNil(t, f.VideoFeatures, name)
			require.Equal(t, sigMax, f.VideoFeatures.MaxSize, name)
			require.NotNil(t, f.VoiceFeatures, name)
			require.Contains(t, f.VoiceFeatures.MimeTypes, "audio/aac", name)
			require.False(t, f.VoiceFeatures.Caption, name)
			require.Equal(t, sigMax, f.VoiceFeatures.MaxSize, name)
			require.Equal(t, 3600, f.VoiceFeatures.MaxDurationSec, name)
			require.NotNil(t, f.StickerFeatures, name)
			require.Contains(t, f.StickerFeatures.MimeTypes, "image/png", name)
			require.Contains(t, f.StickerFeatures.MimeTypes, "image/apng", name)
			require.Contains(t, f.StickerFeatures.MimeTypes, "image/webp", name)
			require.False(t, f.StickerFeatures.Caption, name)
			require.Equal(t, sigMax, f.StickerFeatures.MaxSize, name)
			require.True(t, f.LocationSupported, name)
			require.True(t, f.LinkPreviewsSupported, name)

		case "telegram":
			const tgMax = int64(2 * 1024 * 1024 * 1024)
			require.NotNil(t, f.ImageFeatures, name)
			require.Equal(t, int64(10*1024*1024), f.ImageFeatures.MaxSize, name)
			require.True(t, f.ImageFeatures.Caption, name)
			require.Equal(t, 1024, f.ImageFeatures.MaxCaptionLength, name)
			require.NotNil(t, f.VideoFeatures, name)
			require.Equal(t, tgMax, f.VideoFeatures.MaxSize, name)
			require.NotNil(t, f.VoiceFeatures, name)
			require.Equal(t, []string{"audio/mp4", "audio/mpeg", "audio/ogg"}, f.VoiceFeatures.MimeTypes, name)
			require.True(t, f.VoiceFeatures.Caption, name)
			require.Equal(t, 1024, f.VoiceFeatures.MaxCaptionLength, name)
			require.Equal(t, tgMax, f.VoiceFeatures.MaxSize, name)
			require.NotNil(t, f.StickerFeatures, name)
			require.Equal(t, []string{"image/jpeg", "image/png", "image/webp", "video/lottie+json", "video/webm"}, f.StickerFeatures.MimeTypes, name)
			require.False(t, f.StickerFeatures.Caption, name)
			require.Zero(t, f.StickerFeatures.MaxSize, name)
			require.True(t, f.LocationSupported, name)
			require.True(t, f.LinkPreviewsSupported, name)

		case "gmessages":
			const gmMax = int64(100 * 1024 * 1024)
			require.NotNil(t, f.ImageFeatures, name)
			require.Equal(t, gmMax, f.ImageFeatures.MaxSize, name)
			require.NotNil(t, f.VoiceFeatures, name)
			require.Contains(t, f.VoiceFeatures.MimeTypes, "audio/mp4", name)
			require.False(t, f.VoiceFeatures.Caption, name)
			require.Equal(t, gmMax, f.VoiceFeatures.MaxSize, name)
			require.Nil(t, f.StickerFeatures, name)
			require.False(t, f.LocationSupported, name)
			require.False(t, f.LinkPreviewsSupported, name)
			if name == "gmessages rcs" {
				require.False(t, f.ImageFeatures.Caption, name)
			} else {
				require.True(t, f.ImageFeatures.Caption, name)
			}

		case "slack":
			const slackMax = int64(1 * 1000 * 1000 * 1000)
			require.NotNil(t, f.ImageFeatures, name)
			require.Equal(t, slackMax, f.ImageFeatures.MaxSize, name)
			require.True(t, f.ImageFeatures.Caption, name)
			require.Equal(t, 40000, f.ImageFeatures.MaxCaptionLength, name)
			require.NotNil(t, f.VoiceFeatures, name)
			require.Contains(t, f.VoiceFeatures.MimeTypes, "audio/mp4", name)
			require.Contains(t, f.VoiceFeatures.MimeTypes, "audio/webm; codecs=opus", name)
			require.True(t, f.VoiceFeatures.Caption, name)
			require.Equal(t, 40000, f.VoiceFeatures.MaxCaptionLength, name)
			require.Equal(t, slackMax, f.VoiceFeatures.MaxSize, name)
			require.Equal(t, 300, f.VoiceFeatures.MaxDurationSec, name)
			require.Nil(t, f.StickerFeatures, name)
			require.False(t, f.LocationSupported, name)
			require.True(t, f.LinkPreviewsSupported, name)
		}
	}
}
