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
	"errors"
	"io"
	"net/http"
	"testing"
	"time"
)

func env(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

func TestRefusesToStartWithEmptyWebhookSecret(t *testing.T) {
	for name, secret := range map[string]string{"unset": "", "whitespace": "  \n"} {
		t.Run(name, func(t *testing.T) {
			ready := make(chan string, 1)
			err := run(context.Background(), env(map[string]string{
				"GITHUB_WEBHOOK_SECRET": secret, "LISTEN_ADDR": "127.0.0.1:0",
			}), io.Discard, ready)
			if !errors.Is(err, ErrEmptyWebhookSecret) {
				t.Fatalf("run() = %v, want ErrEmptyWebhookSecret", err)
			}
			select {
			case addr := <-ready:
				t.Fatalf("relay started listening on %s with an empty secret", addr)
			default:
			}
		})
	}
}

func TestConfigDefaults(t *testing.T) {
	c, err := LoadConfig(env(map[string]string{"GITHUB_WEBHOOK_SECRET": "s"}))
	if err != nil {
		t.Fatal(err)
	}
	if c.PingInterval != 25*time.Second || c.BufferWindow != 15*time.Minute || c.CacheTTL != 10*time.Minute {
		t.Errorf("defaults: ping %v window %v ttl %v", c.PingInterval, c.BufferWindow, c.CacheTTL)
	}
	if c.GitHubAPIURL != "https://api.github.com" || c.GitHubWebURL != "https://github.com" {
		t.Errorf("default URLs: %q %q", c.GitHubAPIURL, c.GitHubWebURL)
	}
	if c.OAuthConfigured() {
		t.Error("OAuth reported configured with no client id/secret")
	}
	if _, err := LoadConfig(env(map[string]string{"GITHUB_WEBHOOK_SECRET": "s", "PING_INTERVAL": "soon"})); err == nil {
		t.Error("bad PING_INTERVAL accepted")
	}
}

// The real entrypoint serves /healthz and shuts down when its context ends.
func TestRunServesAndStops(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	ready := make(chan string, 1)
	done := make(chan error, 1)
	go func() {
		done <- run(ctx, env(map[string]string{"GITHUB_WEBHOOK_SECRET": "s", "LISTEN_ADDR": "127.0.0.1:0"}), io.Discard, ready)
	}()
	addr := <-ready
	resp, err := http.Get("http://" + addr + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("/healthz: HTTP %d", resp.StatusCode)
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run() = %v after shutdown", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("run() did not return after its context ended")
	}
}
