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
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/VitruvianSoftware/vitruvian-core/mobile/android/remote/macagent/metrics"
)

// The v1.2 surface, pinned without running gh, kubectl or screencapture.
//
// The actions are covered by their ARGV rather than by running them: a test
// that really approved a PR or synced an ArgoCD app would be a test that
// changes the world every time CI runs it, which is not a test.

func TestPRActionArgvIsFixed(t *testing.T) {
	for _, tc := range []struct {
		action string
		want   []string
	}{
		{"approve", []string{"pr", "review", "2226", "--repo", "VitruvianSoftware/vitruvian-core", "--approve"}},
		{"merge", []string{"pr", "merge", "2226", "--repo", "VitruvianSoftware/vitruvian-core", "--merge"}},
		{"auto_merge", []string{"pr", "merge", "2226", "--repo", "VitruvianSoftware/vitruvian-core", "--auto", "--merge"}},
		{"ready", []string{"pr", "ready", "2226", "--repo", "VitruvianSoftware/vitruvian-core"}},
	} {
		got, err := prActionArgv(tc.action, "VitruvianSoftware/vitruvian-core", 2226)
		if err != nil {
			t.Fatalf("%s: %v", tc.action, err)
		}
		if strings.Join(got, "\x00") != strings.Join(tc.want, "\x00") {
			t.Errorf("%s:\n got %v\nwant %v", tc.action, got, tc.want)
		}
	}
	// Anything else is an error, not a gh invocation nobody predicted.
	if _, err := prActionArgv("close", "o/r", 1); err == nil {
		t.Error("an unknown action must be refused")
	}
	// A repo that looks like a flag is still one argument, so gh reads it as
	// a value it cannot find rather than as an option.
	got, _ := prActionArgv("merge", "--admin", 1)
	if got[3] != "--repo" || got[4] != "--admin" {
		t.Errorf("a repo must stay one argument: %v", got)
	}
}

func TestArgoSyncArgvCarriesTheClusterFlags(t *testing.T) {
	got := argoSyncArgv("/Users/james/.kube/cluster.yaml", "default", "argocd", "cnpg-operator")
	want := []string{
		"--kubeconfig", "/Users/james/.kube/cluster.yaml", "--context", "default",
		"-n", "argocd", "patch", "application", "cnpg-operator", "--type", "merge",
		"-p", `{"operation":{"initiatedBy":{"username":"vitruvian-remote"},"sync":{}}}`,
	}
	if strings.Join(got, "\x00") != strings.Join(want, "\x00") {
		t.Errorf("\n got %v\nwant %v", got, want)
	}
	// Without a kubeconfig the flag is absent entirely rather than empty:
	// `kubectl --kubeconfig ""` is an error, not "use the default".
	got = argoSyncArgv("", "default", "argocd", "x")
	if got[0] != "--context" {
		t.Errorf("an empty kubeconfig must not become an empty flag: %v", got)
	}
}

func TestGhArgvAsksForTheFieldsTheParserReads(t *testing.T) {
	view := strings.Join(ghViewArgv("o/r", 12), " ")
	for _, field := range []string{"isDraft", "headRefName", "baseRefName", "mergeStateStatus", "reviewDecision", "statusCheckRollup", "autoMergeRequest", "author"} {
		if !strings.Contains(view, field) {
			t.Errorf("gh pr view does not ask for %s: %s", field, view)
		}
	}
	// A field the parser needs but the argv does not request is a silent
	// zero, which is exactly the failure this pins.
	search := strings.Join(ghSearchArgv("@me"), " ")
	for _, field := range []string{"number", "repository", "title", "url", "updatedAt"} {
		if !strings.Contains(search, field) {
			t.Errorf("gh search does not ask for %s: %s", field, search)
		}
	}
	if !strings.Contains(strings.Join(ghSearchRepoArgv("o/r"), " "), "--repo o/r") {
		t.Error("the extra-repo search must scope to the repo")
	}
}

func TestResumeArgvPassesTheSessionIDAsAValue(t *testing.T) {
	got := resumeArgv("b4d0359c-d7e1-4db0-8960-536873764a56", "carry on")
	want := []string{"claude", "--resume", "b4d0359c-d7e1-4db0-8960-536873764a56", "-p", "carry on", "--output-format", "text"}
	if strings.Join(got, "\x00") != strings.Join(want, "\x00") {
		t.Errorf("\n got %v\nwant %v", got, want)
	}
}

