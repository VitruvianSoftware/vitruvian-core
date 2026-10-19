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
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
)

const (
	maxWebhookBody   = 25 << 20 // GitHub caps payloads at 25 MB
	maxSmallBody     = 64 << 10
	maxWatchlist     = 200
	streamBuffer     = 256
	repoCheckWorkers = 8
)

var repoNameRE = regexp.MustCompile(`^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9._-]{1,100}$`)

// Server is the relay. Construct with NewServer; Handler() is its routes.
type Server struct {
	cfg     Config
	clock   Clock
	hub     *Hub
	gh      *GitHub
	metrics *Metrics
	log     *slog.Logger

	users  *ttlCache[GitHubUser] // token hash -> user
	access *ttlCache[bool]       // token hash + "|" + repo key -> readable

	subMu sync.RWMutex
	subs  map[int64]map[string]bool // user id -> repo keys
}

// NewServer wires a relay. httpClient may be nil (a 10 s-timeout client).
func NewServer(cfg Config, clock Clock, httpClient *http.Client, log *slog.Logger) *Server {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: defaultGitHubTimeout}
	}
	s := &Server{cfg: cfg, clock: clock, log: log, subs: map[int64]map[string]bool{}}
	s.hub = NewHub(clock, cfg.BufferWindow, cfg.BufferMaxCount)
	s.metrics = NewMetrics(func() float64 { return float64(s.hub.Subscribers()) })
	s.gh = &GitHub{
		APIURL: cfg.GitHubAPIURL, WebURL: cfg.GitHubWebURL,
		ClientID: cfg.ClientID, ClientSecret: cfg.ClientSecret,
		HTTP: httpClient, Metrics: s.metrics,
	}
	s.users = newTTLCache[GitHubUser](clock, cfg.CacheTTL)
	s.access = newTTLCache[bool](clock, cfg.CacheTTL)
	return s
}

// Handler returns the relay's routes. Only the first four are public (the
// HTTPRoute exposes nothing else); /healthz and /metrics stay in-cluster.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /webhook", s.handleWebhook)
	mux.HandleFunc("GET /events", s.handleEvents)
	mux.HandleFunc("PUT /subscriptions", s.handleSubscriptions)
	mux.HandleFunc("POST /auth/exchange", s.handleExchange)
	mux.HandleFunc("POST /auth/revoke", s.handleRevoke)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = io.WriteString(w, "ok\n")
	})
	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		s.metrics.Render(w)
	})
	return mux
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, reason string) {
	writeJSON(w, code, map[string]string{"error": reason})
}

// ---- POST /webhook -------------------------------------------------------

// validSignature checks X-Hub-Signature-256 ("sha256=<hex>") in constant time.
func validSignature(secret, body []byte, header string) bool {
	hexSig, ok := strings.CutPrefix(header, "sha256=")
	if !ok {
		return false
	}
	got, err := hex.DecodeString(hexSig)
	if err != nil || len(got) != sha256.Size {
		return false
	}
	mac := hmac.New(sha256.New, secret)
	mac.Write(body)
	return hmac.Equal(got, mac.Sum(nil))
}

