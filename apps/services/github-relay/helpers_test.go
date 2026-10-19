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
	"bufio"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// ---- fake clock ----------------------------------------------------------

type fakeClock struct {
	mu      sync.Mutex
	now     time.Time
	tickers []*fakeTicker
	made    chan *fakeTicker
}

func newFakeClock() *fakeClock {
	return &fakeClock{now: time.Date(2026, 10, 7, 12, 0, 0, 0, time.UTC), made: make(chan *fakeTicker, 16)}
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
}

func (c *fakeClock) NewTicker(d time.Duration) Ticker {
	t := &fakeTicker{d: d, ch: make(chan time.Time, 1)}
	c.mu.Lock()
	c.tickers = append(c.tickers, t)
	c.mu.Unlock()
	c.made <- t
	return t
}

type fakeTicker struct {
	d       time.Duration
	ch      chan time.Time
	stopped bool
}

func (t *fakeTicker) C() <-chan time.Time { return t.ch }
func (t *fakeTicker) Stop()               { t.stopped = true }
func (t *fakeTicker) Tick()               { t.ch <- time.Time{} }

// ---- fake GitHub ---------------------------------------------------------

type fakeGitHub struct {
	*httptest.Server
	mu        sync.Mutex
	users     map[string]GitHubUser      // token -> user
	readable  map[string]map[string]bool // token -> repo key -> readable
	calls     map[string]int             // "GET /user" etc.
	exchange  func(form map[string]string) (int, string)
	revokes   []string // access tokens revoked
	revokeHdr string
}

