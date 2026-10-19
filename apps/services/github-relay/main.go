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

// Command github-relay receives GitHub App webhooks, keeps a short
// per-repository history, and streams events to the Vitruvian desktop app
// over Server-Sent Events. It also performs the OAuth code exchange, since it
// is the only place the App's client secret may live.
// Spec: docs/superpowers/specs/2026-10-07-notch-github-feature-design.md.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

const defaultGitHubTimeout = 10 * time.Second

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, os.Getenv, os.Stderr, nil); err != nil {
		fmt.Fprintln(os.Stderr, "github-relay:", err)
		os.Exit(1)
	}
}

// run starts the relay and blocks until ctx ends. ready, if set, receives
// the bound address (tests listen on :0).
func run(ctx context.Context, getenv func(string) string, logOut io.Writer, ready chan<- string) error {
	cfg, err := LoadConfig(getenv)
	if err != nil {
		return err
	}
	log := slog.New(slog.NewJSONHandler(logOut, nil))
	if !cfg.OAuthConfigured() {
		log.Warn("GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET not set: /auth/exchange and /auth/revoke will answer 503")
	}
	srv := NewServer(cfg, realClock{}, nil, log)

	// Request contexts derive from base, so cancelling it ends every open
	// SSE stream; Shutdown alone would wait on them forever.
	base, cancelBase := context.WithCancel(context.Background())
	defer cancelBase()
	hs := &http.Server{
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		// No WriteTimeout: /events responses are open for hours.
		IdleTimeout: 120 * time.Second,
		BaseContext: func(net.Listener) context.Context { return base },
	}
	ln, err := net.Listen("tcp", cfg.ListenAddr)
	if err != nil {
		return err
	}
	log.Info("github-relay listening", "addr", ln.Addr().String(),
		"buffer_window", cfg.BufferWindow.String(), "buffer_max", cfg.BufferMaxCount, "ping", cfg.PingInterval.String())
	if ready != nil {
		ready <- ln.Addr().String()
	}
	errc := make(chan error, 1)
	go func() { errc <- hs.Serve(ln) }()
	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	cancelBase()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := hs.Shutdown(shutdownCtx); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}
