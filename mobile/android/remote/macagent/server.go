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
	"time"
)

// newMux is the whole HTTP surface. Three GETs, nothing else.
//
// There is no POST, no PUT, no path that takes input. A request can choose
// which of three documents to read and that is all. Method checks are
// explicit rather than left to the default handler so a probe gets a clear
// 405 instead of a 200 with the wrong body.
func newMux(s *Sampler) *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/metrics", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Snapshot())
	}))
	mux.HandleFunc("/v1/host", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Host())
	}))
	mux.HandleFunc("/healthz", getOnly(func(w http.ResponseWriter, r *http.Request) {
		snap := s.Snapshot()
		age := time.Since(snap.SampledAt)
		ageMS := age.Milliseconds()
		if snap.SampledAt.IsZero() {
			// time.Since(zero) is ~292 million years; -1 says "never".
			ageMS = -1
		}
		// Unhealthy if the sampler has stopped producing. A process that is
		// up but serving a stale reading is exactly the failure a health
		// check exists to catch.
		status := http.StatusOK
		if snap.SampledAt.IsZero() || age > 30*time.Second {
			status = http.StatusServiceUnavailable
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.WriteHeader(status)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"ok":            status == http.StatusOK,
			"sample_age_ms": ageMS,
			"agent_version": version,
			"read_only":     true,
			"sampled_at":    snap.SampledAt,
		})
	}))
	return mux
}

func getOnly(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", "GET, HEAD")
			http.Error(w, "read-only agent: GET only", http.StatusMethodNotAllowed)
			return
		}
		h(w, r)
	}
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	// Every reading is new; a cached one is a stale dashboard.
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(v)
}
