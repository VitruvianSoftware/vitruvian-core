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
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

// A fake ntfy. It records what arrived, which is the only way to check the
// header shape without a real server and a real topic.
type fakeNtfy struct {
	mu     sync.Mutex
	posts  []fakePost
	status int
}

type fakePost struct {
	path    string
	body    string
	headers http.Header
}

func (f *fakeNtfy) handler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		f.mu.Lock()
		f.posts = append(f.posts, fakePost{path: r.URL.Path, body: string(b), headers: r.Header.Clone()})
		status := f.status
		f.mu.Unlock()
		if status == 0 {
			status = http.StatusOK
		}
		w.WriteHeader(status)
		_, _ = w.Write([]byte(`{"id":"x"}`))
	}
}

func (f *fakeNtfy) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.posts)
}

func (f *fakeNtfy) last() fakePost {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.posts[len(f.posts)-1]
}

func TestNotifierPublishesTheDocumentedShape(t *testing.T) {
	f := &fakeNtfy{}
	up := httptest.NewServer(f.handler())
	defer up.Close()

	n := NewNotifier(up.URL, "vitruvian-remote", "s3cr3t-token")
	err := n.Publish(context.Background(), "agent:start", "Agent online", "atlas", "low", "computer", "vitruvian-remote://mac")
	if err != nil {
		t.Fatal(err)
	}
	if f.count() != 1 {
		t.Fatalf("got %d posts", f.count())
	}
	p := f.last()
	// POST <url>/<topic>, the message in the body, everything else a header.
	if p.path != "/vitruvian-remote" {
		t.Errorf("path = %q", p.path)
	}
	if p.body != "atlas" {
		t.Errorf("body = %q", p.body)
	}
	for h, want := range map[string]string{
		"Title":         "Agent online",
		"Priority":      "low",
		"Tags":          "computer",
		"Click":         "vitruvian-remote://mac",
		"Authorization": "Bearer s3cr3t-token",
	} {
		if got := p.headers.Get(h); got != want {
			t.Errorf("%s = %q, want %q", h, got, want)
		}
	}

	// Empty optional headers are omitted, not sent blank: ntfy rejects an
	// empty Priority rather than defaulting it.
	if err := n.Publish(context.Background(), "other", "T", "B", "", "", ""); err != nil {
		t.Fatal(err)
	}
	p = f.last()
	if _, ok := p.headers["Priority"]; ok {
		t.Error("an empty Priority was sent as a header")
	}
	if _, ok := p.headers["Click"]; ok {
		t.Error("an empty Click was sent as a header")
	}
}

func TestNotifierDebouncesPerKey(t *testing.T) {
	f := &fakeNtfy{}
	up := httptest.NewServer(f.handler())
	defer up.Close()
	n := NewNotifier(up.URL, "topic", "")

	ctx := context.Background()
	// The same key three times in a row: one publish. This is the sampler
	// re-reading an unchanged transcript every five seconds.
	for i := 0; i < 3; i++ {
		if err := n.Publish(ctx, "claude:abc:permission", "Claude Code is waiting", "core · Bash", "high", "raised_hand", ""); err != nil {
			t.Fatal(err)
		}
	}
	if f.count() != 1 {
		t.Errorf("same key three times sent %d notifications, want 1", f.count())
	}

	// A DIFFERENT key is not suppressed: a PR going red in the same minute
	// as a permission prompt is separate news.
	if err := n.Publish(ctx, "pr:owner/repo#1:red", "PR #1 checks failed", "title", "high", "x", ""); err != nil {
		t.Fatal(err)
	}
	if f.count() != 2 {
		t.Errorf("a different key was suppressed: %d posts", f.count())
	}

	// Once the window has passed the same key fires again. Reaching into
	// the map is deliberate: sleeping thirty seconds in a unit test is not
	// a test, it is a delay.
	n.mu.Lock()
	n.sent["claude:abc:permission"] = time.Now().Add(-notifyDebounce - time.Second)
	n.mu.Unlock()
	if err := n.Publish(ctx, "claude:abc:permission", "Claude Code is waiting", "core · Bash", "high", "raised_hand", ""); err != nil {
		t.Fatal(err)
	}
	if f.count() != 3 {
		t.Errorf("after the window the key must fire again: %d posts", f.count())
	}
}

func TestNotifierUnconfiguredAndFailing(t *testing.T) {
	// The zero configuration is a working no-op, so every caller can stay
	// unconditional -- but a caller that ASKED (the test endpoint) gets a
	// reason naming the flags.
	n := NewNotifier("", "", "")
	if n.Configured() {
		t.Error("an empty url must not be configured")
	}
	if err := n.Publish(context.Background(), "k", "t", "b", "", "", ""); err == nil {
		t.Error("Publish on an unconfigured notifier must say so")
	}
	// A URL with no topic is also not configured: there is nowhere to post.
	if NewNotifier("https://ntfy.example", "", "").Configured() {
		t.Error("a url with no topic must not be configured")
	}

	// An ntfy that refuses: the error carries the status, and never the
	// token that was sent with it.
	f := &fakeNtfy{status: http.StatusUnauthorized}
	up := httptest.NewServer(f.handler())
	defer up.Close()
	n = NewNotifier(up.URL, "topic", "hunter2")
	err := n.Publish(context.Background(), "k", "t", "b", "", "", "")
	if err == nil {
		t.Fatal("a 401 must be an error")
	}
	if !contains(err.Error(), "401") {
		t.Errorf("error should carry the status: %v", err)
	}
	if contains(err.Error(), "hunter2") {
		t.Errorf("the token leaked into an error: %v", err)
	}
}
