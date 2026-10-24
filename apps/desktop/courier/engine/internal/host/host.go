// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package host runs one network connector against courier's local store, with its own bridge database.
package host

import (
	"context"
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"github.com/rs/zerolog"
	"go.mau.fi/util/dbutil"
	"gopkg.in/yaml.v3"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/bridgev2/bridgeconfig"
	"maunium.net/go/mautrix/bridgev2/commands"
	"maunium.net/go/mautrix/bridgev2/networkid"
	"maunium.net/go/mautrix/event"

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
	db      *dbutil.Database
	log     zerolog.Logger
	stop    sync.Once
}

// Option adjusts how Start prepares a bridge.
type Option func(*options)

type options struct{ configure func(any) error }

// WithConfigure runs after the connector's example config is decoded and before the bridge starts,
// so a network can fill in values the example cannot hold (Telegram's API credentials).
// A connector with no config to decode into makes Start fail ("has no config to configure"):
// a hook that cannot apply must not be skipped silently.
func WithConfigure(f func(networkConfig any) error) Option {
	return func(o *options) { o.configure = f }
}

// Start opens <dataDir>/bridges/<network>.db, loads the connector's example config as its defaults,
// and starts the bridge with the local user (@me) as admin. Starting again on the same dataDir
// reloads the logins made before.
func Start(ctx context.Context, dataDir, network string, s *store.Store, m *media.Store, nc bridgev2.NetworkConnector, log zerolog.Logger, opts ...Option) (*Host, error) {
	var o options
	for _, opt := range opts {
		opt(&o)
	}
	// The bridge database holds the linked device's keys: keep the whole tree private, even if dataDir existed.
	for _, d := range []string{dataDir, filepath.Join(dataDir, "bridges")} {
		if err := sqlite.PrivateDir(d); err != nil {
			return nil, err
		}
	}
	// A connector's example config is the contents of its own "network:" section, with no wrapper key
	// (mxmain indents it under "network:" itself when it builds the full file). We have no user config
	// file yet, so the example is the whole config and no upgrader has anything to migrate.
	example, data, _ := nc.GetConfig()
	if data != nil && example != "" {
		if err := yaml.Unmarshal([]byte(example), data); err != nil {
			return nil, fmt.Errorf("default %s config: %w", network, err)
		}
	}
	if o.configure != nil {
		if data == nil {
			return nil, fmt.Errorf("%s has no config to configure", network)
		}
		if err := o.configure(data); err != nil {
			return nil, fmt.Errorf("configure %s: %w", network, err)
		}
	}
	db, err := sqlite.Open(filepath.Join(dataDir, "bridges", network+".db"))
	if err != nil {
		return nil, err
	}
	// Closed again on every way out but success, a panic in the connector included (the engine recovers it and
	// carries on with the other networks, so the file must not stay open).
	started := false
	defer func() {
		if !started {
			db.Close()
		}
	}()
	cfg := &bridgeconfig.BridgeConfig{
		CommandPrefix: "!" + network,
		// The rest of this section follows mxmain's v0.31.0 example config unless a comment says otherwise.
		// Without this, bridgev2 never names a DM after the contact (portal.go and ghost.go check it).
		PrivateChatPortalMeta: true,
		PhoneNumbersInProfile: true,
		// Connecting a login returns before the network says it is logged in. A send in that gap, or during a
		// reconnect, waits this long instead of failing at once. The example's 0s is wrong for a local app.
		SendReconnectWait: 15 * time.Second,
		// The example leaves auto-reconnect off because an operator restarts a server bridge. Nobody restarts
		// this one, so retry after an unknown error (the minimum bridgev2 accepts is 1 minute).
		UnknownErrorAutoReconnect:     5 * time.Minute,
		UnknownErrorMaxAutoReconnects: 10,
		// A chat's pin, archive and mute on the network are taken in when it first arrives and never again, so a
		// later change on the phone doesn't fight one made in Courier. Only these two tags mean anything to the
		// store (pinned, archived); without the list no tag is taken in at all.
		TagOnlyOnCreate:  true,
		MuteOnlyOnCreate: true,
		OnlyBridgeTags:   []event.RoomTag{event.RoomTagFavourite, event.RoomTagLowPriority},
		// Deliberately not the example's values:
		//  - BridgeStatusNotices stays "": there is no admin-command room to post into.
		//  - PortalEventBuffer stays 0: events are handled and acknowledged synchronously, in order.
		//  - PersonalFilteringSpaces stays false: a space per login is a Matrix-client feature the app has no use for.
		//  - KickMatrixUsers stays false: @me is the only Matrix user and must never be removed from a room.
		Permissions: bridgeconfig.PermissionConfig{string(ids.Me): &bridgeconfig.PermissionLevelAdmin},
		// Enabled alone loads nothing: bridgev2 skips backfill when the message limits are zero. The numbers are
		// mautrix's own example-config defaults. The backwards queue stays off; it only applies to Beeper's server.
		Backfill: bridgeconfig.BackfillConfig{
			Enabled:              true,
			MaxInitialMessages:   50,
			MaxCatchupMessages:   500,
			UnreadHoursThreshold: 720,
			Threads:              bridgeconfig.BackfillThreadsConfig{MaxInitialMessages: 50},
		},
		CleanupOnLogout: bridgeconfig.CleanupOnLogouts{Enabled: false},
	}
	conn := localmatrix.New(network, s, m)
	br := bridgev2.NewBridge(networkid.BridgeID(network), db, log.With().Str("bridge", network).Logger(), cfg, conn, nc,
		func(b *bridgev2.Bridge) bridgev2.CommandProcessor { return commands.NewProcessor(b) })
	if err = br.Start(ctx); err != nil {
		return nil, fmt.Errorf("start %s bridge: %w", network, err)
	}
	started = true
	return &Host{Bridge: br, Network: network, db: db, log: log.With().Str("bridge", network).Logger()}, nil
}

// Stop shuts the bridge down (Bridge.StopWithTimeout) and then waits for its database's connections to be let go.
// What it waits for, in order: every login's Disconnect, all at once, each for at most stopTimeout (one whose network
// won't disconnect is left behind, so quitting never hangs on one network); the connector's Stop (the bridge-state
// writes already under way); the network connector's own Stop; bridgev2 closing the database. Then, for at most
// dbCloseTimeout, it waits until the database has no open connection, and logs if one is still open. bridgev2 does
// not wait for goroutines still mid-query (portal loops, the backfill queue, bridge-state sending), and
// sql.DB.Close does not wait for connections in use.
// Until the last one is released SQLite's -wal and -shm files stay on disk, which a restart or a directory
// cleanup would trip over. Safe to call more than once.
func (h *Host) Stop() {
	h.stop.Do(func() {
		h.Bridge.StopWithTimeout(stopTimeout)
		deadline := time.Now().Add(dbCloseTimeout)
		for h.db.RawDB.Stats().OpenConnections > 0 {
			if time.Now().After(deadline) {
				h.log.Warn().Int("open_connections", h.db.RawDB.Stats().OpenConnections).
					Msg("bridge database still has open connections after Stop")
				return
			}
			time.Sleep(5 * time.Millisecond)
		}
	})
}

// dbCloseTimeout bounds how long Stop waits for in-flight queries to finish.
const dbCloseTimeout = 5 * time.Second

// stopTimeout bounds how long Stop waits for each login to disconnect. A variable so a test can shorten it.
var stopTimeout = 10 * time.Second

// Me returns the local user, whose logins this host runs.
func (h *Host) Me(ctx context.Context) (*bridgev2.User, error) {
	return h.Bridge.GetUserByMXID(ctx, ids.Me)
}
