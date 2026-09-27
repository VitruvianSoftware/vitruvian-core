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
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// The exact link the phone parses. WireTest.kt parses this same string; if
// either side changes its shape, one of the two tests fails.
const pairLinkFixture = "vitruvian-remote://pair?code=482917&name=atlas&url=http%3A%2F%2F100.124.228.116%3A7411"

func TestPairAppLinkMatchesThePhoneFixture(t *testing.T) {
	if got := pairAppLink("100.124.228.116:7411", "482917", "atlas"); got != pairLinkFixture {
		t.Fatalf("pairAppLink = %q\nwant        %q", got, pairLinkFixture)
	}
}

func TestPairName(t *testing.T) {
	for in, want := range map[string]string{
		"atlas":                 "atlas",
		" James's MacBook Pro ": "JamessMacBookPro",
		"a<script>b":            "ascriptb",
		strings.Repeat("x", 40): strings.Repeat("x", 32),
		"":                      "",
	} {
		if got := pairName(in); got != want {
			t.Errorf("pairName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestPairPage(t *testing.T) {
	_, _, ts := newTestAgent(t)
	// Straight into the handler, not over a socket: Go's client refuses to
	// SEND some of the malformed Host headers this test needs to see refused.
	get := func(path, host string) (*http.Response, string) {
		t.Helper()
		req := httptest.NewRequest(http.MethodGet, path, nil)
		req.Host = host
		rec := httptest.NewRecorder()
		ts.Config.Handler.ServeHTTP(rec, req)
		resp := rec.Result()
		b, _ := io.ReadAll(resp.Body)
		return resp, string(b)
	}

	resp, body := get("/pair?code=482917", "100.124.228.116:7411")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status %d: %s", resp.StatusCode, body)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Errorf("Content-Type = %q", ct)
	}
	if csp := resp.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "default-src 'none'") {
		t.Errorf("missing CSP, got %q", csp)
	}
	// The link is HTML-escaped inside href, so & appears as &amp;.
	for _, want := range []string{
		"intent://pair?code=482917&amp;",
		"url=http%3A%2F%2F100.124.228.116%3A7411#Intent;scheme=vitruvian-remote;package=dev.vitruvian.remote;end",
		"vitruvian-remote://pair?code=482917&amp;",
		"<code>482 917</code>",
	} {
		if !strings.Contains(body, want) {
			t.Errorf("page lacks %q", want)
		}
	}

	for _, bad := range []string{"/pair", "/pair?code=12345", "/pair?code=1234567", "/pair?code=12345a"} {
		if resp, _ := get(bad, "100.124.228.116:7411"); resp.StatusCode != http.StatusBadRequest {
			t.Errorf("%s: status %d, want 400", bad, resp.StatusCode)
		}
	}
	// A Host that could smuggle a path or userinfo into the app link is refused.
	for _, host := range []string{"evil.example/x", "user@100.1.2.3:7411", "a b"} {
		if resp, _ := get("/pair?code=482917", host); resp.StatusCode != http.StatusBadRequest {
			t.Errorf("Host %q: status %d, want 400", host, resp.StatusCode)
		}
	}
	post := httptest.NewRecorder()
	ts.Config.Handler.ServeHTTP(post, httptest.NewRequest(http.MethodPost, "/pair?code=482917", nil))
	if post.Code != http.StatusMethodNotAllowed {
		t.Errorf("POST /pair: status %d, want 405", post.Code)
	}
}
