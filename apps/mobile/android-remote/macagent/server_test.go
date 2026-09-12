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
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/VitruvianSoftware/vitruvian-core/apps/mobile/android-remote/macagent/metrics"
)

// These pin the agent's whole HTTP contract without running a single macOS
// command: the sampler is never started, and its snapshot is set directly.

// newTestAgent wires a sampler and a store over a temp config dir, so a test
// never touches ~/.config and two tests never share a token.
func newTestAgent(t *testing.T) (*Sampler, *Store, *httptest.Server) {
	t.Helper()
	s := NewSampler(time.Second, "", "", nil, nil)
	store := NewStore(t.TempDir())
	if _, err := store.EnsureToken(); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(newMux(s, store, "", ""))
	t.Cleanup(srv.Close)
	return s, store, srv
}

// v1.0 had a test here asserting there was no /v1/exec at all, and it said a
// slice that added one would have to come and change it on purpose. This is
// that change. The line the agent defends is no longer "runs nothing" but
// "runs nothing for a caller that has not paired", so that is what is pinned.
func TestReadEndpointsAreGetOnly(t *testing.T) {
	_, _, srv := newTestAgent(t)

	for _, path := range []string{"/v1/metrics", "/v1/host", "/v1/processes", "/v1/vms", "/v1/containers", "/v1/k8s", "/v1/sessions", "/healthz"} {
		for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodPatch} {
			req, _ := http.NewRequest(method, srv.URL+path, nil)
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatal(err)
			}
			resp.Body.Close()
			if resp.StatusCode != http.StatusMethodNotAllowed {
				t.Errorf("%s %s: got %d, want 405", method, path, resp.StatusCode)
			}
			if resp.Header.Get("Allow") != "GET, HEAD" {
				t.Errorf("%s %s: Allow header %q", method, path, resp.Header.Get("Allow"))
			}
		}
	}
}

func TestActEndpointsRefuseAnUnpairedCaller(t *testing.T) {
	_, store, srv := newTestAgent(t)

	// No header at all: 401, and the client is told how to fix it.
	for _, c := range []struct{ method, path string }{
		{http.MethodPost, "/v1/exec"},
		{http.MethodGet, "/v1/clipboard"},
		{http.MethodPost, "/v1/clipboard"},
		{http.MethodPost, "/v1/audio"},
		{http.MethodPost, "/v1/power"},
	} {
		req, _ := http.NewRequest(c.method, srv.URL+c.path, strings.NewReader(`{}`))
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("%s %s with no token: got %d, want 401", c.method, c.path, resp.StatusCode)
		}
		if resp.Header.Get("WWW-Authenticate") == "" {
			t.Errorf("%s %s: no WWW-Authenticate header", c.method, c.path)
		}
	}

	// A token that is not this agent's: 403, a different situation from 401
	// and one the phone renders differently.
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/exec", strings.NewReader(`{"kind":"shell","command":"echo hi"}`))
	req.Header.Set("Authorization", "Bearer "+strings.Repeat("a", 64))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden {
		t.Errorf("wrong token: got %d, want 403", resp.StatusCode)
	}

	// An empty presented token must never be accepted, whatever is on disk.
	// This is the failure where a half-written token file authorises anyone
	// who sends "Bearer ".
	if store.Authorized("") {
		t.Error("an empty presented token was accepted")
	}
}

