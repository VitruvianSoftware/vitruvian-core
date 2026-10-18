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

// BackfillPause is the wait between batches, so bridges' writes get the database.
const BackfillPause = 20 * time.Millisecond

// BackfillRetry is the wait after a batch fails (a SQLITE_BUSY after the busy timeout, say) before trying again.
const BackfillRetry = 30 * time.Second

// RunBackfill indexes, in the background, the history that was on disk when migration 4 ran: batch after batch of
// store.BackfillSearch, with BackfillPause between them, until nothing is left. It returns when that is done or ctx
// ends, finishing first the batch in flight, which commits whole; the next run carries on where this one stopped.
// A batch that fails is logged as a warning and tried again after BackfillRetry; it is never fatal. When it has
// indexed something it logs "search backfill done" with how many batches and how long it took: counts and
// durations only, never text or names. With nothing to do it says nothing.
func RunBackfill(ctx context.Context, s *store.Store, log zerolog.Logger) {
	runBackfill(ctx, s, log, BackfillBatch, BackfillPause, BackfillRetry)
}

func runBackfill(ctx context.Context, s *store.Store, log zerolog.Logger, batch int, pause, retry time.Duration) {
	// A batch is never cut off: it runs to its commit, which is short (BackfillBatch), and ctx is looked at
	// between batches. Cancelling the transaction instead would only roll it back, with the database driver
	// complaining at shutdown. The store's own warnings (a millisecond with no doc id left) go to log.
	batchCtx := log.WithContext(context.WithoutCancel(ctx))
	start := time.Now()
	if complete, err := s.SearchComplete(batchCtx); err == nil && complete {
		return // every start after the first one that finished: nothing to do, nothing to say
	}
	batches := 0
	for ctx.Err() == nil {
		done, err := s.BackfillSearch(batchCtx, batch)
		if err != nil {
			log.Warn().Err(err).Dur("retry_in", retry).Msg("search backfill: a batch failed; trying again later")
			if !sleep(ctx, retry) {
				return
			}
			continue
		}
		batches++
		if done {
			log.Info().Int("batches", batches).Int64("took_ms", time.Since(start).Milliseconds()).
				Msg("search backfill done")
			return
		}
		if !sleep(ctx, pause) {
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