func (s *Server) handleWebhook(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxWebhookBody))
	if err != nil {
		s.metrics.Inc(mWebhookRejected, "too_large")
		writeErr(w, http.StatusRequestEntityTooLarge, "body too large")
		return
	}
	sig := r.Header.Get("X-Hub-Signature-256")
	if sig == "" {
		s.metrics.Inc(mWebhookRejected, "missing_signature")
		writeErr(w, http.StatusBadRequest, "missing X-Hub-Signature-256")
		return
	}
	if !validSignature(s.cfg.WebhookSecret, body, sig) {
		s.metrics.Inc(mWebhookRejected, "bad_signature")
		writeErr(w, http.StatusBadRequest, "bad signature")
		return
	}
	kind := r.Header.Get("X-GitHub-Event")
	delivery := r.Header.Get("X-GitHub-Delivery")
	if kind == "ping" {
		s.metrics.Inc(mWebhookEvents, "ping")
		writeJSON(w, http.StatusOK, map[string]string{"status": "pong"})
		return
	}
	if !supportedKinds[kind] {
		// Signed but not one we relay (the App may be subscribed to more
		// than we use). 202 so GitHub does not flag the delivery as failed.
		s.metrics.Inc(mWebhookEvents, "ignored")
		writeJSON(w, http.StatusAccepted, map[string]string{"status": "ignored"})
		return
	}
	repo, payload, err := Normalize(kind, body)
	if err != nil {
		s.metrics.Inc(mWebhookRejected, "bad_payload")
		s.log.Warn("webhook payload rejected", "kind", kind, "delivery", delivery, "err", err)
		writeErr(w, http.StatusBadRequest, "unreadable payload")
		return
	}
	ev, fanout := s.hub.Publish(repo, kind, payload)
	s.metrics.Inc(mWebhookEvents, kind)
	s.log.Info("webhook", "kind", kind, "repo", repo, "id", ev.ID, "delivery", delivery, "streams", fanout)
	writeJSON(w, http.StatusOK, map[string]any{"status": "accepted", "id": ev.ID})
}

// ---- auth helpers --------------------------------------------------------

func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) > 7 && strings.EqualFold(h[:7], "bearer ") {
		return strings.TrimSpace(h[7:])
	}
	return ""
}

// authenticate resolves the bearer token to a user, cached by token hash.
// It writes the error response itself and returns ok=false on failure.
func (s *Server) authenticate(w http.ResponseWriter, r *http.Request) (string, GitHubUser, bool) {
	token := bearer(r)
	if token == "" {
		w.Header().Set("WWW-Authenticate", `Bearer realm="github-relay"`)
		writeErr(w, http.StatusUnauthorized, "missing bearer token")
		return "", GitHubUser{}, false
	}
	th := tokenHash(token)
	if u, ok := s.users.Get(th); ok {
		return token, u, true
	}
	u, err := s.gh.User(r.Context(), token)
	switch {
	case errors.Is(err, ErrUnauthorized):
		s.forget(th)
		writeErr(w, http.StatusUnauthorized, "github rejected the token")
		return "", GitHubUser{}, false
	case err != nil:
		s.log.Warn("GET /user failed", "err", err)
		writeErr(w, http.StatusBadGateway, "could not reach github")
		return "", GitHubUser{}, false
	}
	s.users.Put(th, u)
	return token, u, true
}

func (s *Server) forget(th string) {
	s.users.DeletePrefix(th)
	s.access.DeletePrefix(th + "|")
}

// canRead is the cached GET /repos/{owner}/{repo} check.
func (s *Server) canRead(ctx context.Context, token, repo string) (bool, error) {
	k := tokenHash(token) + "|" + repoKey(repo)
	if v, ok := s.access.Get(k); ok {
		return v, nil
	}
	ok, err := s.gh.CanRead(ctx, token, repo)
	if err != nil {
		return false, err
	}
	s.access.Put(k, ok)
	return ok, nil
}

// ---- PUT /subscriptions --------------------------------------------------

type subscriptionRequest struct {
	Repositories []string `json:"repositories"`
}

type subscriptionResponse struct {
	Repositories []string `json:"repositories"` // what the stream will carry
	Dropped      []string `json:"dropped"`      // not readable with this token
}