func TestHealthzBeforeAndAfterTheFirstSample(t *testing.T) {
	s, store, srv := newTestAgent(t)

	get := func() (int, map[string]any) {
		resp, err := http.Get(srv.URL + "/healthz")
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var body map[string]any
		if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		return resp.StatusCode, body
	}

	// Never sampled: unhealthy, and the age must not be the 292-million-year
	// figure time.Since(zero) produces.
	code, body := get()
	if code != http.StatusServiceUnavailable {
		t.Errorf("before first sample: got %d, want 503", code)
	}
	if body["sample_age_ms"] != float64(-1) {
		t.Errorf("before first sample: sample_age_ms = %v, want -1", body["sample_age_ms"])
	}
	// v1.1 is not read-only and must not claim to be: a phone built against
	// v1.0 reads this field to decide whether to offer the act controls.
	if body["read_only"] != false {
		t.Errorf("healthz must declare read_only:false in v1.1: %v", body)
	}
	if body["paired"] != false {
		t.Errorf("nothing has paired yet: %v", body)
	}

	// Pairing flips it, so a person looking at the agent can tell "nobody
	// has paired" from "a phone lost its token".
	if err := store.WritePairing("482917"); err != nil {
		t.Fatal(err)
	}
	if _, err := store.ClaimPairing("482917"); err != nil {
		t.Fatal(err)
	}
	if _, body := get(); body["paired"] != true {
		t.Errorf("after pairing: %v", body)
	}

	// Fresh sample: healthy.
	s.mu.Lock()
	s.snap = metrics.Snapshot{SampledAt: time.Now()}
	s.mu.Unlock()
	if code, _ := get(); code != http.StatusOK {
		t.Errorf("fresh sample: got %d, want 200", code)
	}

	// Stale sample: the process is up but the sampler has stopped. That is
	// precisely the failure a health check exists to report.
	s.mu.Lock()
	s.snap = metrics.Snapshot{SampledAt: time.Now().Add(-45 * time.Second)}
	s.mu.Unlock()
	if code, _ := get(); code != http.StatusServiceUnavailable {
		t.Errorf("stale sample: got %d, want 503", code)
	}
}

func TestMetricsAndHostAreServedAsJSONWithNoStore(t *testing.T) {
	s, _, srv := newTestAgent(t)
	s.mu.Lock()
	s.snap = metrics.Snapshot{SampledAt: time.Now(), CPU: metrics.CPU{Ready: true, BusyPercent: 12.5}}
	s.host = metrics.Host{Hostname: "atlas", Cores: 16, MACAddress: "a2:26:7e:45:c1:2d", WakeOnLAN: true}
	s.mu.Unlock()

	for path, want := range map[string]string{
		"/v1/metrics": `"busy_percent":12.5`,
		// mac_address and wake_on_lan are what the phone needs to offer
		// Wake-on-LAN at all; a v1.0 agent has neither.
		"/v1/host": `"mac_address":"a2:26:7e:45:c1:2d"`,
	} {
		resp, err := http.Get(srv.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		var buf [4096]byte
		n, _ := resp.Body.Read(buf[:])
		resp.Body.Close()
		if ct := resp.Header.Get("Content-Type"); ct != "application/json" {
			t.Errorf("%s: Content-Type %q", path, ct)
		}
		if cc := resp.Header.Get("Cache-Control"); cc != "no-store" {
			t.Errorf("%s: a cached reading is a stale dashboard; Cache-Control %q", path, cc)
		}
		if got := string(buf[:n]); !contains(got, want) {
			t.Errorf("%s: body %s does not contain %s", path, got, want)
		}
	}
}

func TestTailscaleIPv4OnlyMatchesCGNAT(t *testing.T) {
	// Whatever this host has, the answer must be in 100.64.0.0/10 or absent.
	// A Mac with no tailnet must not have its LAN address picked instead.
	ip, ok := tailscaleIPv4()
	if !ok {
		return
	}
	if len(ip) < 4 || ip[:4] != "100." {
		t.Errorf("tailscaleIPv4 returned %q, which is not in the CGNAT range", ip)
	}
}

func contains(s, sub string) bool {
	return len(sub) == 0 || (len(s) >= len(sub) && indexOf(s, sub) >= 0)
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

func TestPromqlOverflowIsAReasonNotACut(t *testing.T) {
	// An upstream that answers with more than the cap. The old proxy copied
	// the first 64 KiB and stopped, leaving the phone with unparseable JSON.
	big := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"success","data":{"result":["`))
		w.Write(bytes.Repeat([]byte("x"), maxOutput+10))
		w.Write([]byte(`"]}}`))
	}))
	defer big.Close()
	s := NewSampler(time.Second, "", "", nil, nil)
	srv := httptest.NewServer(newMux(s, NewStore(t.TempDir()), big.URL, ""))
	defer srv.Close()
	resp, err := http.Get(srv.URL + "/v1/promql?q=up")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var got map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatalf("reply must be valid JSON, got decode error %v", err)
	}
	if got["available"] != false || !strings.Contains(got["reason"].(string), "narrow the query") {
		t.Errorf("want an honest overflow reason, got %v", got)
	}
}
