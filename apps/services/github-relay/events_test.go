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
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestFreshStreamSaysHelloWithItsPosition(t *testing.T) {
	r := newRelay(t)
	r.gh.addUser("tok", 1, "james", "o/r")
	r.subscribe("tok", "o/r")
	r.webhook("push", pushBody("o/r", "a1"))

	s := r.openStream("tok", "")
	hello := s.next()
	if hello.Event != "hello" || hello.ID != strconv.FormatInt(r.srv.hub.floor, 10) {
		t.Fatalf("first frame = %+v, want hello at id %d", hello, r.srv.hub.floor)
	}
	s.expectNone() // a fresh connect replays nothing: the client snapshots
}

func TestFanOutToEverySubscribedStream(t *testing.T) {
	r := newRelay(t)
	r.gh.addUser("tok-a", 1, "alice", "o/r")
	r.gh.addUser("tok-b", 2, "bob", "o/r")
	r.gh.addUser("tok-c", 3, "carol", "o/r", "o/other")
	r.subscribe("tok-a", "o/r")
	r.subscribe("tok-b", "O/R") // case-insensitive, as GitHub is
	r.subscribe("tok-c", "o/other")

	a, b, c := r.openStream("tok-a", ""), r.openStream("tok-b", ""), r.openStream("tok-c", "")
	for _, s := range []*stream{a, b, c} {
		s.next() // hello
	}
	r.webhook("check_run", `{"action":"completed","check_run":{"name":"build","status":"completed","conclusion":"success","head_sha":"abc","html_url":"https://x"},"repository":{"full_name":"o/r"}}`)

	for name, s := range map[string]*stream{"alice": a, "bob": b} {
		f := s.next()
		ev := decodeEvent(t, f)
		if f.Event != "check_run" || ev.Repo != "o/r" || ev.Kind != "check_run" || f.ID != strconv.FormatInt(ev.ID, 10) {
			t.Errorf("%s got %+v / %+v", name, f, ev)
		}
	}
	c.expectNone() // carol watches o/other only
	if got := r.srv.metrics.Get(mEventsSent, ""); got != 2 {
		t.Errorf("events sent = %v, want 2", got)
	}
	if got := r.srv.hub.Subscribers(); got != 3 {
		t.Errorf("subscribers = %d, want 3", got)
	}
}

func TestSubscriptionsAreFilteredToReadableRepositories(t *testing.T) {
	r := newRelay(t)
	r.gh.addUser("tok", 1, "james", "o/public")
	got := r.subscribe("tok", "o/public", "o/secret")
	if len(got.Repositories) != 1 || got.Repositories[0] != "o/public" || len(got.Dropped) != 1 || got.Dropped[0] != "o/secret" {
		t.Fatalf("PUT /subscriptions = %+v", got)
	}

	s := r.openStream("tok", "")
	s.next() // hello
	r.webhook("push", pushBody("o/secret", "s1"))
	s.expectNone()
	r.webhook("push", pushBody("o/public", "p1"))
	if ev := decodeEvent(t, s.next()); ev.Repo != "o/public" {
		t.Fatalf("got event for %s", ev.Repo)
	}

	// Access checks are cached for 10 minutes: re-PUTting does not re-ask.
	before := r.gh.Calls("GET /repos")
	r.subscribe("tok", "o/public", "o/secret")
	if after := r.gh.Calls("GET /repos"); after != before {
		t.Errorf("cached access re-checked: %d -> %d calls", before, after)
	}
	r.clock.Advance(11 * time.Minute)
	r.subscribe("tok", "o/public", "o/secret")
	if after := r.gh.Calls("GET /repos"); after != before+2 {
		t.Errorf("expired access not re-checked: %d -> %d calls", before, after)
	}
}

// A repository the token lost access to stops streaming even though the
// stored subscription still names it.
func TestStreamRechecksAccess(t *testing.T) {
	r := newRelay(t)
	r.gh.addUser("tok", 1, "james", "o/r")
	r.subscribe("tok", "o/r")
	s := r.openStream("tok", "")
	s.next()
	r.gh.mu.Lock()
	r.gh.readable["tok"]["o/r"] = false
	r.gh.mu.Unlock()
	r.clock.Advance(11 * time.Minute) // let the cached "readable" expire
	r.webhook("push", pushBody("o/r", "a"))
	s.expectNone()
}

func TestEventsAuth(t *testing.T) {
	r := newRelay(t)
	r.gh.addUser("tok", 1, "james")
	if s := r.openStreamNoWait("", ""); s != http.StatusUnauthorized {
		t.Errorf("no token: HTTP %d, want 401", s)
	}
	if s := r.openStreamNoWait("revoked", ""); s != http.StatusUnauthorized {
		t.Errorf("token GitHub rejects: HTTP %d, want 401", s)
	}
	if s := r.openStreamNoWait("tok", "abc"); s != http.StatusBadRequest {
		t.Errorf("non-numeric Last-Event-ID: HTTP %d, want 400", s)
	}
	// GET /user is cached by token hash.
	r.subscribe("tok")
	r.subscribe("tok")
	if n := r.gh.Calls("GET /user"); n != 2 { // the 400 above + the first PUT
		t.Errorf("GET /user called %d times, want 2 (cached after the first success)", n)
	}
}