func (s *Server) handleSubscriptions(w http.ResponseWriter, r *http.Request) {
	token, user, ok := s.authenticate(w, r)
	if !ok {
		return
	}
	var req subscriptionRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxSmallBody))
	if err := dec.Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "body must be {\"repositories\": [\"owner/name\", ...]}")
		return
	}
	if len(req.Repositories) > maxWatchlist {
		writeErr(w, http.StatusBadRequest, fmt.Sprintf("at most %d repositories", maxWatchlist))
		return
	}
	seen := map[string]bool{}
	var want []string
	for _, repo := range req.Repositories {
		if !repoNameRE.MatchString(repo) {
			writeErr(w, http.StatusBadRequest, "not an owner/name repository: "+strconv.Quote(repo))
			return
		}
		if !seen[repoKey(repo)] {
			seen[repoKey(repo)] = true
			want = append(want, repo)
		}
	}

	readable := make([]bool, len(want))
	errs := make([]error, len(want))
	var wg sync.WaitGroup
	sem := make(chan struct{}, repoCheckWorkers)
	for i, repo := range want {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()
			readable[i], errs[i] = s.canRead(r.Context(), token, repo)
		}()
	}
	wg.Wait()

	resp := subscriptionResponse{Repositories: []string{}, Dropped: []string{}}
	keys := map[string]bool{}
	for i, repo := range want {
		switch {
		case errors.Is(errs[i], ErrUnauthorized):
			s.forget(tokenHash(token))
			writeErr(w, http.StatusUnauthorized, "github rejected the token")
			return
		case errs[i] != nil:
			s.log.Warn("repository access check failed", "repo", repo, "err", errs[i])
			writeErr(w, http.StatusBadGateway, "could not check access to "+repo+"; retry")
			return
		case readable[i]:
			resp.Repositories = append(resp.Repositories, repo)
			keys[repoKey(repo)] = true
		default:
			resp.Dropped = append(resp.Dropped, repo)
		}
	}
	s.subMu.Lock()
	s.subs[user.ID] = keys
	s.subMu.Unlock()
	s.log.Info("subscription set", "user", user.Login, "repos", len(resp.Repositories), "dropped", len(resp.Dropped))
	writeJSON(w, http.StatusOK, resp)
}

func (s *Server) subscribed(userID int64, key string) bool {
	s.subMu.RLock()
	defer s.subMu.RUnlock()
	return s.subs[userID][key]
}

// ---- GET /events ---------------------------------------------------------

// sseWriter writes Server-Sent Events and flushes after each one.
type sseWriter struct {
	w  io.Writer
	rc *http.ResponseController
}

func (e sseWriter) event(id int64, kind string, data []byte) error {
	if _, err := fmt.Fprintf(e.w, "id: %d\nevent: %s\ndata: %s\n\n", id, kind, data); err != nil {
		return err
	}
	return e.rc.Flush()
}

func (e sseWriter) comment(text string) error {
	if _, err := fmt.Fprintf(e.w, ": %s\n\n", text); err != nil {
		return err
	}
	return e.rc.Flush()
}

func (s *Server) handleEvents(w http.ResponseWriter, r *http.Request) {
	token, user, ok := s.authenticate(w, r)
	if !ok {
		return
	}
	var lastID int64
	if v := r.Header.Get("Last-Event-ID"); v != "" {
		n, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
		if err != nil || n < 0 {
			writeErr(w, http.StatusBadRequest, "Last-Event-ID must be a non-negative integer")
			return
		}
		lastID = n
	}

	// deliver decides whether this stream may carry an event for repo: the
	// user subscribed to it and this token can read it. A transient GitHub
	// failure falls back to the subscription, which was itself filtered by
	// a successful access check when it was PUT.
	deliver := func(repo string) bool {
		if !s.subscribed(user.ID, repoKey(repo)) {
			return false
		}
		ok, err := s.canRead(r.Context(), token, repo)
		if err != nil {
			return !errors.Is(err, ErrUnauthorized)
		}
		return ok
	}

	res := s.hub.Subscribe(lastID, streamBuffer, func(key string) bool { return s.subscribed(user.ID, key) })
	defer s.hub.Unsubscribe(res.Sub)

	h := w.Header()
	h.Set("Content-Type", "text/event-stream")
	h.Set("Cache-Control", "no-cache, no-store")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	out := sseWriter{w: w, rc: http.NewResponseController(w)}

	switch {
	case res.Resync:
		s.metrics.Inc(mResyncs, "")
		data, _ := json.Marshal(map[string]any{"kind": "resync", "id": res.Position})
		if out.event(res.Position, "resync", data) != nil {
			return
		}
	default:
		if lastID > 0 {
			s.metrics.Inc(mReplays, "")
		}
		for _, ev := range res.Replay {
			if !deliver(ev.Repo) {
				continue
			}
			if s.send(out, ev) != nil {
				return
			}
			s.metrics.Inc(mReplayedEvents, "")
		}
		data, _ := json.Marshal(map[string]any{"kind": "hello", "id": res.Position})
		if out.event(res.Position, "hello", data) != nil {
			return
		}
	}

	ticker := s.clock.NewTicker(s.cfg.PingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-ticker.C():
			if out.comment("ping") != nil {
				return
			}
		case ev, open := <-res.Sub.ch:
			if !open {
				if s.hub.Dropped(res.Sub) {
					s.metrics.Inc(mStreamsDropped, "")
					s.log.Warn("stream dropped: client fell behind", "user", user.Login)
				}
				return
			}
			if !deliver(ev.Repo) {
				continue
			}
			if s.send(out, ev) != nil {
				return
			}
		}
	}
}