func newFakeGitHub(t *testing.T) *fakeGitHub {
	f := &fakeGitHub{
		users:    map[string]GitHubUser{},
		readable: map[string]map[string]bool{},
		calls:    map[string]int{},
	}
	mux := http.NewServeMux()
	auth := func(r *http.Request) string { return strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ") }
	mux.HandleFunc("GET /user", func(w http.ResponseWriter, r *http.Request) {
		f.count("GET /user")
		f.mu.Lock()
		u, ok := f.users[auth(r)]
		f.mu.Unlock()
		if !ok {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_ = json.NewEncoder(w).Encode(u)
	})
	mux.HandleFunc("GET /repos/{owner}/{name}", func(w http.ResponseWriter, r *http.Request) {
		f.count("GET /repos")
		f.mu.Lock()
		ok := f.readable[auth(r)][repoKey(r.PathValue("owner")+"/"+r.PathValue("name"))]
		f.mu.Unlock()
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_, _ = io.WriteString(w, `{"full_name":"x"}`)
	})
	mux.HandleFunc("POST /login/oauth/access_token", func(w http.ResponseWriter, r *http.Request) {
		f.count("POST /login/oauth/access_token")
		_ = r.ParseForm()
		form := map[string]string{}
		for k := range r.PostForm {
			form[k] = r.PostForm.Get(k)
		}
		code, body := http.StatusOK, `{"access_token":"gho_new","token_type":"bearer","scope":""}`
		if f.exchange != nil {
			code, body = f.exchange(form)
		}
		w.WriteHeader(code)
		_, _ = io.WriteString(w, body)
	})
	mux.HandleFunc("DELETE /applications/{id}/token", func(w http.ResponseWriter, r *http.Request) {
		f.count("DELETE /applications/token")
		var b struct {
			AccessToken string `json:"access_token"`
		}
		_ = json.NewDecoder(r.Body).Decode(&b)
		f.mu.Lock()
		f.revokes = append(f.revokes, b.AccessToken)
		f.revokeHdr = r.Header.Get("Authorization")
		f.mu.Unlock()
		w.WriteHeader(http.StatusNoContent)
	})
	f.Server = httptest.NewServer(mux)
	t.Cleanup(f.Close)
	return f
}

func (f *fakeGitHub) count(k string) {
	f.mu.Lock()
	f.calls[k]++
	f.mu.Unlock()
}

func (f *fakeGitHub) Calls(k string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls[k]
}

func (f *fakeGitHub) addUser(token string, id int64, login string, repos ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.users[token] = GitHubUser{ID: id, Login: login}
	f.readable[token] = map[string]bool{}
	for _, r := range repos {
		f.readable[token][repoKey(r)] = true
	}
}

// ---- relay under test ----------------------------------------------------

const testSecret = "test-webhook-secret"

type relay struct {
	t     *testing.T
	srv   *Server
	http  *httptest.Server
	clock *fakeClock
	gh    *fakeGitHub
}

func newRelay(t *testing.T, mutate ...func(*Config)) *relay {
	t.Helper()
	gh := newFakeGitHub(t)
	cfg, err := LoadConfig(func(k string) string {
		return map[string]string{
			"GITHUB_WEBHOOK_SECRET": testSecret,
			"GITHUB_CLIENT_ID":      "Iv1.testclient",
			"GITHUB_CLIENT_SECRET":  "client-secret",
			"GITHUB_API_URL":        gh.URL,
			"GITHUB_WEB_URL":        gh.URL,
		}[k]
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range mutate {
		m(&cfg)
	}
	clock := newFakeClock()
	s := NewServer(cfg, clock, gh.Client(), slog.New(slog.NewTextHandler(io.Discard, nil)))
	hs := httptest.NewServer(s.Handler())
	t.Cleanup(hs.Close)
	return &relay{t: t, srv: s, http: hs, clock: clock, gh: gh}
}

func sign(secret, body string) string {
	m := hmac.New(sha256.New, []byte(secret))
	m.Write([]byte(body))
	return "sha256=" + hex.EncodeToString(m.Sum(nil))
}

// webhook posts a signed delivery and returns the status code.
func (r *relay) webhook(kind, body string) int {
	r.t.Helper()
	req, _ := http.NewRequest(http.MethodPost, r.http.URL+"/webhook", strings.NewReader(body))
	req.Header.Set("X-GitHub-Event", kind)
	req.Header.Set("X-Hub-Signature-256", sign(testSecret, body))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		r.t.Fatal(err)
	}
	resp.Body.Close()
	return resp.StatusCode
}

func pushBody(repo, after string) string {
	return `{"ref":"refs/heads/main","after":"` + after + `","repository":{"full_name":"` + repo + `","default_branch":"main"}}`
}

func (r *relay) subscribe(token string, repos ...string) subscriptionResponse {
	r.t.Helper()
	b, _ := json.Marshal(subscriptionRequest{Repositories: repos})
	req, _ := http.NewRequest(http.MethodPut, r.http.URL+"/subscriptions", strings.NewReader(string(b)))
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		r.t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		r.t.Fatalf("PUT /subscriptions: HTTP %d", resp.StatusCode)
	}
	var out subscriptionResponse
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return out
}

// sseFrame is one parsed SSE block: an event or a comment.
type sseFrame struct {
	ID, Event, Data, Comment string
}

type stream struct {
	t      *testing.T
	status int
	frames chan sseFrame
	cancel context.CancelFunc
	ticker *fakeTicker
}

// openStream connects to /events and parses frames in the background.
func (r *relay) openStream(token, lastID string) *stream {
	r.t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, r.http.URL+"/events", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	if lastID != "" {
		req.Header.Set("Last-Event-ID", lastID)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		cancel()
		r.t.Fatal(err)
	}
	s := &stream{t: r.t, status: resp.StatusCode, frames: make(chan sseFrame, 64), cancel: cancel}
	r.t.Cleanup(func() { cancel(); resp.Body.Close() })
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return s
	}
	go func() {
		defer close(s.frames)
		sc := bufio.NewScanner(resp.Body)
		var f sseFrame
		for sc.Scan() {
			line := sc.Text()
			switch {
			case line == "":
				s.frames <- f
				f = sseFrame{}
			case strings.HasPrefix(line, ": "):
				f.Comment = strings.TrimPrefix(line, ": ")
			case strings.HasPrefix(line, "id: "):
				f.ID = strings.TrimPrefix(line, "id: ")
			case strings.HasPrefix(line, "event: "):
				f.Event = strings.TrimPrefix(line, "event: ")
			case strings.HasPrefix(line, "data: "):
				f.Data = strings.TrimPrefix(line, "data: ")
			}
		}
	}()
	// The handler creates its ping ticker once the opening frames are out.
	select {
	case s.ticker = <-r.clock.made:
	case <-time.After(5 * time.Second):
		r.t.Fatal("stream never started its ping ticker")
	}
	return s
}

func (s *stream) next() sseFrame {
	s.t.Helper()
	select {
	case f, ok := <-s.frames:
		if !ok {
			s.t.Fatal("stream closed")
		}
		return f
	case <-time.After(5 * time.Second):
		s.t.Fatal("timed out waiting for an SSE frame")
	}
	return sseFrame{}
}

// expectNone asserts no frame arrives within a short window.
func (s *stream) expectNone() {
	s.t.Helper()
	select {
	case f, ok := <-s.frames:
		if ok {
			s.t.Fatalf("unexpected frame: %+v", f)
		}
	case <-time.After(150 * time.Millisecond):
	}
}

func decodeEvent(t *testing.T, f sseFrame) Event {
	t.Helper()
	var ev Event
	if err := json.Unmarshal([]byte(f.Data), &ev); err != nil {
		t.Fatalf("data is not an event: %q: %v", f.Data, err)
	}
	return ev
}
