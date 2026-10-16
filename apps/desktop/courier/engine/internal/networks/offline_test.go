// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package networks

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	telegram "go.mau.fi/mautrix-telegram/pkg/connector"
	whatsapp "go.mau.fi/mautrix-whatsapp/pkg/connector"

	"github.com/VitruvianSoftware/courier/engine/internal/host"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// This runs every registered network's real connector through host.Start. It needs no account and no network:
// with no login there is nothing to connect, but Start still decodes the connector's example config, applies the
// spec's own configuration, upgrades the bridge's databases, and wires the connector to the local store. The
// second start is the "open the app again" path over the databases the first one created.
//
// Every connector's Start was read at its pinned version and touches only the local database without a login
// (WhatsApp: whatsmeow and bridge schema upgrades plus a database-only DM migration; Telegram: Store.Upgrade;
// Google Messages: DB.Upgrade plus a database-only portal-ID revert; Slack: DB.Upgrade; Signal, on macOS:
// ResetHTTPTransport only builds a local HTTP client, then Store.Upgrade, connector.go:78-85 of mautrix-signal
// v0.2609.0), so no network is skipped.
func TestEveryNetworkStartsOfflineTwice(t *testing.T) {
	t.Setenv("COURIER_TELEGRAM_API_ID", "424242")
	t.Setenv("COURIER_TELEGRAM_API_HASH", "0123456789abcdef0123456789abcdef")

	for _, n := range All() {
		t.Run(n.Name, func(t *testing.T) {
			ctx, dir := context.Background(), t.TempDir()
			s, err := store.Open(filepath.Join(dir, "courier.db"))
			require.NoError(t, err)
			defer s.Close()
			m := &media.Store{Dir: filepath.Join(dir, "media")}

			spec, err := n.Spec()
			require.NoError(t, err)
			for run := 1; run <= 2; run++ {
				nc, err := spec.Connector()
				require.NoError(t, err)
				var opts []host.Option
				if spec.Configure != nil {
					opts = append(opts, host.WithConfigure(spec.Configure))
				}
				h, err := host.Start(ctx, dir, spec.Name, s, m, nc, zerolog.Nop(), opts...)
				require.NoError(t, err, "start %d", run)

				switch c := nc.(type) {
				case *whatsapp.WhatsAppConnector:
					require.Equal(t, `{{or .BusinessName .PushName .Phone .RedactedPhone "Unknown user"}} (WA)`, c.Config.DisplaynameTemplate,
						"start %d: the connector's example config must become its real defaults", run)
				case *telegram.TelegramConnector:
					require.Equal(t, 424242, c.Config.APIID, "start %d: the spec's credentials must reach the connector", run)
					require.Equal(t, "0123456789abcdef0123456789abcdef", c.Config.APIHash)
				}
				me, err := h.Me(ctx)
				require.NoError(t, err)
				require.Empty(t, me.GetUserLogins(), "nobody has linked %s in this data dir", n.Name)
				h.Stop()
			}
			require.FileExists(t, filepath.Join(dir, "bridges", n.Name+".db"))
		})
	}
}