func (s *Server) send(out sseWriter, ev Event) error {
	data, err := json.Marshal(ev)
	if err != nil {
		return err
	}
	if err := out.event(ev.ID, ev.Kind, data); err != nil {
		return err
	}
	s.metrics.Inc(mEventsSent, "")
	return nil
}

// ---- POST /auth/exchange, /auth/revoke ----------------------------------

type exchangeRequest struct {
	Code     string `json:"code"`
	State    string `json:"state"`
	Verifier string `json:"verifier"`
}

// stateFor is the app's state value for a verifier: base64url(sha256(v)),
// unpadded, which is exactly a PKCE S256 code_challenge.
func stateFor(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func (s *Server) handleExchange(w http.ResponseWriter, r *http.Request) {
	if !s.cfg.OAuthConfigured() {
		s.metrics.Inc(mExchangeFailures, "not_configured")
		writeErr(w, http.StatusServiceUnavailable, "oauth is not configured on this relay")
		return
	}
	var req exchangeRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxSmallBody)).Decode(&req); err != nil ||
		req.Code == "" || req.State == "" || len(req.Verifier) < 43 || len(req.Verifier) > 128 {
		s.metrics.Inc(mExchangeFailures, "bad_request")
		writeErr(w, http.StatusBadRequest, "body must be {code, state, verifier} with a 43-128 character verifier")
		return
	}
	if subtle.ConstantTimeCompare([]byte(stateFor(req.Verifier)), []byte(req.State)) != 1 {
		// A redirect captured by another app claiming vitruvian:// carries
		// code and state but not the verifier: it stops here.
		s.metrics.Inc(mExchangeFailures, "state_mismatch")
		s.log.Warn("auth exchange rejected: state does not match verifier")
		writeErr(w, http.StatusBadRequest, "state_mismatch")
		return
	}
	tok, err := s.gh.Exchange(r.Context(), req.Code)
	var xerr *ExchangeError
	switch {
	case errors.As(err, &xerr):
		s.metrics.Inc(mExchangeFailures, "github_rejected")
		s.log.Warn("auth exchange refused by github", "reason", xerr.Code)
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "exchange_failed", "reason": xerr.Code})
		return
	case err != nil:
		s.metrics.Inc(mExchangeFailures, "github_error")
		s.log.Warn("auth exchange failed", "err", err)
		writeErr(w, http.StatusBadGateway, "could not reach github")
		return
	}
	s.metrics.Inc(mExchanges, "")
	s.log.Info("auth exchange ok")
	writeJSON(w, http.StatusOK, tok)
}

func (s *Server) handleRevoke(w http.ResponseWriter, r *http.Request) {
	token := bearer(r)
	if token == "" {
		writeErr(w, http.StatusBadRequest, "missing bearer token")
		return
	}
	s.forget(tokenHash(token))
	if s.cfg.OAuthConfigured() {
		if err := s.gh.Revoke(r.Context(), token); err != nil {
			s.log.Warn("token revoke failed (best effort)", "err", err)
		}
	}
	// Best effort by design: the app deletes its Keychain item regardless.
	w.WriteHeader(http.StatusNoContent)
}
