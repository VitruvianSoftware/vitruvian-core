// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package search

import (
	"bytes"
	"context"
	"encoding/json"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/rs/zerolog"
	"github.com/stretchr/testify/require"

	"github.com/VitruvianSoftware/courier/engine/internal/store"
	"github.com/VitruvianSoftware/courier/engine/internal/store/storetest"
)

// batchFailed is the warning RunBackfill logs for a failed batch.
const batchFailed = "search backfill: a batch failed; trying again later"

// waitLimit bounds every wait in these tests. It is generous: nothing here is a timing assertion.
const waitLimit = 60 * time.Second

// logBuf is a log destination safe to read while the backfill writes to it.
type logBuf struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *logBuf) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

func (l *logBuf) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.String()
}

// lines are the log lines at level.
func (l *logBuf) lines(t *testing.T, level string) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, line := range strings.Split(strings.TrimSpace(l.String()), "\n") {
		if line == "" {
			continue
		}
		var m map[string]any
		require.NoError(t, json.Unmarshal([]byte(line), &m), line)
		if m["level"] == level {
			out = append(out, m)
		}
	}
	return out
}

// warnings are the warn lines, less the database layer's notes that a transaction took over a second: those depend
// on how busy the machine is (the race detector, tests in parallel), and say nothing about what is tested.
func (l *logBuf) warnings(t *testing.T) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, w := range l.lines(t, "warn") {
		if w["message"] != "Transaction took long" && w["message"] != "Transaction still running" {
			out = append(out, w)
		}
	}
	return out
}

// newLog is a logger like the engine's: info and above.
func newLog() (*logBuf, zerolog.Logger) {
	b := &logBuf{}
	return b, zerolog.New(b).Level(zerolog.InfoLevel)
}

// seeded is a store whose database held n messages before migration 4 (see storetest). The caller closes it.
func seeded(t *testing.T, n int) (*store.Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "courier.db")
	s, err := store.Open(path)
	require.NoError(t, err)
	require.NoError(t, s.Close())
	storetest.SeedUnindexed(t, path, n)
	s, err = store.Open(path)
	require.NoError(t, err)
	return s, path
}

func complete(t *testing.T, s *store.Store) bool {
	t.Helper()
	c, err := s.SearchComplete(context.Background())
	require.NoError(t, err)
	return c
}

// waitFor polls cond until it holds; it fails the test after waitLimit.
func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(waitLimit)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatalf("waited %v for %s", waitLimit, what)
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// returned waits for done to close.
func returned(t *testing.T, done <-chan struct{}) {
	t.Helper()
	select {
	case <-done:
	case <-time.After(waitLimit):
		t.Fatalf("RunBackfill did not return within %v of its context ending", waitLimit)
	}
}

func TestRunBackfillIndexesEverythingAndSaysSo(t *testing.T) {
	s, path := seeded(t, 3000)
	defer s.Close()
	lb, log := newLog()
	RunBackfill(context.Background(), s, log)
	require.True(t, complete(t, s))
	require.Equal(t, 3000, storetest.Indexed(t, path))

	done := lb.lines(t, "info")
	require.Len(t, done, 1, lb.String())
	require.Equal(t, "search backfill done", done[0]["message"])
	require.EqualValues(t, 2, done[0]["batches"], "3,000 messages, a chat and a person in batches of %d", BackfillBatch)
	require.Contains(t, done[0], "took_ms")
	require.Empty(t, lb.warnings(t))
	require.NotContains(t, lb.String(), "seed", "counts and durations only, never text or names")

	// Once everything is in, a later start has nothing to do and says nothing.
	lb2, log2 := newLog()
	RunBackfill(context.Background(), s, log2)
	require.Empty(t, lb2.String())
}

func TestRunBackfillStopsWithItsContext(t *testing.T) {
	s, path := seeded(t, 5000)
	defer s.Close()
	lb, log := newLog()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go func() {
		defer close(done)
		runBackfill(ctx, s, log, 10, BackfillPause, BackfillRetry) // 500 batches: far from done when stopped
	}()
	waitFor(t, "the first batch", func() bool { return storetest.Indexed(t, path) > 0 })
	cancel()
	returned(t, done)

	stoppedAt := storetest.Indexed(t, path)
	require.Less(t, stoppedAt, 5000)
	require.False(t, complete(t, s))
	require.Empty(t, lb.warnings(t), "stopping is not an error, and cuts no transaction off")
	require.Empty(t, lb.lines(t, "info"), "and not done")

	// It picks up where it stopped.
	RunBackfill(context.Background(), s, log)
	require.True(t, complete(t, s))
	require.Equal(t, 5000, storetest.Indexed(t, path))
}

func TestRunBackfillRetriesAfterAnError(t *testing.T) {
	s, path := seeded(t, 5000)
	lb, log := newLog()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go func() {
		defer close(done)
		RunBackfill(ctx, s, log)
	}()
	waitFor(t, "the first batch", func() bool { return storetest.Indexed(t, path) > 0 })
	require.NoError(t, s.Close()) // closed under it
	waitFor(t, "a warning", func() bool { return len(lb.warnings(t)) > 0 })
	cancel()
	returned(t, done)

	warns := lb.warnings(t)
	require.Len(t, warns, 1, "one warning, then it waits %v before trying again: %s", BackfillRetry, lb.String())
	require.Equal(t, batchFailed, warns[0]["message"])
	require.Contains(t, warns[0], "error")
	require.Empty(t, lb.lines(t, "info"))
	require.NotContains(t, lb.String(), "seed message")

	// It does try again, rather than give up: with a short retry it keeps warning until its context ends.
	lb2, log2 := newLog()
	ctx2, cancel2 := context.WithCancel(context.Background())
	defer cancel2()
	done2 := make(chan struct{})
	go func() {
		defer close(done2)
		runBackfill(ctx2, s, log2, BackfillBatch, BackfillPause, time.Millisecond)
	}()
	waitFor(t, "three tries", func() bool { return len(lb2.warnings(t)) >= 3 })
	for _, w := range lb2.warnings(t) {
		require.Equal(t, batchFailed, w["message"])
	}
	cancel2()
	returned(t, done2)
}