// openStreamNoWait returns the status of a /events request that is expected
// to be refused before streaming.
func (r *relay) openStreamNoWait(token, lastID string) int {
	req, _ := http.NewRequest(http.MethodGet, r.http.URL+"/events", nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if lastID != "" {
		req.Header.Set("Last-Event-ID", lastID)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		r.t.Fatal(err)
	}
	resp.Body.Close()
	return resp.StatusCode
}

func TestReplayFromLastEventID(t *testing.T) {
	r := newRelay(t)
	r.gh.addUser("tok", 1, "james", "o/r", "o/x")
	r.subscribe("tok", "o/r")
	r.webhook("push", pushBody("o/r", "one"))
	r.webhook("push", pushBody("o/x", "not-watched"))
	r.webhook("push", pushBody("o/r", "two"))
	r.webhook("push", pushBody("o/r", "three"))
	first := r.srv.hub.floor

	s := r.openStream("tok", strconv.FormatInt(first, 10))
	var afters []string
	for range 2 {
		ev := decodeEvent(t, s.next())
		afters = append(afters, string(ev.Payload))
	}
	if want := []string{`"after":"two"`, `"after":"three"`}; !contains(afters[0], want[0]) || !contains(afters[1], want[1]) {
		t.Fatalf("replayed %v, want two then three", afters)
	}
	hello := s.next()
	if hello.Event != "hello" || hello.ID != strconv.FormatInt(first+3, 10) {
		t.Fatalf("after replay got %+v, want hello at %d", hello, first+3)
	}
	if r.srv.metrics.Get(mReplays, "") != 1 || r.srv.metrics.Get(mReplayedEvents, "") != 2 {
		t.Errorf("replay metrics: %v replays, %v events", r.srv.metrics.Get(mReplays, ""), r.srv.metrics.Get(mReplayedEvents, ""))
	}
}

func TestResyncWhenLastEventIDIsOlderThanTheBuffer(t *testing.T) {
	r := newRelay(t)
	r.gh.addUser("tok", 1, "james", "o/r")
	r.subscribe("tok", "o/r")
	r.webhook("push", pushBody("o/r", "old"))
	old := r.srv.hub.floor
	r.webhook("push", pushBody("o/r", "older-than-15m"))
	r.clock.Advance(16 * time.Minute)
	r.webhook("push", pushBody("o/r", "new")) // evicts the first two

	s := r.openStream("tok", strconv.FormatInt(old, 10))
	f := s.next()
	if f.Event != "resync" || f.ID != strconv.FormatInt(old+2, 10) {
		t.Fatalf("got %+v, want resync carrying the current id %d", f, old+2)
	}
	s.expectNone() // no partial replay after a resync
	if r.srv.metrics.Get(mResyncs, "") != 1 {
		t.Error("resync not counted")
	}
}

func TestResyncWhenBufferOverflowsItsCount(t *testing.T) {
	r := newRelay(t, func(c *Config) { c.BufferMaxCount = 2 })
	r.gh.addUser("tok", 1, "james", "o/r")
	r.subscribe("tok", "o/r")
	for _, a := range []string{"1", "2", "3"} {
		r.webhook("push", pushBody("o/r", a))
	}
	if s := r.openStream("tok", strconv.FormatInt(r.srv.hub.floor, 10)); s.next().Event == "resync" {
		t.Fatal("id 1 is still the predecessor of the oldest kept event (2): replay, not resync")
	}
	r.webhook("push", pushBody("o/r", "4")) // now 2 is evicted too
	if f := r.openStream("tok", strconv.FormatInt(r.srv.hub.floor, 10)).next(); f.Event != "resync" {
		t.Fatalf("got %+v, want resync", f)
	}
}

// An id from a previous relay process (lower than this process's floor) or
// from nowhere (higher than anything issued) cannot be replayed.
func TestResyncAfterRelayRestart(t *testing.T) {
	r := newRelay(t)
	r.gh.addUser("tok", 1, "james", "o/r")
	r.subscribe("tok", "o/r")
	for _, id := range []int64{r.srv.hub.floor - 500, r.srv.hub.floor + 10} {
		if f := r.openStream("tok", strconv.FormatInt(id, 10)).next(); f.Event != "resync" {
			t.Errorf("Last-Event-ID %d: got %+v, want resync", id, f)
		}
	}
}

func TestPingEvery25Seconds(t *testing.T) {
	r := newRelay(t)
	r.gh.addUser("tok", 1, "james", "o/r")
	s := r.openStream("tok", "")
	s.next() // hello
	if s.ticker.d != 25*time.Second {
		t.Fatalf("ping ticker period = %v, want 25s (Cloudflare closes idle streams at 100s)", s.ticker.d)
	}
	s.expectNone()
	for range 3 {
		s.ticker.Tick()
		if f := s.next(); f.Comment != "ping" || f.Event != "" || f.Data != "" {
			t.Fatalf("tick wrote %+v, want a ': ping' comment", f)
		}
	}
	s.cancel()
	deadline := time.Now().Add(2 * time.Second)
	for !s.ticker.stopped && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if !s.ticker.stopped {
		t.Error("ticker not stopped after the client went away")
	}
}

// A client that stops reading is dropped rather than stalling the webhook.
func TestSlowStreamIsDroppedNotBlocking(t *testing.T) {
	r := newRelay(t)
	res := r.srv.hub.Subscribe(0, 1, func(string) bool { return true })
	r.srv.hub.Publish("o/r", "push", []byte(`{}`))
	done := make(chan struct{})
	go func() { r.srv.hub.Publish("o/r", "push", []byte(`{}`)); close(done) }()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Publish blocked on a full stream")
	}
	if !r.srv.hub.Dropped(res.Sub) || r.srv.hub.Subscribers() != 0 {
		t.Fatal("full stream was not dropped")
	}
}

func contains(s, sub string) bool { return strings.Contains(s, sub) }

