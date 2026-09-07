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
	"errors"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/VitruvianSoftware/vitruvian-core/mobile/android/remote/macagent/metrics"
)

// The HTTP surface, in two tiers.
//
// READ endpoints need no auth: the tailnet is the boundary, and everything
// they return is what Activity Monitor already shows anyone at the keyboard.
//
// ACT endpoints need the bearer token that pairing issues, and pairing needs
// someone at this Mac's keyboard. They are wrapped in act() below, one at a
// time and explicitly -- there is no "everything under this prefix is
// protected" rule, because the day someone adds a route to the wrong prefix
// is the day the token stops mattering.

// server carries what the handlers need beyond the sampler: the token store
// and the optional Prometheus upstream.
type server struct {
	sampler *Sampler
	store   *Store
	// promURL is empty unless --prometheus-url was given.
	promURL string
	// promToken is sent as a bearer on upstream PromQL requests. Grafana's
	// datasource proxy -- the reachable path to the homelab Prometheus from
	// off-network -- needs one. Never written to a log or a response.
	promToken string
}

func newMux(s *Sampler, store *Store, promURL string, promToken string) *http.ServeMux {
	srv := &server{sampler: s, store: store, promURL: strings.TrimRight(promURL, "/"), promToken: promToken}
	mux := http.NewServeMux()

	// --- read ---
	mux.HandleFunc("/v1/metrics", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Snapshot())
	}))
	mux.HandleFunc("/v1/host", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Host())
	}))
	mux.HandleFunc("/v1/processes", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Processes())
	}))
	mux.HandleFunc("/v1/ollama", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Ollama())
	}))
	mux.HandleFunc("/v1/vms", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.VMs())
	}))
	mux.HandleFunc("/v1/containers", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Containers())
	}))
	mux.HandleFunc("/v1/k8s", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.K8s())
	}))
	mux.HandleFunc("/v1/sessions", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Sessions())
	}))
	mux.HandleFunc("/v1/promql", getOnly(srv.promql))
	mux.HandleFunc("/healthz", getOnly(srv.healthz))

	// --- pairing ---
	// Unauthenticated by necessity: it is how a phone gets the credential.
	// The code itself is the proof, and Store.ClaimPairing bounds the
	// guessing.
	mux.HandleFunc("/v1/pair", postOnly(srv.pair))

	// --- read + act on the same path ---
	mux.HandleFunc("/v1/audio", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodGet, http.MethodHead:
			writeJSON(w, s.Audio())
		case http.MethodPost:
			srv.act(srv.setAudio)(w, r)
		default:
			methodNotAllowed(w, "GET, HEAD, POST")
		}
	})
	mux.HandleFunc("/v1/clipboard", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		// Reading the clipboard is an ACT, not a read, despite the verb: it
		// is where passwords live for thirty seconds at a time, and it is
		// not something Activity Monitor shows anyone.
		case http.MethodGet:
			srv.act(srv.getClipboard)(w, r)
		case http.MethodPost:
			srv.act(srv.setClipboard)(w, r)
		default:
			methodNotAllowed(w, "GET, POST")
		}
	})

	// --- act ---
	mux.HandleFunc("/v1/exec", postOnly(srv.act(srv.exec)))
	mux.HandleFunc("/v1/power", postOnly(srv.act(srv.power)))
	return mux
}

func (srv *server) healthz(w http.ResponseWriter, r *http.Request) {
	snap := srv.sampler.Snapshot()
	age := time.Since(snap.SampledAt)
	ageMS := age.Milliseconds()
	if snap.SampledAt.IsZero() {
		// time.Since(zero) is ~292 million years; -1 says "never".
		ageMS = -1
	}
	// Unhealthy if the sampler has stopped producing. A process that is up
	// but serving a stale reading is exactly the failure a health check
	// exists to catch.
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
		// v1.0 said true here. It is a lie in v1.1 and saying so is the
		// point of keeping the field: a phone built against the old agent
		// must be able to tell which one it is talking to.
		"read_only":  false,
		"paired":     srv.store.Paired(),
		"sampled_at": snap.SampledAt,
	})
}

// pair is POST /v1/pair. Every failure is a 403 with the same body: telling
// a guesser whether it got "expired" or "wrong" tells it where to spend its
// four remaining attempts. The agent log gets the real reason.
func (srv *server) pair(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Code string `json:"code"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	tok, err := srv.store.ClaimPairing(body.Code)
	if err != nil {
		log.Printf("pair: refused (%v)", err)
		writeError(w, http.StatusForbidden, "pairing refused")
		return
	}
	log.Print("pair: a client paired successfully")
	writeJSON(w, map[string]string{"token": tok})
}

// act wraps a handler in the bearer check.
//
// 401 for a missing or malformed header, 403 for a wrong token: the phone
// renders "not paired" for the first and "this token is dead, pair again"
// for the second, and they are genuinely different situations.
func (srv *server) act(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		presented, ok := bearer(r)
		if !ok {
			w.Header().Set("WWW-Authenticate", `Bearer realm="vitruvian-remote-agent"`)
			writeError(w, http.StatusUnauthorized, "act endpoints need a bearer token; pair first")
			return
		}
		if !srv.store.Authorized(presented) {
			writeError(w, http.StatusForbidden, "token not recognised; pair again")
			return
		}
		h(w, r)
	}
}

func bearer(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	tok, ok := strings.CutPrefix(h, "Bearer ")
	if !ok {
		return "", false
	}
	tok = strings.TrimSpace(tok)
	return tok, tok != ""
}

// logAct is the record the Mac keeps of what the phone did. First 80
// characters only: a command can be a whole script, and a log that
// truncates is one someone will still read.
func logAct(kind, command string) {
	const n = 80
	c := strings.ReplaceAll(strings.TrimSpace(command), "\n", " ")
	if len(c) > n {
		c = c[:n] + "..."
	}
	log.Printf("act %s: %s", kind, c)
}

func (srv *server) exec(w http.ResponseWriter, r *http.Request) {
	var req execRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if strings.TrimSpace(req.Command) == "" {
		writeError(w, http.StatusBadRequest, "command is required")
		return
	}
	logAct(req.Kind, req.Command)
	res, err := runAct(r.Context(), req)
	if err != nil {
		// The only error runAct returns is an unknown kind: a request that
		// never ran, which is a 400 rather than a result with an exit code.
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, res)
}

func (srv *server) getClipboard(w http.ResponseWriter, r *http.Request) {
	logAct("clipboard", "read")
	text, err := pbpaste(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "pbpaste: "+err.Error())
		return
	}
	writeJSON(w, map[string]string{"text": text})
}

func (srv *server) setClipboard(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Text string `json:"text"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	logAct("clipboard", "write "+body.Text)
	if err := pbcopy(r.Context(), body.Text); err != nil {
		writeError(w, http.StatusInternalServerError, "pbcopy: "+err.Error())
		return
	}
	writeJSON(w, map[string]bool{"ok": true})
}

