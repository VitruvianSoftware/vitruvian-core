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
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
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

	// capture is how GET /v1/screen takes a picture. A field rather than a
	// direct call so a test can inject one: the real path needs Screen
	// Recording granted to the agent binary by a person in System Settings,
	// which no CI runner and no unit test can arrange.
	capture func(ctx context.Context, width int) ([]byte, error)

	// phone is the v1.3 bridge: the single outbound link the phone holds
	// open, and the calls waiting on it. Always non-nil -- "no phone" is a
	// state of the bridge, not a nil check at every call site.
	phone *phoneBridge

	// screen caches the last capture for screenCacheTTL, so a thumb resting
	// on a refreshing thumbnail does not run screencapture ten times a
	// second.
	screenMu   sync.Mutex
	screenAt   time.Time
	screenPX   int
	screenJPEG []byte
}

// screenCacheTTL is the contract's two seconds.
const screenCacheTTL = 2 * time.Second

func newMux(s *Sampler, store *Store, promURL string, promToken string) *http.ServeMux {
	srv := &server{
		sampler:   s,
		store:     store,
		promURL:   strings.TrimRight(promURL, "/"),
		promToken: promToken,
		capture:   screenshotJPEG,
		phone:     newPhoneBridge(),
	}
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
	mux.HandleFunc("/v1/tools", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Tools())
	}))
	mux.HandleFunc("/v1/antigravity", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.Antigravity())
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

	// --- v1.2 read ---
	// The Claude session list, the PR list and the ArgoCD app list are all
	// READ: each is something anyone at this Mac's keyboard already sees, in
	// a terminal or a browser tab that is already logged in.
	mux.HandleFunc("/v1/claude/sessions", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.ClaudeSessions())
	}))
	mux.HandleFunc("/v1/prs", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.PRs())
	}))
	mux.HandleFunc("/v1/argocd", getOnly(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, s.ArgoCD())
	}))

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

	// --- v1.2 act ---
	// Each wrapped one at a time, on purpose: see the note at the top of the
	// file about why there is no "everything under this prefix" rule.
	mux.HandleFunc("/v1/exec/stream", postOnly(srv.act(srv.execStream)))
	mux.HandleFunc("/v1/claude/resume", postOnly(srv.act(srv.claudeResume)))
	mux.HandleFunc("/v1/prs/action", postOnly(srv.act(srv.prAction)))
	mux.HandleFunc("/v1/argocd/sync", postOnly(srv.act(srv.argoSync)))
	mux.HandleFunc("/v1/notify/test", postOnly(srv.act(srv.notifyTest)))
	// A screenshot is as sensitive as the clipboard and is an act for the
	// same reason, GET or not: it is a picture of whatever is on the screen,
	// which is not what Activity Monitor shows anyone.
	mux.HandleFunc("/v1/screen", getOnly(srv.act(srv.screen)))

	// --- v1.3: the phone bridge ---
	// The link and the results are ACT: they are how the phone offers the
	// Mac a way to run things on it, which is the same trust direction as
	// /v1/exec pointed the other way. The status is READ: it says whether a
	// link exists and which tools it named, and nothing more.
	mux.HandleFunc("/v1/phone/link", postOnly(srv.act(srv.phoneLink)))
	mux.HandleFunc("/v1/phone/result", postOnly(srv.act(srv.phoneResultHandler)))
	mux.HandleFunc("/v1/phone", getOnly(srv.phoneStatus))
	// Not wrapped in act(): the MCP endpoint has its own token and its own
	// loopback rule, both inside the handler. See mcp.go for why they are
	// different from the pairing token's.
	mux.HandleFunc("/mcp/phone", srv.mcpPhone)
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
		// v1.2. The topic is not a credential and the token is never in
		// here: someone debugging "why do I get no notifications" needs to
		// see which topic the agent is publishing to, and that is all.
		"notify": map[string]any{
			"configured": srv.sampler.Notifier().Configured(),
			"topic":      srv.sampler.Notifier().Topic(),
		},
	})
}

// claudeResume is POST /v1/claude/resume: pick a session up where it stopped.
//
// It runs through runAct like every other exec, so it inherits the timeout,
// the output cap and the act log. The session id goes in as its own argument
// after --resume, which is what makes it a value rather than a command.
func (srv *server) claudeResume(w http.ResponseWriter, r *http.Request) {
	var body struct {
		SessionID string `json:"session_id"`
		Prompt    string `json:"prompt"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if strings.TrimSpace(body.SessionID) == "" || strings.TrimSpace(body.Prompt) == "" {
		writeError(w, http.StatusBadRequest, "session_id and prompt are required")
		return
	}
	logAct("claude-resume", body.SessionID+": "+body.Prompt)
	writeJSON(w, runArgv(r.Context(), resumeArgv(body.SessionID, body.Prompt), claudeResumeTimeoutSec*time.Second))
}

// prAction is POST /v1/prs/action. The four verbs in the contract and
// nothing else: prActionArgv turns an unknown one into an error, which is a
// 400 here rather than a gh invocation nobody predicted.
func (srv *server) prAction(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Repo   string `json:"repo"`
		Number int    `json:"number"`
		Action string `json:"action"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if strings.TrimSpace(body.Repo) == "" || body.Number <= 0 {
		writeError(w, http.StatusBadRequest, "repo and a positive number are required")
		return
	}
	args, err := prActionArgv(body.Action, body.Repo, body.Number)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	logAct("pr", body.Action+" "+body.Repo+"#"+strconv.Itoa(body.Number))
	stdout, stderr, err := runToolWithin(r.Context(), 60*time.Second, "gh", args...)
	// gh writes its confirmations to stderr and its data to stdout, so the
	// reply carries both: "Merged pull request #2226" is on stderr, and a
	// phone that only showed stdout would report a successful merge as
	// nothing at all.
	out := strings.TrimSpace(strings.TrimSpace(stdout) + "\n" + strings.TrimSpace(stderr))
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "output": strings.TrimSpace(out + "\n" + err.Error())})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "output": out})
}

