// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package host

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"
	"go.mau.fi/util/configupgrade"
	"maunium.net/go/mautrix/bridgev2"
	"maunium.net/go/mautrix/event"

	"github.com/VitruvianSoftware/courier/engine/internal/fakenet"
	"github.com/VitruvianSoftware/courier/engine/internal/media"
	"github.com/VitruvianSoftware/courier/engine/internal/sqlite"
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

func TestConfigureRunsAfterExampleDefaults(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()

	n := &configNet{Network: fakenet.New()}
	var seenGreeting string
	h, err := Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, n, zerolog.Nop(),
		WithConfigure(func(networkConfig any) error {
			cfg := networkConfig.(*struct {
				Greeting string `yaml:"greeting"`
				Retries  int    `yaml:"retries"`
			})
			seenGreeting = cfg.Greeting // the example default must already be in place
			cfg.Retries = 9
			return nil
		}))
	require.NoError(t, err)
	defer h.Stop()

	require.Equal(t, "hello", seenGreeting, "the hook must run after the example config is decoded")
	require.Equal(t, "hello", n.cfg.Greeting, "fields the hook leaves alone keep the example default")
	require.Equal(t, 9, n.cfg.Retries, "the hook's override must win over the example default")
}

func TestConfigureErrorFailsStartBeforeOpeningTheDatabase(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()

	_, err = Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, &configNet{Network: fakenet.New()}, zerolog.Nop(),
		WithConfigure(func(any) error { return errors.New("missing api id") }))
	require.ErrorContains(t, err, "missing api id")
	require.ErrorContains(t, err, "fake")
	require.NoFileExists(t, filepath.Join(dir, "bridges", "fake.db"))
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
	require.Equal(t, []event.RoomTag{"m.favourite", "m.lowpriority"}, c.OnlyBridgeTags,
		"without these no network pin or archive is ever taken in")
	// Deliberate departures from the example config:
	require.Empty(t, c.BridgeStatusNotices, "there is no admin-command room to post notices into")
	require.Zero(t, c.PortalEventBuffer, "events are handled synchronously so statuses are acknowledged in order")
	require.False(t, c.PersonalFilteringSpaces, "spaces are a Matrix-client feature; the app has no use for them")
	require.False(t, c.KickMatrixUsers, "@me is the only Matrix user, so never remove anyone")
	require.False(t, c.SplitPortals)
	require.False(t, c.AsyncEvents)
	require.False(t, c.Relay.Enabled)
}

func TestStartKeepsTheDataDirAndBridgeDatabasePrivate(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	require.NoError(t, os.Chmod(dir, 0o755), "fixture: the data dir already exists and is world-readable")
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()

	h, err := Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, fakenet.New(), zerolog.Nop())
	require.NoError(t, err)
	defer h.Stop()

	for path, want := range map[string]os.FileMode{
		dir:                                      0o700,
		filepath.Join(dir, "bridges"):            0o700,
		filepath.Join(dir, "bridges", "fake.db"): 0o600, // the WhatsApp device keys live in here
		filepath.Join(dir, "courier.db"):         0o600,
	} {
		fi, err := os.Stat(path)
		require.NoError(t, err)
		require.Equal(t, want, fi.Mode().Perm(), path)
	}
}

func TestStopIsIdempotent(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	h, err := Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, fakenet.New(), zerolog.Nop())
	require.NoError(t, err)
	require.NotPanics(t, func() {
		h.Stop()
		h.Stop()
	})
}