func TestClaudeResumeRequiresBothFields(t *testing.T) {
	_, store, srv := newTestAgent(t)
	tok := pairedToken(t, store)
	for _, body := range []string{`{"prompt":"go on"}`, `{"session_id":"abc"}`, `{}`} {
		req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/claude/resume", strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tok)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("%s: got %d, want 400", body, resp.StatusCode)
		}
	}
}

func TestV12ActEndpointsRefuseAnUnpairedCaller(t *testing.T) {
	_, _, srv := newTestAgent(t)
	for _, c := range []struct{ method, path string }{
		{http.MethodPost, "/v1/exec/stream"},
		{http.MethodPost, "/v1/claude/resume"},
		{http.MethodPost, "/v1/prs/action"},
		{http.MethodPost, "/v1/argocd/sync"},
		{http.MethodPost, "/v1/notify/test"},
		// A screenshot is a GET and still an act: it is a picture of
		// whatever is on the screen.
		{http.MethodGet, "/v1/screen"},
	} {
		req, _ := http.NewRequest(c.method, srv.URL+c.path, strings.NewReader(`{}`))
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("%s %s: got %d, want 401", c.method, c.path, resp.StatusCode)
		}
	}
}

func TestV12ReadEndpointsNeedNoToken(t *testing.T) {
	s, _, srv := newTestAgent(t)
	s.mu.Lock()
	s.claude = metrics.ClaudeSessions{Sessions: []metrics.ClaudeSession{{
		SessionID: "b4d0359c", Project: "/Users/james/core", State: metrics.StateWaitingForPermission, LastTool: "Bash",
	}}}
	s.prs = metrics.PRs{Available: true, PRs: []metrics.PR{{Repo: "o/r", Number: 1, Checks: metrics.Checks{Success: 26, Skipped: 19}}}}
	s.argo = metrics.ArgoApps{Available: true, Apps: []metrics.ArgoApp{{Name: "cnpg-operator", Sync: "Synced"}}}
	s.mu.Unlock()

	for path, want := range map[string]string{
		"/v1/claude/sessions": `"state":"waiting_for_permission"`,
		"/v1/prs":             `"success":26`,
		"/v1/argocd":          `"name":"cnpg-operator"`,
	} {
		resp, err := http.Get(srv.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		var buf [4096]byte
		n, _ := resp.Body.Read(buf[:])
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Errorf("%s: got %d", path, resp.StatusCode)
		}
		if got := string(buf[:n]); !contains(got, want) {
			t.Errorf("%s: %s does not contain %s", path, got, want)
		}
	}
}

