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
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/VitruvianSoftware/vitruvian-core/mobile/android/remote/macagent/metrics"
)

// These pin the agent's whole HTTP contract without running a single macOS
// command: the sampler is never started, and its snapshot is set directly.

func TestReadOnlyRefusesEverythingButGet(t *testing.T) {
	srv := httptest.NewServer(newMux(NewSampler(time.Second)))
	defer srv.Close()

	for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodPatch} {
		req, _ := http.NewRequest(method, srv.URL+"/v1/metrics", nil)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusMethodNotAllowed {
			t.Errorf("%s /v1/metrics: got %d, want 405 -- this agent must not accept writes", method, resp.StatusCode)
		}
		if resp.Header.Get("Allow") != "GET, HEAD" {
			t.Errorf("%s: Allow header %q", method, resp.Header.Get("Allow"))
		}
	}
	// There is no exec endpoint. A 404 here is the proof, and a future slice
	// that adds one must come and change this test on purpose.
	resp, err := http.Post(srv.URL+"/v1/exec", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("/v1/exec: got %d, want 404", resp.StatusCode)
	}
}

func TestHealthzBeforeAndAfterTheFirstSample(t *testing.T) {
	s := NewSampler(time.Second)
	srv := httptest.NewServer(newMux(s))
	defer srv.Close()

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
	if body["read_only"] != true {
		t.Errorf("healthz must declare read_only: %v", body)
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
	s := NewSampler(time.Second)
	s.mu.Lock()
	s.snap = metrics.Snapshot{SampledAt: time.Now(), CPU: metrics.CPU{Ready: true, BusyPercent: 12.5}}
	s.host = metrics.Host{Hostname: "atlas", Cores: 16}
	s.mu.Unlock()
	srv := httptest.NewServer(newMux(s))
	defer srv.Close()

	for path, want := range map[string]string{"/v1/metrics": `"busy_percent":12.5`, "/v1/host": `"hostname":"atlas"`} {
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
