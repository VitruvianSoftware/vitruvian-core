// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//go:build darwin

package networks

import (
	"testing"

	"github.com/stretchr/testify/require"
	signal "go.mau.fi/mautrix-signal/pkg/connector"
)

// On macOS Signal is the last network, after the portable four.
func TestSignalIsRegisteredLastOnDarwin(t *testing.T) {
	var names []string
	for _, n := range All() {
		names = append(names, n.Name)
	}
	require.Equal(t, []string{"whatsapp", "telegram", "gmessages", "slack", "signal"}, names)

	signal, ok := Get("signal")
	require.True(t, ok)
	require.Equal(t, "Signal", signal.DisplayName)
	require.Equal(t, []string{"qr"}, signal.Flows)
}

// platformClients adds Signal's row of the sync table: it takes message-request accepts and nothing else.
func platformClients() map[string]platformClient {
	return map[string]platformClient{"signal": {
		client: (*signal.SignalClient)(nil), sent: []string{"accept_request"}, implements: []string{"accept_request"},
	}}
}
