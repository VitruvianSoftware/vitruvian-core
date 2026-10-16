// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package host

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"go.mau.fi/util/configupgrade"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

func TestHostRestartReloadsLogin(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	m := &media.Store{Dir: filepath.Join(dir, "media")}

	net1 := fakenet.New()
	h1, err := Start(ctx, dir, "fake", s, m, net1, zerolog.Nop())
	require.NoError(t, err)
	_, err = net1.Login(ctx, h1.Bridge)
	require.NoError(t, err)
	h1.Stop()

	h2, err := Start(ctx, dir, "fake", s, m, fakenet.New(), zerolog.Nop())
	require.NoError(t, err)
	defer h2.Stop()
	me, err := h2.Me(ctx)
	require.NoError(t, err)
	require.Len(t, me.GetUserLogins(), 1, "the login made before the restart must be loaded again")
}

// configNet is a fake network that, like a real connector, returns its example config unwrapped
// (the contents of the network section itself) and a pointer for it to be decoded into.
type configNet struct {
	*fakenet.Network
	cfg struct {
		Greeting string `yaml:"greeting"`
		Retries  int    `yaml:"retries"`
	}
}

func (n *configNet) GetConfig() (string, any, configupgrade.Upgrader) {
	return "# Comments are fine.\ngreeting: hello\nretries: 3\n", &n.cfg, configupgrade.NoopUpgrader
}

func TestStartAppliesConnectorConfigDefaults(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()

	n := &configNet{Network: fakenet.New()}
	h, err := Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, n, zerolog.Nop())
	require.NoError(t, err)
	defer h.Stop()

	require.Equal(t, "hello", n.cfg.Greeting, "the connector's example config must become its defaults")
	require.Equal(t, 3, n.cfg.Retries)
}

func TestStartRejectsUnparseableConnectorConfig(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()

	n := &configNet{Network: fakenet.New()}
	bad := &badConfigNet{configNet: n}
	_, err = Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, bad, zerolog.Nop())
	require.Error(t, err, "a broken default config must fail loudly, not be skipped")
	require.NoFileExists(t, filepath.Join(dir, "bridges", "fake.db"), "a failed config must not leave a database behind")
}

type badConfigNet struct{ *configNet }

func (n *badConfigNet) GetConfig() (string, any, configupgrade.Upgrader) {
	return "greeting: [unclosed\n", &n.cfg, configupgrade.NoopUpgrader
}

func TestStartGivesLocalUserAdminAndBackfill(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()

	h, err := Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, fakenet.New(), zerolog.Nop())
	require.NoError(t, err)
	defer h.Stop()

	me, err := h.Me(ctx)
	require.NoError(t, err)
	require.True(t, me.Permissions.Admin, "@me must be admin of its own bridge")
	// "Enabled" alone loads nothing: bridgev2 skips backfill when the message limits are zero.
	bf := h.Bridge.Config.Backfill
	require.True(t, bf.Enabled)
	require.Equal(t, 50, bf.MaxInitialMessages, "history for a new room")
	require.Equal(t, 500, bf.MaxCatchupMessages, "messages missed while courier was closed")
	require.Equal(t, 720, bf.UnreadHoursThreshold)
	require.Equal(t, 50, bf.Threads.MaxInitialMessages)
	require.False(t, bf.Queue.AnyEnabled(), "the backwards queue only applies to Beeper's server")
	require.False(t, h.Bridge.Config.CleanupOnLogout.Enabled)
	require.FileExists(t, filepath.Join(dir, "bridges", "fake.db"), "each network gets its own database")
}

// The bridge section mirrors mxmain's v0.31.0 example config, except where a local single-user app differs.
func TestStartBridgeConfigMatchesExampleDefaults(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()

	h, err := Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, fakenet.New(), zerolog.Nop())
	require.NoError(t, err)
	defer h.Stop()

	c := h.Bridge.Config
	require.True(t, c.PrivateChatPortalMeta, "without this, DMs get no name or avatar from the contact")
	require.Equal(t, 15*time.Second, c.SendReconnectWait, "a send during a reconnect waits instead of failing at once")
	require.Equal(t, 5*time.Minute, c.UnknownErrorAutoReconnect, "nothing restarts a local app that hit an unknown error")
	require.Equal(t, 10, c.UnknownErrorMaxAutoReconnects)
	require.True(t, c.TagOnlyOnCreate)
	require.True(t, c.MuteOnlyOnCreate)
	// Deliberate departures from the example config:
	require.Empty(t, c.BridgeStatusNotices, "there is no admin-command room to post notices into")
	require.Zero(t, c.PortalEventBuffer, "events are handled synchronously so statuses are acknowledged in order")
	require.False(t, c.PersonalFilteringSpaces, "spaces are a Matrix-client feature; the app has no use for them")
	require.False(t, c.KickMatrixUsers, "@me is the only Matrix user, so never remove anyone")
	require.False(t, c.SplitPortals)
	require.False(t, c.AsyncEvents)
	require.False(t, c.Relay.Enabled)
}
