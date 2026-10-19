// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package main

import (
	"encoding/json"
	"sort"
	"strings"
	"sync"
	"time"
)

// Event is one normalised webhook, as it goes over the wire.
type Event struct {
	ID      int64           `json:"id"`
	Repo    string          `json:"repo"`
	Kind    string          `json:"kind"`
	Payload json.RawMessage `json:"payload"`

	at time.Time // when the relay received it; drives the age-out
}

// repoKey is how repositories are matched: GitHub names are case-insensitive.
func repoKey(fullName string) string { return strings.ToLower(fullName) }

type repoBuffer struct {
	events []Event
	// evictedUpTo is the highest id ever dropped from this buffer. A client
	// whose Last-Event-ID is below it has missed events and must resync.
	evictedUpTo int64
}

// subscriber is one open /events stream. The hub never blocks on it: if its
// channel is full the stream is closed and the client reconnects with
// Last-Event-ID, which replays what it missed.
type subscriber struct {
	ch      chan Event
	dropped bool
}

// Hub owns the per-repository ring buffers and the set of open streams.
// Single replica, in memory, by design: a restart loses both, and clients
// recover by re-PUTting their watchlist and re-snapshotting on resync.
type Hub struct {
	mu     sync.Mutex
	clock  Clock
	window time.Duration
	max    int

	// floor is the first id this process hands out. Ids are seeded from the
	// start time so an id from a previous incarnation is always below it,
	// and a reconnecting client is told to resync instead of being silently
	// replayed a partial history.
	floor  int64
	nextID int64
	repos  map[string]*repoBuffer
	subs   map[*subscriber]struct{}
}

// NewHub starts ids at start-time-in-ms * 1000.
func NewHub(clock Clock, window time.Duration, max int) *Hub {
	floor := clock.Now().UnixMilli() * 1000
	if floor < 1 {
		floor = 1
	}
	return &Hub{
		clock: clock, window: window, max: max,
		floor: floor, nextID: floor,
		repos: map[string]*repoBuffer{},
		subs:  map[*subscriber]struct{}{},
	}
}

// Publish assigns the next id, buffers the event and fans it out. It returns
// the stored event and how many streams it was offered to.
func (h *Hub) Publish(repo, kind string, payload json.RawMessage) (Event, int) {
	h.mu.Lock()
	defer h.mu.Unlock()
	now := h.clock.Now()
	ev := Event{ID: h.nextID, Repo: repo, Kind: kind, Payload: payload, at: now}
	h.nextID++
	key := repoKey(repo)
	b := h.repos[key]
	if b == nil {
		b = &repoBuffer{}
		h.repos[key] = b
	}
	b.events = append(b.events, ev)
	h.trimLocked(b, now)
	n := 0
	for s := range h.subs {
		select {
		case s.ch <- ev:
			n++
		default:
			s.dropped = true
			close(s.ch)
			delete(h.subs, s)
		}
	}
	return ev, n
}

func (h *Hub) trimLocked(b *repoBuffer, now time.Time) {
	cut := 0
	for cut < len(b.events) && (now.Sub(b.events[cut].at) > h.window || len(b.events)-cut > h.max) {
		b.evictedUpTo = b.events[cut].ID
		cut++
	}
	if cut > 0 {
		b.events = append([]Event(nil), b.events[cut:]...)
	}
}

// SubscribeResult is what a new stream starts from.
type SubscribeResult struct {
	Sub *subscriber
	// Replay holds buffered events after lastID for the given repositories,
	// in id order. Empty when Resync is set.
	Replay []Event
	// Resync means the client's lastID is older than the buffer (or from a
	// previous relay process): it must re-snapshot.
	Resync bool
	// Position is the newest id at subscribe time. The stream sends it on
	// its hello (or resync) event, so a client that saw no events still
	// reconnects with a Last-Event-ID and gets replayed what it missed.
	Position int64
}

// Subscribe registers a stream and computes its replay atomically, so no
// event can fall between the replay and the live feed. lastID 0 means a
// fresh connection: no replay, no resync. inScope picks the repositories
// (by repoKey) whose history matters to this client.
func (h *Hub) Subscribe(lastID int64, buf int, inScope func(key string) bool) SubscribeResult {
	h.mu.Lock()
	defer h.mu.Unlock()
	s := &subscriber{ch: make(chan Event, buf)}
	h.subs[s] = struct{}{}
	newest := h.nextID - 1
	res := SubscribeResult{Sub: s, Position: newest}
	if lastID <= 0 {
		return res
	}
	if lastID < h.floor-1 || lastID > newest {
		res.Resync = true
		return res
	}
	now := h.clock.Now()
	for key, b := range h.repos {
		if !inScope(key) {
			continue
		}
		h.trimLocked(b, now)
		if b.evictedUpTo > lastID {
			res.Resync, res.Replay = true, nil
			return res
		}
		for _, ev := range b.events {
			if ev.ID > lastID {
				res.Replay = append(res.Replay, ev)
			}
		}
	}
	sort.Slice(res.Replay, func(i, j int) bool { return res.Replay[i].ID < res.Replay[j].ID })
	return res
}

// Unsubscribe removes a stream; safe to call after the hub dropped it.
func (h *Hub) Unsubscribe(s *subscriber) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.subs[s]; ok {
		delete(h.subs, s)
		close(s.ch)
	}
}

// Subscribers is the number of open streams.
func (h *Hub) Subscribers() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.subs)
}

// Dropped reports whether the hub closed s for being too slow.
func (h *Hub) Dropped(s *subscriber) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return s.dropped
}