// argoSync is POST /v1/argocd/sync: ask the ArgoCD controller to reconcile
// one Application now.
//
// A kubectl patch rather than the argocd CLI, which would need its own login
// and a session token this agent has no way to obtain. The patch is the same
// thing the ArgoCD UI's Sync button writes.
func (srv *server) argoSync(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Name      string `json:"name"`
		Namespace string `json:"namespace"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if strings.TrimSpace(body.Name) == "" || strings.TrimSpace(body.Namespace) == "" {
		writeError(w, http.StatusBadRequest, "name and namespace are required")
		return
	}
	if srv.sampler.kubeContext == "" {
		writeError(w, http.StatusBadRequest, notConfiguredKube)
		return
	}
	logAct("argocd", "sync "+body.Namespace+"/"+body.Name)
	args := argoSyncArgv(srv.sampler.kubeconfig, srv.sampler.kubeContext, body.Namespace, body.Name)
	stdout, stderr, err := runToolWithin(r.Context(), 30*time.Second, "kubectl", args...)
	out := strings.TrimSpace(strings.TrimSpace(stdout) + "\n" + strings.TrimSpace(stderr))
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "output": strings.TrimSpace(out + "\n" + err.Error())})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "output": out})
}

// notifyTest is POST /v1/notify/test: prove the push path end to end.
//
// It bypasses the debounce by using a key that changes every time -- the
// point of a test button is that pressing it twice sends twice, and a second
// press that silently did nothing would be read as a broken configuration.
func (srv *server) notifyTest(w http.ResponseWriter, r *http.Request) {
	n := srv.sampler.Notifier()
	if !n.Configured() {
		writeError(w, http.StatusBadRequest, errNotifyNotConfigured.Error())
		return
	}
	logAct("notify", "test")
	key := "notify:test:" + strconv.FormatInt(time.Now().UnixNano(), 10)
	if err := n.Publish(r.Context(), key, "Test from Vitruvian Remote",
		"If this arrived, notifications work.", "default", "bell", "vitruvian-remote://mac"); err != nil {
		// 502, not 500: the agent is fine and ntfy is not, and the phone
		// should say which.
		writeError(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, map[string]any{"ok": true, "topic": n.Topic()})
}

// screen is GET /v1/screen: a JPEG of the main display.
//
// The 503 is the interesting reply. Screen Recording is a permission a person
// grants to a specific BINARY in System Settings, and an agent installed by
// `bazel run :install` has never been granted it -- so the honest first
// answer for most installs is the refusal, with the exact pane to open. An
// empty image or a black rectangle would be worse than an error.
func (srv *server) screen(w http.ResponseWriter, r *http.Request) {
	width := defaultScreenWidth
	if q := r.URL.Query().Get("width"); q != "" {
		n, err := strconv.Atoi(q)
		if err != nil {
			writeError(w, http.StatusBadRequest, "width must be a number between 200 and 1600")
			return
		}
		width = n
	}
	if width < minScreenWidth {
		width = minScreenWidth
	}
	if width > maxScreenWidth {
		width = maxScreenWidth
	}
	logAct("screen", "capture width "+strconv.Itoa(width))

	srv.screenMu.Lock()
	defer srv.screenMu.Unlock()
	// The cache is keyed on width as well as age: a client that switched
	// from a thumbnail to a full-size peek must not be handed the thumbnail.
	if srv.screenJPEG != nil && srv.screenPX == width && time.Since(srv.screenAt) < screenCacheTTL {
		writeJPEG(w, srv.screenJPEG)
		return
	}
	img, err := srv.capture(r.Context(), width)
	if err != nil {
		if errors.Is(err, errScreenRecordingDenied) {
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("Cache-Control", "no-store")
			w.WriteHeader(http.StatusServiceUnavailable)
			_ = json.NewEncoder(w).Encode(map[string]any{"available": false, "reason": screenDeniedReason})
			return
		}
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	srv.screenJPEG, srv.screenPX, srv.screenAt = img, width, time.Now()
	writeJPEG(w, img)
}

func writeJPEG(w http.ResponseWriter, b []byte) {
	w.Header().Set("Content-Type", "image/jpeg")
	// no-store on a screenshot is not a freshness nicety: it is the
	// difference between a picture of someone's screen living in a proxy
	// cache and not.
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Content-Length", strconv.Itoa(len(b)))
	_, _ = w.Write(b)
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
	// Bounded, and bounded HONESTLY: the first version cut the body at the
	// cap, which turned a large result into invalid JSON that the phone
	// could only report as "unterminated string at character 65536". Read
	// one byte past the cap to know it overflowed, and say so instead.
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxOutput+1))
	if err != nil {
		writeError(w, http.StatusBadGateway, "prometheus: "+err.Error())
		return
	}
	if len(body) > maxOutput {
		writeJSON(w, map[string]any{
			"available": false,
			"reason":    fmt.Sprintf("result larger than %d KiB; narrow the query (fewer series, or a label filter)", maxOutput/1024),
		})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(resp.StatusCode)
	_, _ = w.Write(body)
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
