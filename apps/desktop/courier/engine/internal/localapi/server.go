// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

// Package localapi is Courier's local API (milestone 5): an MCP server over streamable HTTP at /v0/mcp, the same
// path the reference app uses, so an MCP client that used the reference app's server needs only a new address and
// token. Each tool calls the engine's own protocol methods in-process (Dispatcher), so it answers from the same
// code the app's requests run.
//
// It listens on 127.0.0.1 only, unless Remote Access is on: then on every address. Every request needs a bearer
// token the person approved in Settings → Integrations. With Remote Access off, a request whose Host isn't this
// Mac's loopback address is refused (a DNS rebinding guard); with it on, any Host is accepted and the token is the
// guard. A request from a browser (one carrying Origin) is always refused, and no CORS header is ever sent.
//
// Logs carry a tool's name, how long it took and how it ended. Never a token, a message's text, a chat's title, a
// name or a number.
package localapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/modelcontextprotocol/go-sdk/auth"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/rs/zerolog"

	"github.com/VitruvianSoftware/courier/engine/internal/store"
)

const (
	// MCPPath is where the MCP endpoint is served: the reference app's path.
	MCPPath = "/v0/mcp"
	// MaxBodyBytes is the largest request body accepted; a larger one is 413.
	MaxBodyBytes = 1 << 20
	// IdleTimeout is how long a connection may sit between requests before it is closed.
	IdleTimeout = 120 * time.Second
)

// Dispatcher calls one of the engine's protocol methods and returns its result as JSON. *rpc.Dispatcher is one.
// An error that carries a protocol code (ProtocolCode) is mapped to plain words for the tool's caller.
type Dispatcher interface {
	Dispatch(ctx context.Context, method string, params any) (json.RawMessage, error)
}

// Publisher sends a notification to the app and says how many app connections it was handed to; Listeners is how
// many there are now. *rpc.Notifier is one.
type Publisher interface {
	Publish(method string, params any) int
	Listeners() int
}

// Config is how the local API should be running.
type Config struct {
	Enabled bool // Allow connections
	Port    int
	Remote  bool // Remote Access: every address rather than 127.0.0.1, and any Host
}

// Status is how the local API is running.
type Status struct {
	Enabled   bool   `json:"enabled"`
	Port      int    `json:"port"`
	Remote    bool   `json:"remote"`
	Listening bool   `json:"listening"`
	Error     string `json:"error"` // why it isn't listening although enabled, for people; "" otherwise
}

// Server is the local API.
type Server struct {
	store *store.Store
	disp  Dispatcher
	pub   Publisher
	log   zerolog.Logger
	mcp   *mcp.Server
	http  http.Handler

	mu     sync.Mutex // guards cfg, status, ln and srv: Apply runs one at a time
	cfg    Config
	status Status
	ln     net.Listener
	srv    *http.Server
	served chan struct{} // closed when srv's Serve returns

	remote atomic.Bool  // Remote Access as the listener was opened with: read on every request
	port   atomic.Int64 // the port listened on: the Host guard's

	pairs pairing // the pairing request waiting for the person, if any (pair.go)

	idleTimeout time.Duration // IdleTimeout unless a test sets it (SetIdleTimeout)
}

// SetIdleTimeout changes IdleTimeout for listeners opened after it, for tests.
func (s *Server) SetIdleTimeout(d time.Duration) {
	s.mu.Lock()
	s.idleTimeout = d
	s.mu.Unlock()
}

// New is a local API serving from s, calling the engine through d and telling the app through p. It listens only
// once Apply says so.
func New(s *store.Store, d Dispatcher, p Publisher, log zerolog.Logger) *Server {
	srv := &Server{store: s, disp: d, pub: p, log: log, status: Status{Port: store.DefaultLocalAPIPort}}
	srv.mcp = mcp.NewServer(&mcp.Implementation{Name: "courier", Title: "Courier", Version: "0.5"}, &mcp.ServerOptions{
		Instructions: "Courier is a messaging app on this Mac that brings several chat networks into one inbox. " +
			"These tools read its chats and messages, and send messages when this connection is allowed to.",
	})
	srv.addTools()
	streamable := mcp.NewStreamableHTTPHandler(func(*http.Request) *mcp.Server { return srv.mcp }, &mcp.StreamableHTTPOptions{
		// The SDK's own guard refuses any Host but a loopback one whenever a request arrives on loopback. Ours
		// (guard) is the same with Remote Access off, and must let any Host through with it on.
		DisableLocalhostProtection: true,
		MaxRequestBodyBytes:        MaxBodyBytes,
		SessionTimeout:             time.Hour,
	})
	authed := auth.RequireBearerToken(srv.verify, &auth.RequireBearerTokenOptions{AllowMissingExpiration: true})(streamable)
	mux := http.NewServeMux()
	mux.Handle(MCPPath, srv.requireToken(authed))
	mux.HandleFunc(PairPath, srv.servePair)
	srv.http = srv.guard(mux)
	return srv
}

// MCP is the MCP server the tools are on, for a client in the same process (a test's in-memory one).
func (s *Server) MCP() *mcp.Server { return s.mcp }

// Handler is the local API's HTTP handler, guards and all: what the listener serves.
func (s *Server) Handler() http.Handler { return s.http }

// Status is how the local API is running now.
func (s *Server) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.status
}

// Addr is the address listened on, or nil when not listening.
func (s *Server) Addr() net.Addr {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.ln == nil {
		return nil
	}
	return s.ln.Addr()
}

