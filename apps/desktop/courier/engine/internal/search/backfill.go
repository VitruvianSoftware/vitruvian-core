// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package search is Courier's search over courier.db: messages, chats and people. The index itself is the store's
// (migration 4); this package fills it in behind with what was already on disk, and answers queries over it.
package search

import (
	"context"
	"time"

	"github.com/rs/zerolog"

	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

// BackfillBatch is how many rows one backfill batch reads, in one transaction. It is small enough that a bridge's
// write waits at most tens of milliseconds for a batch to finish.
const BackfillBatch = 2000

// BackfillPause is the shortest wait between batches, so bridges' writes get the database. After a batch that took
// longer, the wait is as long as the batch took: the backfill holds the database at most about half the time.
const BackfillPause = 20 * time.Millisecond

// BackfillRetry is the wait after a batch fails (a SQLITE_BUSY after the busy timeout, say) before trying again.
const BackfillRetry = 30 * time.Second

// RunBackfill indexes, in the background, the history that was on disk when migration 4 ran: batch after batch of
// store.BackfillSearch, each followed by a rest as long as it took (at least BackfillPause), until nothing is
// left. It returns when that is done or ctx ends, finishing first the batch in flight, which commits whole; the
// next run carries on where this one stopped. A batch that fails is logged as a warning and tried again after
// BackfillRetry; it is never fatal. When it has indexed something it logs "search backfill done" with how many
// batches and how long it took, and how many messages, chats and people the index now holds: counts and
// durations only, never text or names. With nothing to do it says nothing.
func RunBackfill(ctx context.Context, s *store.Store, log zerolog.Logger) {
	runBackfill(ctx, s, log, backfillConfig{
		batch: BackfillBatch, pause: BackfillPause, retry: BackfillRetry, now: time.Now, sleep: sleep,
	})
}

// backfillConfig is RunBackfill's batch size, waits and clock; tests change them.
type backfillConfig struct {
	batch        int
	pause, retry time.Duration
	now          func() time.Time
	sleep        func(ctx context.Context, d time.Duration) bool // false if ctx ended first
}

func runBackfill(ctx context.Context, s *store.Store, log zerolog.Logger, cfg backfillConfig) {
	// A batch is never cut off: it runs to its commit, which is short (BackfillBatch rows, store.BackfillTimeBudget),
	// and ctx is looked at between batches. Cancelling the transaction instead would only roll it back, with the
	// database driver complaining at shutdown. The store's own warnings (milliseconds with no doc id left) go to log.
	batchCtx := log.WithContext(context.WithoutCancel(ctx))
	start := cfg.now()
	if complete, err := s.SearchComplete(batchCtx); err == nil && complete {
		return // every start after the first one that finished: nothing to do, nothing to say
	}
	batches := 0
	for ctx.Err() == nil {
		began := cfg.now()
		done, err := s.BackfillSearch(batchCtx, cfg.batch)
		took := cfg.now().Sub(began)
		if err != nil {
			log.Warn().Err(err).Dur("retry_in", cfg.retry).Msg("search backfill: a batch failed; trying again later")
			if !cfg.sleep(ctx, cfg.retry) {
				return
			}
			continue
		}
		batches++
		if done {
			line := log.Info().Int("batches", batches).Int64("took_ms", cfg.now().Sub(start).Milliseconds())
			if messages, chats, people, err := s.SearchCounts(batchCtx); err == nil {
				line = line.Int("messages", messages).Int("chats", chats).Int("people", people)
			}
			line.Msg("search backfill done")
			return
		}
		if !cfg.sleep(ctx, max(cfg.pause, took)) {
			return
		}
	}
}

// sleep waits d, and reports false if ctx ended first.
func sleep(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}
