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
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// GitHub talks to the GitHub REST API and OAuth endpoints. Both base URLs
// are injectable so tests run against an httptest fake.
type GitHub struct {
	APIURL       string
	WebURL       string
	ClientID     string
	ClientSecret string
	HTTP         *http.Client
	Metrics      *Metrics
}

// ErrUnauthorized means GitHub rejected the token (401): the client must
// drop it and sign in again.
var ErrUnauthorized = errors.New("github rejected the token")

// GitHubUser is the part of GET /user the relay needs.
type GitHubUser struct {
	ID    int64  `json:"id"`
	Login string `json:"login"`
}

func (g *GitHub) do(ctx context.Context, req *http.Request) (*http.Response, error) {
	req = req.WithContext(ctx)
	req.Header.Set("User-Agent", "vitruvian-github-relay")
	if req.Header.Get("Accept") == "" {
		req.Header.Set("Accept", "application/vnd.github+json")
	}
	if strings.HasPrefix(req.URL.String(), g.APIURL) {
		req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	}
	return g.HTTP.Do(req)
}

// User resolves a token to its user (GET /user).
func (g *GitHub) User(ctx context.Context, token string) (GitHubUser, error) {
	req, _ := http.NewRequest(http.MethodGet, g.APIURL+"/user", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := g.do(ctx, req)
	if err != nil {
		g.Metrics.Inc(mGitHubErrors, "user")
		return GitHubUser{}, err
	}
	defer drain(resp)
	switch {
	case resp.StatusCode == http.StatusUnauthorized:
		return GitHubUser{}, ErrUnauthorized
	case resp.StatusCode != http.StatusOK:
		g.Metrics.Inc(mGitHubErrors, "user")
		return GitHubUser{}, fmt.Errorf("GET /user: HTTP %d", resp.StatusCode)
	}
	var u GitHubUser
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&u); err != nil || u.ID == 0 {
		g.Metrics.Inc(mGitHubErrors, "user")
		return GitHubUser{}, fmt.Errorf("GET /user: unreadable response")
	}
	return u, nil
}

// CanRead reports whether the token can read owner/name
// (GET /repos/{owner}/{repo}: 200 yes; 403/404 no; anything else an error).
func (g *GitHub) CanRead(ctx context.Context, token, repo string) (bool, error) {
	owner, name, _ := strings.Cut(repo, "/")
	req, _ := http.NewRequest(http.MethodGet, g.APIURL+"/repos/"+url.PathEscape(owner)+"/"+url.PathEscape(name), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := g.do(ctx, req)
	if err != nil {
		g.Metrics.Inc(mGitHubErrors, "repo")
		return false, err
	}
	defer drain(resp)
	switch resp.StatusCode {
	case http.StatusOK:
		return true, nil
	case http.StatusNotFound, http.StatusForbidden:
		return false, nil
	case http.StatusUnauthorized:
		return false, ErrUnauthorized
	default:
		g.Metrics.Inc(mGitHubErrors, "repo")
		return false, fmt.Errorf("GET /repos/%s: HTTP %d", repo, resp.StatusCode)
	}
}

// TokenResponse is what /auth/exchange hands back to the app, once.
type TokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	Scope       string `json:"scope"`
}

// ExchangeError is GitHub refusing the code (it answers 200 with an error
// body). Code is GitHub's error identifier, e.g. bad_verification_code; it
// is safe to return and log, unlike the code itself.
type ExchangeError struct{ Code string }

func (e *ExchangeError) Error() string { return "github refused the code: " + e.Code }

// Exchange redeems an OAuth code (POST {web}/login/oauth/access_token).
func (g *GitHub) Exchange(ctx context.Context, code string) (TokenResponse, error) {
	form := url.Values{"client_id": {g.ClientID}, "client_secret": {g.ClientSecret}, "code": {code}}
	req, _ := http.NewRequest(http.MethodPost, g.WebURL+"/login/oauth/access_token", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	resp, err := g.do(ctx, req)
	if err != nil {
		g.Metrics.Inc(mGitHubErrors, "exchange")
		return TokenResponse{}, err
	}
	defer drain(resp)
	if resp.StatusCode != http.StatusOK {
		g.Metrics.Inc(mGitHubErrors, "exchange")
		return TokenResponse{}, fmt.Errorf("token endpoint: HTTP %d", resp.StatusCode)
	}
	var body struct {
		TokenResponse
		Error string `json:"error"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&body); err != nil {
		g.Metrics.Inc(mGitHubErrors, "exchange")
		return TokenResponse{}, fmt.Errorf("token endpoint: unreadable response")
	}
	if body.Error != "" || body.AccessToken == "" {
		code := body.Error
		if code == "" {
			code = "no_token"
		}
		return TokenResponse{}, &ExchangeError{Code: code}
	}
	return body.TokenResponse, nil
}

// Revoke deletes a user token (DELETE /applications/{client_id}/token).
func (g *GitHub) Revoke(ctx context.Context, token string) error {
	b, _ := json.Marshal(map[string]string{"access_token": token})
	req, _ := http.NewRequest(http.MethodDelete, g.APIURL+"/applications/"+url.PathEscape(g.ClientID)+"/token", bytes.NewReader(b))
	req.SetBasicAuth(g.ClientID, g.ClientSecret)
	req.Header.Set("Content-Type", "application/json")
	resp, err := g.do(ctx, req)
	if err != nil {
		g.Metrics.Inc(mGitHubErrors, "revoke")
		return err
	}
	defer drain(resp)
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusNotFound {
		g.Metrics.Inc(mGitHubErrors, "revoke")
		return fmt.Errorf("revoke: HTTP %d", resp.StatusCode)
	}
	return nil
}

func drain(resp *http.Response) {
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1<<20))
	_ = resp.Body.Close()
}

// tokenHash keys every cache: the relay never keeps a token itself.
func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// ttlCache is a small expiring map. It is swept on write once it grows, so
// a stream of distinct tokens cannot grow it without bound.
type ttlCache[V any] struct {
	mu    sync.Mutex
	ttl   time.Duration
	clock Clock
	m     map[string]ttlEntry[V]
}

type ttlEntry[V any] struct {
	v   V
	exp time.Time
}

func newTTLCache[V any](clock Clock, ttl time.Duration) *ttlCache[V] {
	return &ttlCache[V]{ttl: ttl, clock: clock, m: map[string]ttlEntry[V]{}}
}

func (c *ttlCache[V]) Get(k string) (V, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.m[k]
	if !ok || !c.clock.Now().Before(e.exp) {
		var zero V
		return zero, false
	}
	return e.v, true
}

func (c *ttlCache[V]) Put(k string, v V) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.clock.Now()
	if len(c.m) > 4096 {
		for key, e := range c.m {
			if !now.Before(e.exp) {
				delete(c.m, key)
			}
		}
	}
	c.m[k] = ttlEntry[V]{v: v, exp: now.Add(c.ttl)}
}

func (c *ttlCache[V]) DeletePrefix(prefix string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for k := range c.m {
		if strings.HasPrefix(k, prefix) {
			delete(c.m, k)
		}
	}
}
