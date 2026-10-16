// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package networks

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	telegram "go.mau.fi/mautrix-telegram/pkg/connector"
	"gopkg.in/yaml.v3"
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