// bridgev2's Stop closes the database without waiting for goroutines still mid-query, so SQLite's
// -wal and -shm files can outlive it. Stop must not return until every connection is closed.
func TestStopWaitsForTheBridgeDatabaseToClose(t *testing.T) {
	ctx := context.Background()
	for i := 0; i < 20; i++ {
		dir := t.TempDir()
		s, err := store.Open(filepath.Join(dir, "courier.db"))
		require.NoError(t, err)
		n := fakenet.New()
		h, err := Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, n, zerolog.Nop())
		require.NoError(t, err)
		login, err := n.Login(ctx, h.Bridge)
		require.NoError(t, err)
		for j := 0; j < 5; j++ {
			n.Incoming(login, "chat1", "alice", fmt.Sprintf("m%d", j), "hello")
		}
		h.Stop()
		require.Zero(t, h.db.RawDB.Stats().OpenConnections, "run %d: Stop returned with the bridge database still open", i)
		// Leftover -wal/-shm files are not a sign of an open database: when two connections close at the same
		// moment, neither can take the lock SQLite needs to delete them, and the next open replays them.
		// What matters is that nothing writes after Stop and that the file opens cleanly again.
		bridges := filepath.Join(dir, "bridges")
		before := dirSnapshot(t, bridges)
		time.Sleep(20 * time.Millisecond)
		require.Equal(t, before, dirSnapshot(t, bridges), "run %d: the bridge database changed after Stop returned", i)
		reopened, err := sqlite.Open(filepath.Join(bridges, "fake.db"))
		require.NoError(t, err)
		var integrity string
		require.NoError(t, reopened.RawDB.QueryRow("PRAGMA integrity_check").Scan(&integrity))
		require.Equal(t, "ok", integrity, "run %d", i)
		require.NoError(t, reopened.Close())
		s.Close()
	}
}

// dirSnapshot lists each file in dir with its size and modification time.
func dirSnapshot(t *testing.T, dir string) map[string]string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	require.NoError(t, err)
	snap := map[string]string{}
	for _, e := range entries {
		info, err := e.Info()
		require.NoError(t, err)
		snap[e.Name()] = fmt.Sprintf("%d %d", info.Size(), info.ModTime().UnixNano())
	}
	return snap
}

func TestConfigureWithNoConfigIsAnError(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	called := false
	_, err = Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, fakenet.New(), zerolog.Nop(),
		WithConfigure(func(any) error { called = true; return nil }))
	require.ErrorContains(t, err, "fake has no config to configure")
	require.False(t, called)
	require.NoFileExists(t, filepath.Join(dir, "bridges", "fake.db"))
}

// stuckNet is a network whose logins never finish disconnecting, like a connector stuck on a dead socket.
type stuckNet struct {
	*fakenet.Network
	release chan struct{}
}

func (n *stuckNet) LoadUserLogin(ctx context.Context, login *bridgev2.UserLogin) error {
	if err := n.Network.LoadUserLogin(ctx, login); err != nil {
		return err
	}
	login.Client = &stuckClient{NetworkAPI: login.Client, release: n.release}
	return nil
}

type stuckClient struct {
	bridgev2.NetworkAPI
	release chan struct{}
}

func (c *stuckClient) Disconnect() { <-c.release }

func TestStopDoesNotHangOnALoginThatWontDisconnect(t *testing.T) {
	old := stopTimeout
	stopTimeout = 200 * time.Millisecond
	t.Cleanup(func() { stopTimeout = old })

	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	n := &stuckNet{Network: fakenet.New(), release: make(chan struct{})}
	defer close(n.release)
	h, err := Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, n, zerolog.Nop())
	require.NoError(t, err)
	_, err = n.Login(ctx, h.Bridge)
	require.NoError(t, err)

	done := make(chan struct{})
	go func() { h.Stop(); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Stop is still waiting for a login that will never disconnect")
	}
}

// panicNet is a connector whose Start panics.
type panicNet struct{ *fakenet.Network }

func (n *panicNet) Start(context.Context) error { panic("start panic") }

func TestPanicDuringStartClosesTheBridgeDatabase(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	require.Panics(t, func() {
		_, _ = Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, &panicNet{fakenet.New()}, zerolog.Nop())
	})
	// An open SQLite database in WAL mode keeps its -wal and -shm files; a closed one leaves only the .db.
	require.Eventually(t, func() bool {
		entries, err := os.ReadDir(filepath.Join(dir, "bridges"))
		return err == nil && len(entries) == 1 && entries[0].Name() == "fake.db"
	}, 5*time.Second, 20*time.Millisecond, "the bridge database must be closed when start-up panics")
}

func TestHostEnablesPhoneNumbersInProfile(t *testing.T) {
	ctx, dir := context.Background(), t.TempDir()
	s, err := store.Open(filepath.Join(dir, "courier.db"))
	require.NoError(t, err)
	defer s.Close()
	h, err := Start(ctx, dir, "fake", s, &media.Store{Dir: filepath.Join(dir, "media")}, fakenet.New(), zerolog.Nop())
	require.NoError(t, err)
	defer h.Stop()
	require.True(t, h.Bridge.Config.PhoneNumbersInProfile)
	require.True(t, h.Bridge.Config.BridgeMatrixLeave)
}
