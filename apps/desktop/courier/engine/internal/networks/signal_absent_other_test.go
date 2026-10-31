// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//go:build !darwin

package networks

import (
	"testing"

	"github.com/stretchr/testify/require"
)

// Off macOS there is no libsignal_ffi.a or libgchat_ffi.a, so Signal and Google Chat must not be registered.
func TestSignalIsAbsentOffDarwin(t *testing.T) {
	var names []string
	for _, n := range All() {
		names = append(names, n.Name)
	}
	require.Equal(t, []string{"whatsapp", "telegram", "gmessages", "slack"}, names)
	_, ok := Get("signal")
	require.False(t, ok)
	_, ok = Get("gchat")
	require.False(t, ok)
}

// platformClients has no row to add off macOS: Signal isn't built here.
func platformClients() map[string]platformClient { return nil }

// platformActionRows has no rows to add off macOS: Signal isn't built here.
func platformActionRows() (map[string]actionRow, map[string]handlerRow) { return nil, nil }

// platformPollChecks has nothing to add off macOS.
func platformPollChecks() map[string]func(data any) bool { return nil }

// platformReceiptColumns has no column to add off macOS: Signal isn't built here.
func platformReceiptColumns() map[string]receiptNetwork { return nil }
