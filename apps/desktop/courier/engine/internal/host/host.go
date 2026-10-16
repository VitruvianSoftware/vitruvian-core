// Package host runs one network connector against courier's local store, with its own bridge database.
package host

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/rs/zerolog"
	"gopkg.in/yaml.v3"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/bridgeconfig"
	"maunium.net/go/mautrix/bridgev2/commands"
	"maunium.net/go/mautrix/bridgev2/networkid"

	"github.com/VitruvianSoftware/courier/engine/internal/ids"
	"github.com/VitruvianSoftware/courier/engine/internal/localmatrix"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// Host is one running bridge for one network.
type Host struct {
	Bridge  *bridgev2.Bridge
	Network string
}

// Start opens <dataDir>/bridges/<network>.db, loads the connector's example config as its defaults,
// and starts the bridge with the local user (@me) as admin. Starting again on the same dataDir
// reloads the logins made before.
func Start(ctx context.Context, dataDir, network string, s *store.Store, m *media.Store, nc bridgev2.NetworkConnector, log zerolog.Logger) (*Host, error) {
	if err := os.MkdirAll(filepath.Join(dataDir, "bridges"), 0o700); err != nil {
		return nil, err
	}
	// A connector's example config is the contents of its own "network:" section, with no wrapper key
	// (mxmain indents it under "network:" itself when it builds the full file). We have no user config
	// file yet, so the example is the whole config and no upgrader has anything to migrate.
	if example, data, _ := nc.GetConfig(); data != nil && example != "" {
		if err := yaml.Unmarshal([]byte(example), data); err != nil {
			return nil, fmt.Errorf("default %s config: %w", network, err)
		}
	}
	db, err := sqlite.Open(filepath.Join(dataDir, "bridges", network+".db"))
	if err != nil {
		return nil, err
	}
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix:   "!" + network,
		Permissions:     bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
		Backfill:        bridgeconfig.BackfillConfig{Enabled: true},
		CleanupOnLogout: bridgeconfig.CleanupOnLogouts{Enabled: false},
	}
	conn := localmatrix.New(network, s, m)
	br := bridgev2.NewBridge(networkid.BridgeID(network), db, log.With().Str("bridge", network).Logger(), cfg, conn, nc,
		func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	if err = br.Start(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("start %s bridge: %w", network, err)
	}
	return &Host{Bridge: br, Network: network}, nil
}

// Stop disconnects the logins and shuts the bridge down. bridgev2 closes the bridge database itself.
func (h *Host) Stop() { h.Bridge.Stop() }

// Me returns the local user, whose logins this host runs.
func (h *Host) Me(ctx context.Context) (*bridgev2.User, error) {
	return h.Bridge.GetUserByMXID(ctx, ids.Me)
}
