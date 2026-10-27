// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package logscrub

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
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

func TestScrubPathReplacesUserHomeDirAndRealpath(t *testing.T) {
	t.Setenv("HOME", "/Volumes/Data/alice-example")
	require.Equal(
		t,
		"open ~/Library/Application Support/Courier/courier.db: permission denied",
		ScrubPath("open /Volumes/Data/alice-example/Library/Application Support/Courier/courier.db: permission denied"),
	)
	require.Equal(
		t,
		"cannot mkdir ~: file exists",
		ScrubPath("cannot mkdir /Volumes/Data/alice-example: file exists"),
	)

	// Symlinked HOME -> realpath must also be scrubbed.
	base := t.TempDir()
	realHome := filepath.Join(base, "real-alice-home")
	linkHome := filepath.Join(base, "link-alice-home")
	require.NoError(t, os.MkdirAll(realHome, 0o700))
	require.NoError(t, os.Symlink(realHome, linkHome))
	t.Setenv("HOME", linkHome)

	resolvedReal, err := filepath.EvalSymlinks(realHome)
	require.NoError(t, err)
	require.Equal(
		t,
		"open ~/Library/Courier/courier.db",
		ScrubPath("open "+resolvedReal+"/Library/Courier/courier.db"),
	)
	require.Equal(
		t,
		"open ~/Library/Courier/courier.db",
		ScrubPath("open "+linkHome+"/Library/Courier/courier.db"),
	)
}

func TestRollingFileRolloverHalvesAndAppends(t *testing.T) {
	path := filepath.Join(t.TempDir(), StderrLogName)
	const maxBytes = 200
	rf, err := OpenRollingFile(path, maxBytes)
	require.NoError(t, err)
	defer rf.Close()

	// Write 4 lines of 45 bytes each = 180 bytes (under maxBytes = 200).
	for i := 1; i <= 4; i++ {
		line := fmt.Sprintf("{\"level\":\"info\",\"message\":\"line-%02d-padding\"}\n", i)
		require.Len(t, line, 45)
		_, err := rf.Write([]byte(line))
		require.NoError(t, err)
	}

	// Verify ordinary writes append to the existing file without rewriting earlier bytes:
	// overwrite byte 0 on disk via a separate descriptor, then do one more non-rollover write (10 bytes -> 190 <= 200).
	fCheck, err := os.OpenFile(path, os.O_WRONLY, 0o600)
	require.NoError(t, err)
	_, err = fCheck.WriteAt([]byte("X"), 0)
	require.NoError(t, err)
	require.NoError(t, fCheck.Close())

	_, err = rf.Write([]byte("short1234\n"))
	require.NoError(t, err)

	beforeRollover, err := os.ReadFile(path)
	require.NoError(t, err)
	require.Equal(t, byte('X'), beforeRollover[0], "ordinary write must append to the open file without rewriting the whole file")

	// Next 45-byte write pushes total to 235 > 200, triggering rollover to <= maxBytes/2 (100 bytes).
	fifth := fmt.Sprintf("{\"level\":\"info\",\"message\":\"line-%02d-padding\"}\n", 5)
	_, err = rf.Write([]byte(fifth))
	require.NoError(t, err)

	afterRollover, err := os.ReadFile(path)
	require.NoError(t, err)
	require.LessOrEqual(t, len(afterRollover), maxBytes/2, "rollover must trim retained file to <= maxBytes/2")
	require.True(t, strings.HasSuffix(string(afterRollover), fifth))
}

type genericCrashBox[T any] struct {
	val T
}

//go:noinline
func (b *genericCrashBox[T]) crash(secret T) {
	panic(secret)
}

//go:noinline
func triggerGenericPanic[T any](secret T) (stack string) {
	defer func() {
		if recover() != nil {
			stack = string(debug.Stack())
		}
	}()
	box := &genericCrashBox[T]{val: secret}
	box.crash(secret)
	return ""
}

func TestScrubStderrExportPreservesRealPanicAndGenericFrames(t *testing.T) {
	realStack := triggerGenericPanic("+14155550199 secret panic payload")
	require.Contains(t, realStack, "panic(")

	dump := "panic: +14155550199 secret panic payload\n\n" + realStack +
		"\ngithub.com/VitruvianSoftware/courier/engine/internal/logscrub.instantiated[go.shape.int,int](0x14000123456)\n" +
		"\t/Users/alice/Workspace/vitruvian-core/apps/desktop/courier/engine/internal/logscrub/stack_test.go:180 +0x20\n"

	scrubbed := ScrubStderrExport(dump)
	joined := strings.Join(scrubbed, "\n")

	require.Contains(t, scrubbed, "panic: [redacted]")
	require.Contains(t, scrubbed, "panic(...)", "real Go runtime panic(...) frame must be preserved")
	require.Contains(t, joined, "genericCrashBox[...]).crash(...)", "real Go generic method frame must be preserved")
	require.Contains(t, joined, "triggerGenericPanic[...](...)", "real Go generic function frame must be preserved")
	require.Contains(t, joined, "instantiated[go.shape.int,int](...)", "concrete/shape generic frame must be preserved")
	require.NotContains(t, joined, "+14155550199")
	require.NotContains(t, joined, "secret panic payload")
}
