// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package logscrub

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestScrubStderrExport(t *testing.T) {
	dump := strings.Join([]string{
		`{"level":"warn","bridge":"whatsapp","pn":"+14155550199","token":"xoxc-123-456","time":"2026-10-25T12:00:00Z","message":"syncing +14155550199 with xoxc-123-456"}`,
		`{"level":"warn","broken_json":`,
		`{"msg":"unreadable log line dropped"}`,
		`arbitrary debug print from library with phone +14155550199 and token xoxc-123-456`,
		`courier-engine: open /Users/alice/Library/Application Support/Courier/courier.db: permission denied (token xoxc-123-456, phone +14155550199)`,
		`panic: failed to parse "+14155550199: secret message" with token xoxc-123-456`,
		`fatal error: concurrent map writes for +14155550199`,
		``,
		`goroutine 42 [running]:`,
		`maunium.net/go/mautrix/bridgev2.(*Portal).handleRemoteEvent(0x1400012a000, {0x104c92a00, 0x14000180000})`,
		"\t/Users/alice/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/bridgev2/portal.go:2690 +0x1c4",
		`github.com/VitruvianSoftware/courier/engine/internal/host.(*Host).Start(0x1400012a000, 0x14000999000)`,
		"\t/Users/alice/Workspace/vitruvian-core/apps/desktop/courier/engine/internal/host/host.go:200 +0x88",
		`created by maunium.net/go/mautrix/bridgev2.(*Bridge).StartLogins in goroutine 1`,
		"\t/Users/alice/go/pkg/mod/maunium.net/go/mautrix@v0.31.0/bridgev2/bridge.go:366 +0x40",
		`goroutine 1 [chan receive]:`,
		`main.run({0x1400012a000, 0x24}, {0x104c8a2e0, 0x14000010018})`,
		"\t/Users/alice/Workspace/vitruvian-core/apps/desktop/courier/engine/cmd/courier-engine/main.go:205",
		`random trailing line with secret +14155550199`,
	}, "\n")

	got := ScrubStderrExport(dump)
	want := []string{
		`{"level":"warn","bridge":"whatsapp","time":"2026-10-25T12:00:00Z","message":"syncing [id] with [id]"}`,
		`courier-engine: open ~/Library/Application Support/Courier/courier.db: permission denied (token [id], phone [id])`,
		`panic: [redacted]`,
		`fatal error: [redacted]`,
		`goroutine 42 [running]:`,
		`maunium.net/go/mautrix/bridgev2.(*Portal).handleRemoteEvent(...)`,
		"\tmaunium.net/go/mautrix@v0.31.0/bridgev2/portal.go:2690 +0x1c4",
		`github.com/VitruvianSoftware/courier/engine/internal/host.(*Host).Start(...)`,
		"\tgithub.com/VitruvianSoftware/courier/engine/internal/host/host.go:200 +0x88",
		`created by maunium.net/go/mautrix/bridgev2.(*Bridge).StartLogins in goroutine 1`,
		"\tmaunium.net/go/mautrix@v0.31.0/bridgev2/bridge.go:366 +0x40",
		`goroutine 1 [chan receive]:`,
		`main.run(...)`,
		"\tgithub.com/VitruvianSoftware/courier/engine/cmd/courier-engine/main.go:205",
	}
	require.Equal(t, want, got)

	joined := strings.Join(got, "\n")
	for _, forbidden := range []string{
		"+14155550199",
		"14155550199",
		"xoxc-123-456",
		"secret message",
		"0x1400012a000",
		"/Users/alice",
		"alice",
		"arbitrary debug print",
		"random trailing line",
	} {
		require.NotContains(t, joined, forbidden)
	}
}

func TestScrubPathAndStartupError(t *testing.T) {
	require.Equal(
		t,
		"open ~/Library/Application Support/Courier/courier.db: token [id] for [id]",
		ScrubPath("open /Users/alice/Library/Application Support/Courier/courier.db: token xoxc-123-456 for +14155550199"),
	)
	require.Equal(
		t,
		"open ~/data/courier.db: permission denied",
		ScrubPath("open /home/bob/data/courier.db: permission denied"),
	)
	require.Equal(
		t,
		"courier-engine: cannot open ~/Library/Application Support/Courier: [id]",
		ScrubStartupError("courier-engine:", errors.New("cannot open /Users/alice/Library/Application Support/Courier: +14155550199")),
	)
	require.Equal(
		t,
		"error: cannot open ~/Library/Application Support/Courier-m1: [id]",
		ScrubStartupError("error:", errors.New("cannot open /Users/alice/Library/Application Support/Courier-m1: xoxc-123-456")),
	)
}

func TestRollingFileBoundsAt256KB(t *testing.T) {
	path := filepath.Join(t.TempDir(), StderrLogName)
	rf, err := OpenRollingFile(path, MaxStderrLogBytes)
	require.NoError(t, err)
	defer rf.Close()

	fi, err := os.Stat(path)
	require.NoError(t, err)
	require.Equal(t, os.FileMode(0o600), fi.Mode().Perm())

	line := `{"level":"warn","bridge":"whatsapp","message":"test log line for rollover"}` + "\n"
	// Write ~400 KB of log lines so it rolls over at 256 KB.
	count := (400 << 10) / len(line)
	for range count {
		_, err := rf.Write([]byte(line))
		require.NoError(t, err)
	}
	_, err = rf.Write([]byte(`{"level":"error","bridge":"signal","message":"latest line stays"}` + "\n"))
	require.NoError(t, err)
	require.NoError(t, rf.Close())

	data, err := os.ReadFile(path)
	require.NoError(t, err)
	require.LessOrEqual(t, len(data), MaxStderrLogBytes)
	require.Greater(t, len(data), MaxStderrLogBytes/2)
	require.True(t, strings.HasSuffix(string(data), `{"level":"error","bridge":"signal","message":"latest line stays"}`+"\n"))

	exported := ScrubStderrExport(string(data))
	require.NotEmpty(t, exported)
	require.Equal(t, `{"level":"error","bridge":"signal","message":"latest line stays"}`, exported[len(exported)-1])
}