func (srv *server) setAudio(w http.ResponseWriter, r *http.Request) {
	var body struct {
		VolumePercent int `json:"volume_percent"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	logAct("audio", "volume "+strconv.Itoa(body.VolumePercent))
	if err := setVolume(r.Context(), body.VolumePercent); err != nil {
		writeError(w, http.StatusInternalServerError, "set volume: "+err.Error())
		return
	}
	// Read it back rather than echoing the request: the clamp, and a Mac
	// that rounds to its own step, both make the effective volume differ
	// from what was asked for.
	out, err := run(r.Context(), "osascript", "-e", "get volume settings")
	if err == nil {
		if a, perr := metrics.ParseVolumeSettings(out); perr == nil {
			srv.sampler.SetAudio(a)
			writeJSON(w, a)
			return
		}
	}
	writeJSON(w, srv.sampler.Audio())
}

func (srv *server) power(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Action string `json:"action"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if _, ok := powerArgv[body.Action]; !ok {
		writeError(w, http.StatusBadRequest, "unknown action "+body.Action+" (want sleep or restart)")
		return
	}
	logAct("power", body.Action)
	// Answer BEFORE acting. `pmset sleepnow` suspends the machine mid-write
	// otherwise, and the phone sees a dropped connection for an action that
	// in fact succeeded.
	writeJSON(w, map[string]bool{"ok": true})
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
	if err := power(r.Context(), body.Action); err != nil {
		log.Printf("power %s: %v", body.Action, err)
	}
}

// promql proxies one instant query to the configured Prometheus.
//
// A proxy rather than a client: the phone already knows how to read
// Prometheus's JSON, and the agent has no business interpreting a query it
// did not write. What it adds is reach -- the Prometheus is on the homelab
// network, the phone is not.
func (srv *server) promql(w http.ResponseWriter, r *http.Request) {
	if srv.promURL == "" {
		writeJSON(w, map[string]any{"available": false, "reason": "not configured (--prometheus-url)"})
		return
	}
	q := r.URL.Query().Get("q")
	if strings.TrimSpace(q) == "" {
		writeError(w, http.StatusBadRequest, "q is required")
		return
	}
	upstream := srv.promURL + "/api/v1/query?query=" + url.QueryEscape(q)
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, upstream, nil)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if srv.promToken != "" {
		req.Header.Set("Authorization", "Bearer "+srv.promToken)
	}
	resp, err := promClient.Do(req)
	if err != nil {
		// 502, not 500: the agent is fine, the thing behind it is not, and
		// the phone should say so rather than blaming the Mac.
		writeError(w, http.StatusBadGateway, "prometheus: "+err.Error())
		return
	}
	defer resp.Body.Close()
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(resp.StatusCode)
	// Bounded: a query that matches a million series would otherwise be
	// copied straight into a phone.
	_, _ = io.Copy(w, io.LimitReader(resp.Body, maxOutput))
}

// promClient has a timeout of its own. http.DefaultClient has none, and a
// Prometheus that accepts the connection and then stalls would hold this
// handler open for as long as the phone is willing to wait.
var promClient = &http.Client{Timeout: 10 * time.Second}

func getOnly(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			methodNotAllowed(w, "GET, HEAD")
			return
		}
		h(w, r)
	}
}

func postOnly(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			methodNotAllowed(w, "POST")
			return
		}
		h(w, r)
	}
}

func methodNotAllowed(w http.ResponseWriter, allow string) {
	w.Header().Set("Allow", allow)
	writeError(w, http.StatusMethodNotAllowed, "method not allowed; want "+allow)
}

// maxRequestBody bounds what a client may send. Every body this agent
// accepts is a small JSON object; the largest legitimate one is a clipboard
// write, and 1 MiB is more text than anyone pastes from a phone.
const maxRequestBody = 1 << 20

func decodeJSON(r *http.Request, v any) error {
	if r.Body == nil {
		return errors.New("a JSON body is required")
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, maxRequestBody)).Decode(v); err != nil {
		return errors.New("invalid JSON body: " + err.Error())
	}
	return nil
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	// Every reading is new; a cached one is a stale dashboard.
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(v)
}

// writeError is the one error shape the contract promises: {"error": "..."}.
// http.Error's text/plain body would make a phone's JSON decoder throw on
// exactly the responses it most needs to render.
func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}
