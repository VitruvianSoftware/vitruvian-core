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
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Config is everything the relay reads from its environment.
type Config struct {
	ListenAddr     string
	WebhookSecret  []byte
	ClientID       string
	ClientSecret   string
	GitHubAPIURL   string // REST API base, e.g. https://api.github.com
	GitHubWebURL   string // OAuth base, e.g. https://github.com
	BufferWindow   time.Duration
	BufferMaxCount int
	PingInterval   time.Duration
	CacheTTL       time.Duration
}

// ErrEmptyWebhookSecret is why the relay refuses to start. An empty secret
// would make every HMAC check trivially forgeable: the same trap the CI
// collector fell into (telemetry spec §3.4).
var ErrEmptyWebhookSecret = errors.New("GITHUB_WEBHOOK_SECRET is empty: refusing to start, since an empty secret lets anyone forge webhook deliveries")

// LoadConfig reads the environment through getenv (os.Getenv in production).
func LoadConfig(getenv func(string) string) (Config, error) {
	c := Config{
		ListenAddr:     orDefault(getenv("LISTEN_ADDR"), ":8080"),
		WebhookSecret:  []byte(getenv("GITHUB_WEBHOOK_SECRET")),
		ClientID:       strings.TrimSpace(getenv("GITHUB_CLIENT_ID")),
		ClientSecret:   getenv("GITHUB_CLIENT_SECRET"),
		GitHubAPIURL:   strings.TrimRight(orDefault(getenv("GITHUB_API_URL"), "https://api.github.com"), "/"),
		GitHubWebURL:   strings.TrimRight(orDefault(getenv("GITHUB_WEB_URL"), "https://github.com"), "/"),
		BufferWindow:   15 * time.Minute,
		BufferMaxCount: 500,
		PingInterval:   25 * time.Second,
		CacheTTL:       10 * time.Minute,
	}
	if len(strings.TrimSpace(string(c.WebhookSecret))) == 0 {
		return Config{}, ErrEmptyWebhookSecret
	}
	var err error
	if c.BufferWindow, err = durationEnv(getenv, "BUFFER_WINDOW", c.BufferWindow); err != nil {
		return Config{}, err
	}
	if c.PingInterval, err = durationEnv(getenv, "PING_INTERVAL", c.PingInterval); err != nil {
		return Config{}, err
	}
	if v := getenv("BUFFER_MAX_EVENTS"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n <= 0 {
			return Config{}, fmt.Errorf("BUFFER_MAX_EVENTS=%q: want a positive integer", v)
		}
		c.BufferMaxCount = n
	}
	return c, nil
}

// OAuthConfigured reports whether /auth/exchange and /auth/revoke can work.
func (c Config) OAuthConfigured() bool { return c.ClientID != "" && c.ClientSecret != "" }

func orDefault(v, d string) string {
	if v == "" {
		return d
	}
	return v
}

func durationEnv(getenv func(string) string, key string, d time.Duration) (time.Duration, error) {
	v := getenv(key)
	if v == "" {
		return d, nil
	}
	p, err := time.ParseDuration(v)
	if err != nil || p <= 0 {
		return 0, fmt.Errorf("%s=%q: want a positive duration such as 25s", key, v)
	}
	return p, nil
}
