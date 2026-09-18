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
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
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

// --- the mute switch -------------------------------------------------------

func TestMutedNotifierSendsNothingAndSaysWhy(t *testing.T) {
	f := &fakeNtfy{}
	up := httptest.NewServer(f.handler())
	defer up.Close()

	n := NewNotifier(up.URL, "topic", "")
	// On by default, or every existing install goes quiet on upgrade.
	if !n.Enabled() {
		t.Fatal("a fresh notifier is muted")
	}

	n.SetEnabled(false)
	err := n.Publish(context.Background(), "agent:start", "Agent online", "atlas", "low", "computer", "")
	// The disabled error, NOT the unconfigured one: one is fixed by a tap and
	// the other by editing a plist, and the phone shows whichever it is told.
	if err != errNotifyDisabled {
		t.Fatalf("err = %v, want errNotifyDisabled", err)
	}
	if f.count() != 0 {
		t.Fatalf("muted notifier still posted %d times", f.count())
	}

	// Unmuting must not need the ntfy flags again -- the switch and the
	// configuration are separate states.
	n.SetEnabled(true)
	if err := n.Publish(context.Background(), "agent:start", "Agent online", "atlas", "low", "computer", ""); err != nil {
		t.Fatal(err)
	}
	if f.count() != 1 {
		t.Fatalf("unmuted notifier posted %d times, want 1", f.count())
	}
}

// notify is the sampler's path, and muting it must be silent. If it let the
// disabled error through to the log, a mute would cost a line of log per
// sample -- which is the noise the switch exists to remove.
func TestMutedNotifyIsSilent(t *testing.T) {
	f := &fakeNtfy{}
	up := httptest.NewServer(f.handler())
	defer up.Close()

	n := NewNotifier(up.URL, "topic", "")
	n.SetEnabled(false)
	n.notify(context.Background(), "claude:x:idle", "Claude Code finished a turn", "repo", "default", "bell", "")
	if f.count() != 0 {
		t.Fatalf("muted notify posted %d times", f.count())
	}
}

func TestStoreNotifySwitchDefaultsOnAndSurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	store := NewStore(dir)
	// No file yet. An agent that predates the switch was publishing, so the
	// absence of a file has to mean "on".
	if !store.NotifyEnabled() {
		t.Fatal("a store with no file reports muted")
	}
	if err := store.SetNotifyEnabled(false); err != nil {
		t.Fatal(err)
	}
	// A new Store over the same dir is what the next login gets.
	if NewStore(dir).NotifyEnabled() {
		t.Error("the mute did not survive a restart")
	}
	if err := store.SetNotifyEnabled(true); err != nil {
		t.Fatal(err)
	}
	if !NewStore(dir).NotifyEnabled() {
		t.Error("the unmute did not survive a restart")
	}
}

func TestNotifySettingsEndpointFlipsTheSwitchAndPersistsIt(t *testing.T) {
	f := &fakeNtfy{}
	up := httptest.NewServer(f.handler())
	defer up.Close()

	s := NewSampler(time.Second, "", "", nil, NewNotifier(up.URL, "topic", ""))
	store := NewStore(t.TempDir())
	srv := httptest.NewServer(newMux(s, store, "", ""))
	defer srv.Close()
	tok := pairedToken(t, store)

	post := func(body string) (int, map[string]any) {
		t.Helper()
		req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/notify/settings", strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tok)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var out map[string]any
		_ = json.NewDecoder(resp.Body).Decode(&out)
		return resp.StatusCode, out
	}

	code, out := post(`{"enabled":false}`)
	if code != http.StatusOK {
		t.Fatalf("got %d, want 200", code)
	}
	// It answers with the state it ended in, so the phone renders what the
	// Mac believes rather than what it just asked for.
	if out["enabled"] != false {
		t.Errorf("response enabled = %v, want false", out["enabled"])
	}
	if s.Notifier().Enabled() {
		t.Error("the running notifier was not muted")
	}
	if store.NotifyEnabled() {
		t.Error("the mute was not persisted")
	}

	// A body without the field is a 400, not a silent mute: {} and
	// {"enabled":false} are one typo apart.
	if code, _ := post(`{}`); code != http.StatusBadRequest {
		t.Errorf("empty body got %d, want 400", code)
	}

	// A test push while muted is refused rather than sent, so the button
	// cannot contradict the switch.
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/notify/test", strings.NewReader(`{}`))
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("test push while muted got %d, want 400", resp.StatusCode)
	}

	if code, out := post(`{"enabled":true}`); code != http.StatusOK || out["enabled"] != true {
		t.Errorf("unmute got %d %v", code, out)
	}
	if !store.NotifyEnabled() {
		t.Error("the unmute was not persisted")
	}
}
