// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package networks

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	gmessages "go.mau.fi/mautrix-gmessages/pkg/connector"
	slack "go.mau.fi/mautrix-slack/pkg/connector"
	telegram "go.mau.fi/mautrix-telegram/pkg/connector"
	whatsapp "go.mau.fi/mautrix-whatsapp/pkg/connector"
	"gopkg.in/yaml.v3"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/actions"
	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
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

func TestNotStartedKeepsTheReasonAndDropsDuplicateKeys(t *testing.T) {
	got := NotStarted(map[string]error{
		"telegram":          errors.New("Telegram needs its own app credentials"),
		"slack (duplicate)": errors.New("network slack is already running; names must be unique"),
	})
	require.Equal(t, map[string]string{"telegram": "Telegram needs its own app credentials"}, got)
	require.Empty(t, NotStarted(nil))
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
	require.Equal(t, "{{or .BusinessName .PushName .Phone .RedactedPhone \"Unknown user\"}} (WA)", cfg.DisplaynameTemplate,
		"every other setting keeps the example's value")
}

// The "sent" rows of the plan's per-network table, checked against the client types of the pinned bridges. A
// bridge bump that adds or drops one of these handlers fails here, so the table (and what Courier tells people
// reaches each network) is looked at again.
func TestNetworkSyncTableMatchesTheBridges(t *testing.T) {
	want := map[string][]string{
		"whatsapp":  {"pin", "mute", "unread"},
		"telegram":  {"pin", "mute"},
		"gmessages": {},
		"slack":     {},
	}
	clients := map[string]bridgev2.NetworkAPI{
		"whatsapp":  (*whatsapp.WhatsAppClient)(nil),
		"telegram":  (*telegram.TelegramClient)(nil),
		"gmessages": (*gmessages.GMClient)(nil),
		"slack":     (*slack.SlackClient)(nil),
	}
	for name, c := range platformClients() {
		clients[name], want[name] = c.client, c.syncs
	}
	var registered []string
	for _, n := range All() {
		registered = append(registered, n.Name)
	}
	require.ElementsMatch(t, registered, keys(clients), "every registered network has a row")
	for name, c := range clients {
		require.Equal(t, want[name], actions.SyncsOf(c), name)
		// The same, asked of the bridgev2 interfaces directly.
		_, pin := c.(bridgev2.TagHandlingNetworkAPI)
		_, mute := c.(bridgev2.MuteHandlingNetworkAPI)
		_, unread := c.(bridgev2.MarkedUnreadHandlingNetworkAPI)
		_, accept := c.(bridgev2.MessageRequestAcceptingNetworkAPI)
		require.Equal(t, want[name], pick(pin, "pin", mute, "mute", unread, "unread", accept, "accept_request"), name)
	}
}

type platformClient struct {
	client bridgev2.NetworkAPI
	syncs  []string
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