// TestScreenSuccessPathWithAnInjectedCapture is how the happy path is tested
// at all: on a Mac where Screen Recording has not been granted to this
// binary -- which is every Mac until someone opens System Settings, and every
// CI runner forever -- the real capture cannot succeed. The handler's own
// logic (bounds, caching, headers) is what is worth pinning, so the capture
// itself is injected.
func TestScreenSuccessPathWithAnInjectedCapture(t *testing.T) {
	s := NewSampler(time.Second, "", "", nil, nil)
	store := NewStore(t.TempDir())
	if _, err := store.EnsureToken(); err != nil {
		t.Fatal(err)
	}
	mux := newMux(s, store, "", "")
	// newMux built the server; reach the same instance back out of the
	// handler by rebuilding it with the capture replaced.
	var calls atomic.Int32
	var lastWidth atomic.Int32
	srvObj := &server{sampler: s, store: store, capture: func(ctx context.Context, width int) ([]byte, error) {
		calls.Add(1)
		lastWidth.Store(int32(width))
		return []byte{0xFF, 0xD8, 0xFF, 0xE0, 'j', 'p', 'g'}, nil
	}}
	mux = http.NewServeMux()
	mux.HandleFunc("/v1/screen", getOnly(srvObj.act(srvObj.screen)))
	ts := httptest.NewServer(mux)
	defer ts.Close()
	tok := pairedToken(t, store)

	get := func(q string) *http.Response {
		req, _ := http.NewRequest(http.MethodGet, ts.URL+"/v1/screen"+q, nil)
		req.Header.Set("Authorization", "Bearer "+tok)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		return resp
	}

	resp := get("?width=1000")
	body := make([]byte, 16)
	n, _ := resp.Body.Read(body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("got %d", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "image/jpeg" {
		t.Errorf("Content-Type = %q", ct)
	}
	// no-store on a screenshot is not a freshness nicety.
	if cc := resp.Header.Get("Cache-Control"); cc != "no-store" {
		t.Errorf("Cache-Control = %q", cc)
	}
	if n != 7 {
		t.Errorf("body was %d bytes", n)
	}
	if lastWidth.Load() != 1000 {
		t.Errorf("width = %d", lastWidth.Load())
	}

	// The two-second cache: a second request at the same width does not run
	// the capture again. This is what keeps a thumb on a refreshing
	// thumbnail from running screencapture ten times a second.
	get("?width=1000").Body.Close()
	if calls.Load() != 1 {
		t.Errorf("the cache did not hold: %d captures", calls.Load())
	}
	// A different width must NOT be served from it, or a full-size peek
	// comes back as the thumbnail.
	get("?width=400").Body.Close()
	if calls.Load() != 2 {
		t.Errorf("a different width was served from the cache: %d captures", calls.Load())
	}

	// Bounds are clamped, not rejected -- except for a non-number, which is
	// a caller bug worth naming.
	get("?width=99999").Body.Close()
	if lastWidth.Load() != maxScreenWidth {
		t.Errorf("width was not clamped: %d", lastWidth.Load())
	}
	get("?width=1").Body.Close()
	if lastWidth.Load() != minScreenWidth {
		t.Errorf("width was not clamped up: %d", lastWidth.Load())
	}
	resp = get("?width=wide")
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("a non-numeric width: got %d, want 400", resp.StatusCode)
	}
}

// The refusal path, which on this Mac is the REAL one. The reason must be
// the contract's exact sentence, because the phone shows it verbatim and it
// is the only thing that tells someone which pane to open.
func TestScreenDeniedIsA503WithTheDocumentedReason(t *testing.T) {
	s := NewSampler(time.Second, "", "", nil, nil)
	store := NewStore(t.TempDir())
	if _, err := store.EnsureToken(); err != nil {
		t.Fatal(err)
	}
	srvObj := &server{sampler: s, store: store, capture: func(ctx context.Context, width int) ([]byte, error) {
		return nil, errScreenRecordingDenied
	}}
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/screen", getOnly(srvObj.act(srvObj.screen)))
	ts := httptest.NewServer(mux)
	defer ts.Close()

	req, _ := http.NewRequest(http.MethodGet, ts.URL+"/v1/screen", nil)
	req.Header.Set("Authorization", "Bearer "+pairedToken(t, store))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("got %d, want 503", resp.StatusCode)
	}
	var got map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatalf("the refusal must be JSON: %v", err)
	}
	if got["available"] != false {
		t.Errorf("available = %v", got["available"])
	}
	if got["reason"] != screenDeniedReason {
		t.Errorf("reason = %q\nwant  %q", got["reason"], screenDeniedReason)
	}
	if !strings.Contains(screenDeniedReason, "System Settings") {
		t.Error("the reason must name where to fix it")
	}
}

// The exact string macOS 26 produced on this machine, where Screen Recording
// is not granted to the agent binary. Captured by running the real command:
//
//	$ screencapture -x -t jpg /tmp/x.jpg
//	could not create image from display <exit 1>
//
// Without this mapping the endpoint answered 500 with screencapture's line
// and no next step, which is the failure this test pins shut.
func TestIsScreenDeniedRecognisesTheRealRefusal(t *testing.T) {
	if !isScreenDenied("could not create image from display\n") {
		t.Error("the real macOS 26 refusal was not recognised")
	}
	if !isScreenDenied("screencapture: not authorized to capture the screen") {
		t.Error("the older wording was not recognised")
	}
	// A different failure must NOT be reported as a permission problem: it
	// would send someone to the wrong pane in System Settings.
	if isScreenDenied("screencapture: cannot write file to /tmp: No space left on device") {
		t.Error("a disk-full failure was misreported as a permission problem")
	}
	if isScreenDenied("") {
		t.Error("an empty stderr is not evidence of a refusal")
	}
}