// Apply starts, stops or moves the listener to match cfg, at once: a change of port or of Remote Access closes
// the old listener (and the connections on it) and opens the new one. A port that can't be listened on leaves the
// local API off, with the reason in Status.Error; nothing else about the engine is affected. Port 0 picks a free
// port (for tests).
func (s *Server) Apply(ctx context.Context, cfg Config) Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.ln != nil && cfg.Enabled && s.cfg.Enabled && cfg.Port == s.cfg.Port && cfg.Remote == s.cfg.Remote && cfg.Port != 0 {
		return s.status // already so
	}
	s.closeLocked()
	s.cfg = cfg
	s.status = Status{Enabled: cfg.Enabled, Port: cfg.Port, Remote: cfg.Remote}
	if !cfg.Enabled {
		return s.status
	}
	host := "127.0.0.1"
	if cfg.Remote {
		host = "" // every address, IPv4 and IPv6
	}
	ln, err := (&net.ListenConfig{}).Listen(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(cfg.Port)))
	if err != nil {
		s.status.Error = listenError(cfg.Port, err)
		s.log.Warn().Int("port", cfg.Port).Bool("remote", cfg.Remote).Msg("the local API couldn't listen")
		return s.status
	}
	port := ln.Addr().(*net.TCPAddr).Port
	s.remote.Store(cfg.Remote)
	s.port.Store(int64(port))
	s.ln = ln
	idle := s.idleTimeout
	if idle <= 0 {
		idle = IdleTimeout
	}
	// IdleTimeout closes a kept-alive connection that has sat with no request; a response still being written (the
	// MCP SDK's long-lived GET stream) is not idle, so it isn't cut.
	s.srv = &http.Server{Handler: s.http, ReadHeaderTimeout: 10 * time.Second, IdleTimeout: idle}
	s.served = make(chan struct{})
	go func(srv *http.Server, done chan struct{}) {
		defer close(done)
		_ = srv.Serve(ln)
	}(s.srv, s.served)
	s.status.Port = port
	s.status.Listening = true
	return s.status
}

// Close stops listening and closes every connection.
func (s *Server) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closeLocked()
	s.status.Listening = false
}

func (s *Server) closeLocked() {
	if s.srv == nil {
		return
	}
	_ = s.srv.Close() // closes the listener and every connection, streams included
	<-s.served
	s.srv, s.ln, s.served = nil, nil, nil
}

// listenError is why port couldn't be listened on, for people.
func listenError(port int, err error) string {
	if errors.Is(err, syscall.EADDRINUSE) {
		return fmt.Sprintf("Port %d is in use by another app", port)
	}
	if errors.Is(err, syscall.EACCES) {
		return fmt.Sprintf("Courier isn't allowed to use port %d", port)
	}
	return fmt.Sprintf("Courier couldn't listen on port %d", port)
}

// writeError answers with status and {"error": msg}. No CORS header is ever set.
func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

// guard is what every request passes first: no Origin (a browser) at all, then, with Remote Access off, only a
// loopback Host on our own port; and the body is read no further than MaxBodyBytes.
func (s *Server) guard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, browser := r.Header["Origin"]; browser {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		if !s.remote.Load() && !s.loopbackHost(r.Host) {
			writeError(w, http.StatusForbidden, "forbidden")
			return
		}
		// The limit holds while the body is read (413 past it), with or without a Content-Length. Refusing at once on
		// the Content-Length alone would close the connection while the client is still writing, and it would see
		// a broken pipe rather than the 413.
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, MaxBodyBytes)
		}
		next.ServeHTTP(w, r)
	})
}

// loopbackHost is whether host is 127.0.0.1, [::1] or localhost on the port listened on.
func (s *Server) loopbackHost(host string) bool {
	h, p, err := net.SplitHostPort(host)
	if err != nil || p != strconv.FormatInt(s.port.Load(), 10) {
		return false
	}
	return h == "127.0.0.1" || h == "::1" || strings.EqualFold(h, "localhost")
}

type tokenKey struct{}

// requireToken looks the request's bearer token up, on every request: an unknown or revoked one (revoked while a
// client is connected, say) is 401 at once.
func (s *Server) requireToken(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		scheme, secret, ok := strings.Cut(r.Header.Get("Authorization"), " ")
		if !ok || !strings.EqualFold(scheme, "Bearer") || strings.TrimSpace(secret) == "" {
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		tok, err := s.store.LookupAPIToken(r.Context(), strings.TrimSpace(secret))
		if errors.Is(err, store.ErrLastUsedNotSaved) {
			// A good token whose last use couldn't be written down: only "last used" in Settings is behind.
			s.log.Warn().Msg("the local API couldn't save a token's last use")
			err = nil
		}
		if err != nil {
			if !errors.Is(err, store.ErrNotFound) {
				s.log.Warn().Msg("the local API couldn't look a token up")
			}
			writeError(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), tokenKey{}, tok)))
	})
}

// verify hands the token requireToken found to the MCP SDK, which keeps each session to the token that began it
// and gives each tool call the request's TokenInfo.
func (s *Server) verify(ctx context.Context, _ string, _ *http.Request) (*auth.TokenInfo, error) {
	tok, ok := ctx.Value(tokenKey{}).(store.APIToken)
	if !ok {
		return nil, auth.ErrInvalidToken
	}
	return &auth.TokenInfo{UserID: tok.ID, Extra: map[string]any{"canSend": tok.CanSend}}, nil
}
