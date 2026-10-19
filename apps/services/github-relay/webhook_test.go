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
	"net/http"
	"strings"
	"testing"
)

// GitHub's documented X-Hub-Signature-256 test vector.
func TestValidSignatureGitHubVector(t *testing.T) {
	secret, body := []byte("It's a Secret to Everybody"), []byte("Hello, World!")
	good := "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"
	if !validSignature(secret, body, good) {
		t.Fatal("GitHub's test vector did not verify")
	}
	for _, bad := range []string{
		"", "sha256=", "sha1=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17",
		"sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e18",
		"sha256=zz", "757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17",
	} {
		if validSignature(secret, body, bad) {
			t.Errorf("signature %q accepted", bad)
		}
	}
}

func TestWebhookRejectsMissingOrBadSignatureWith400(t *testing.T) {
	r := newRelay(t)
	body := pushBody("o/r", "abc")
	cases := map[string]string{
		"missing":      "",
		"wrong secret": sign("not-the-secret", body),
		"malformed":    "sha256=nothex",
		"other body":   sign(testSecret, body+" "),
	}
	for name, sig := range cases {
		t.Run(name, func(t *testing.T) {
			req, _ := http.NewRequest(http.MethodPost, r.http.URL+"/webhook", strings.NewReader(body))
			req.Header.Set("X-GitHub-Event", "push")
			if sig != "" {
				req.Header.Set("X-Hub-Signature-256", sig)
			}
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatal(err)
			}
			resp.Body.Close()
			if resp.StatusCode != http.StatusBadRequest {
				t.Fatalf("HTTP %d, want 400", resp.StatusCode)
			}
		})
	}
	if got := r.srv.metrics.Get(mWebhookRejected, "missing_signature"); got != 1 {
		t.Errorf("missing_signature counter = %v, want 1", got)
	}
	if got := r.srv.metrics.Get(mWebhookRejected, "bad_signature"); got != 3 {
		t.Errorf("bad_signature counter = %v, want 3", got)
	}
	if n := r.srv.hub.nextID - r.srv.hub.floor; n != 0 {
		t.Errorf("%d rejected deliveries were buffered", n)
	}
}

func TestWebhookAcceptsSignedEvents(t *testing.T) {
	r := newRelay(t)
	if code := r.webhook("push", pushBody("o/r", "abc")); code != http.StatusOK {
		t.Fatalf("signed push: HTTP %d", code)
	}
	if code := r.webhook("ping", `{"zen":"hi"}`); code != http.StatusOK {
		t.Fatalf("signed ping: HTTP %d", code)
	}
	if code := r.webhook("issues", `{"repository":{"full_name":"o/r"}}`); code != http.StatusAccepted {
		t.Fatalf("signed unsupported event: HTTP %d, want 202", code)
	}
	if code := r.webhook("push", `{"no":"repo"}`); code != http.StatusBadRequest {
		t.Fatalf("signed push without a repository: HTTP %d, want 400", code)
	}
	if got := r.srv.metrics.Get(mWebhookEvents, "push"); got != 1 {
		t.Errorf("push counter = %v, want 1", got)
	}
}