func TestNotifyTestSaysSoWhenUnconfigured(t *testing.T) {
	_, store, srv := newTestAgent(t)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/notify/test", strings.NewReader(`{}`))
	req.Header.Set("Authorization", "Bearer "+pairedToken(t, store))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("got %d, want 400", resp.StatusCode)
	}
	var got map[string]string
	_ = json.NewDecoder(resp.Body).Decode(&got)
	// Naming the flags is the point: the fix is a restart with two
	// arguments, and "unavailable" would send someone to the log.
	if !strings.Contains(got["error"], "--ntfy-url") {
		t.Errorf("the reason must name the flags: %q", got["error"])
	}
}

func TestHealthzReportsNotifyConfiguration(t *testing.T) {
	// Unconfigured.
	_, _, srv := newTestAgent(t)
	resp, err := http.Get(srv.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	var body map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&body)
	resp.Body.Close()
	n, ok := body["notify"].(map[string]any)
	if !ok {
		t.Fatalf("healthz has no notify block: %v", body)
	}
	if n["configured"] != false || n["topic"] != "" {
		t.Errorf("notify = %v", n)
	}

	// Configured: the topic is reported (it is not a credential) and the
	// token is nowhere in the response.
	s := NewSampler(time.Second, "", "", nil, NewNotifier("https://ntfy.example", "vitruvian-remote", "s3cr3t"))
	store := NewStore(t.TempDir())
	if _, err := store.EnsureToken(); err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(newMux(s, store, "", ""))
	defer ts.Close()
	resp, err = http.Get(ts.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	raw := make([]byte, 2048)
	rn, _ := resp.Body.Read(raw)
	resp.Body.Close()
	text := string(raw[:rn])
	if !contains(text, `"configured":true`) || !contains(text, `"topic":"vitruvian-remote"`) {
		t.Errorf("healthz notify block: %s", text)
	}
	if contains(text, "s3cr3t") {
		t.Errorf("the ntfy token leaked into /healthz: %s", text)
	}
}

func TestSplitReposDropsEmpties(t *testing.T) {
	got := splitRepos(" a/b , , c/d ,")
	if len(got) != 2 || got[0] != "a/b" || got[1] != "c/d" {
		t.Errorf("got %v", got)
	}
	// An empty flag must be no repos, not one empty repo: `gh search --repo
	// ""` is an error gh would report once a minute forever.
	if got := splitRepos(""); len(got) != 0 {
		t.Errorf("empty flag gave %v", got)
	}
}

func TestSessionNotificationsFireOnTransitionsOnly(t *testing.T) {
	f := &fakeNtfy{}
	up := httptest.NewServer(f.handler())
	defer up.Close()
	s := NewSampler(time.Second, "", "", nil, NewNotifier(up.URL, "topic", ""))
	ctx := context.Background()

	waiting := metrics.ClaudeSessions{Sessions: []metrics.ClaudeSession{{
		SessionID: "abc", Project: "/Users/james/core", State: metrics.StateWaitingForPermission, LastTool: "Bash",
	}}}
	s.notifySessionTransitions(ctx, waiting)
	if f.count() != 1 {
		t.Fatalf("entering waiting_for_permission sent %d", f.count())
	}
	if got := f.last().headers.Get("Title"); got != "Claude Code is waiting" {
		t.Errorf("title = %q", got)
	}
	// The project is the LAST path segment, not the whole path: a phone
	// notification has room for "core", not for six directories.
	if got := f.last().body; got != "core · Bash" {
		t.Errorf("body = %q", got)
	}

	// Still waiting on the next tick: not news, and the debounce is not what
	// stops it -- the state did not change.
	s.notifySessionTransitions(ctx, waiting)
	if f.count() != 1 {
		t.Errorf("an unchanged state sent again: %d", f.count())
	}

	// working -> idle is the "finished a turn" notification.
	working := metrics.ClaudeSessions{Sessions: []metrics.ClaudeSession{{SessionID: "abc", Project: "/Users/james/core", State: metrics.StateWorking}}}
	s.notifySessionTransitions(ctx, working)
	idle := metrics.ClaudeSessions{Sessions: []metrics.ClaudeSession{{SessionID: "abc", Project: "/Users/james/core", State: metrics.StateIdle, LastText: "All four gates are green."}}}
	s.notifySessionTransitions(ctx, idle)
	if f.count() != 2 {
		t.Fatalf("working -> idle sent %d in total", f.count())
	}
	if got := f.last().headers.Get("Title"); got != "Claude Code finished a turn" {
		t.Errorf("title = %q", got)
	}

	// A session first SEEN idle is not announced. Otherwise every restart
	// would fire one notification per finished session on the first tick.
	s2 := NewSampler(time.Second, "", "", nil, NewNotifier(up.URL, "topic", ""))
	before := f.count()
	s2.notifySessionTransitions(ctx, idle)
	if f.count() != before {
		t.Error("a session first seen idle was announced")
	}
}

func TestPRNotificationsFireOnVerdictChangesOnly(t *testing.T) {
	f := &fakeNtfy{}
	up := httptest.NewServer(f.handler())
	defer up.Close()
	s := NewSampler(time.Second, "", "", nil, NewNotifier(up.URL, "topic", ""))
	ctx := context.Background()

	pending := metrics.PRs{Available: true, PRs: []metrics.PR{{Repo: "o/r", Number: 7, Title: "a change", Checks: metrics.Checks{Success: 3, Pending: 1}}}}
	green := metrics.PRs{Available: true, PRs: []metrics.PR{{Repo: "o/r", Number: 7, Title: "a change", Checks: metrics.Checks{Success: 4}}}}
	red := metrics.PRs{Available: true, PRs: []metrics.PR{{Repo: "o/r", Number: 7, Title: "a change", Checks: metrics.Checks{Success: 3, Failure: 1}}}}

	// First sight, still running: nothing.
	s.notifyPRTransitions(ctx, pending)
	if f.count() != 0 {
		t.Fatalf("a pending PR was announced: %d", f.count())
	}
	// Settles green: one notification.
	s.notifyPRTransitions(ctx, green)
	if f.count() != 1 {
		t.Fatalf("going green sent %d", f.count())
	}
	if got := f.last().headers.Get("Title"); got != "PR #7 checks green" {
		t.Errorf("title = %q", got)
	}
	// Still green: not news.
	s.notifyPRTransitions(ctx, green)
	if f.count() != 1 {
		t.Errorf("an unchanged verdict sent again: %d", f.count())
	}
	// Goes red: news again, and at high priority.
	s.notifyPRTransitions(ctx, red)
	if f.count() != 2 {
		t.Fatalf("going red sent %d in total", f.count())
	}
	if got := f.last().headers.Get("Priority"); got != "high" {
		t.Errorf("a failing PR should be high priority, got %q", got)
	}

	// A PR settled the first time it is EVER seen is not announced: after a
	// restart that would be one notification per open PR.
	s2 := NewSampler(time.Second, "", "", nil, NewNotifier(up.URL, "topic", ""))
	before := f.count()
	s2.notifyPRTransitions(ctx, green)
	if f.count() != before {
		t.Error("a PR first seen green was announced")
	}
}

func TestReadTailReadsOnlyTheEnd(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/t.jsonl"
	// A file bigger than the window. Reading it whole every five seconds is
	// the load this seek exists to avoid.
	big := strings.Repeat("x", transcriptTail) + "\nTHE-END\n"
	if err := writeFileForTest(path, big); err != nil {
		t.Fatal(err)
	}
	got := readTail(path, transcriptTail)
	if int64(len(got)) > transcriptTail {
		t.Errorf("read %d bytes, want at most %d", len(got), transcriptTail)
	}
	if !strings.Contains(got, "THE-END") {
		t.Error("the tail must be the END of the file")
	}
	// A short file comes back whole, and a missing one is "" rather than a
	// crash in a sampler goroutine.
	if err := writeFileForTest(dir+"/s.jsonl", "small\n"); err != nil {
		t.Fatal(err)
	}
	if readTail(dir+"/s.jsonl", transcriptTail) != "small\n" {
		t.Error("a short file must come back whole")
	}
	if readTail(dir+"/nope.jsonl", transcriptTail) != "" {
		t.Error("a missing file must be empty, not a panic")
	}
}

func writeFileForTest(path, content string) error {
	return os.WriteFile(path, []byte(content), 0o600)
}
