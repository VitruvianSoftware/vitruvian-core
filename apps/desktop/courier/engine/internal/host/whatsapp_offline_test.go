// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package host

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"go.mau.fi/mautrix-whatsapp/pkg/connector"

	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// This is the one test that runs the real mautrix-whatsapp connector through host.Start. It needs no account and
// no network: with no login there is nothing to connect, but Start still decodes the connector's example config,
// upgrades the whatsmeow and bridge databases, and wires the connector to the local store. The second start is
// the "open the app again" path over the databases the first one created.
func TestStartWithRealWhatsAppConnectorOffline(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	m := &media.Store{Dir: filepath.Join(dir, "media")}

	for run := 1; run <= 2; run++ {
		wa := &connector.WhatsAppConnector{}
		h, err := Start(ctx, dir, "whatsapp", s, m, wa, zerolog.Nop())
		require.NoError(t, err, "start %d", run)

		require.Equal(t, `{{or .BusinessName .PushName .Phone .RedactedPhone "Unknown user"}} (WA)`, wa.Config.DisplaynameTemplate,
			"start %d: the connector's example config must become its real defaults", run)
		me, err := h.Me(ctx)
		require.NoError(t, err)
		require.Empty(t, me.GetUserLogins(), "nobody has linked WhatsApp in this data dir")
		h.Stop()
	}
	require.FileExists(t, filepath.Join(dir, "bridges", "whatsapp.db"))
}
