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
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// v1.7, pinned without agy. The summaries database is built by the test with
// agy's own schema (as measured on agy 1.2.11), the resume runner is a fake
// that records what it was asked to run, and hooks.json is a temp file.

const agyTestHookCommand = "/opt/test/vitruvian-remote-agent agy-permission-hook"

// The conversation_summaries schema, copied from agy 1.2.11's database.
const agySchema = "CREATE TABLE `conversation_summaries` (`conversation_id` text,`title` text NOT NULL DEFAULT \"\",`preview` text NOT NULL DEFAULT \"\",`step_count` integer NOT NULL DEFAULT 0,`last_modified_time` datetime NOT NULL,`workspace_uris` text NOT NULL,`status` text NOT NULL DEFAULT \"\",`source` text NOT NULL DEFAULT \"\",`project_id` text NOT NULL DEFAULT \"\",`agent_name` text NOT NULL DEFAULT \"\",`parent_conversation_id` text NOT NULL DEFAULT \"\",`nesting_depth` integer NOT NULL DEFAULT 0,`battle_id` text NOT NULL DEFAULT \"\",`winning_conversation_id` text NOT NULL DEFAULT \"\",`not_fully_idle` numeric NOT NULL DEFAULT false,`killed` numeric NOT NULL DEFAULT false,`last_user_input_time` datetime NOT NULL,`last_user_input_step_index` integer NOT NULL DEFAULT -1,`app_data_dir` text NOT NULL DEFAULT \"\", raw_summary BLOB, group_id TEXT NOT NULL DEFAULT '',PRIMARY KEY (`conversation_id`));"

// Four conversations, one per state the database alone can produce.
const (
	agyIdle    = "11111111-1111-4111-8111-111111111111"
	agyWorking = "22222222-2222-4222-8222-222222222222"
	agyKilled  = "33333333-3333-4333-8333-333333333333"
	agyBusy    = "44444444-4444-4444-8444-444444444444" // IDLE status, not_fully_idle
)

// requireSQLite skips when the sqlite3 CLI is missing -- it ships with macOS
// and the runner images, so a skip here is a runner problem worth seeing.
func requireSQLite(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("sqlite3"); err != nil {
		t.Skip("SKIPPED: sqlite3 not on PATH; the database round trip is not covered on this runner")
	}
}

// makeAgyDB writes a summaries database whose first two conversations live in
// workspace (a directory the test controls) and the rest in a path that does
// not exist on the test machine.
func makeAgyDB(t *testing.T, workspace string) string {
	t.Helper()
	requireSQLite(t)
	db := filepath.Join(t.TempDir(), "conversation_summaries.db")
	ws := `["file://` + workspace + `"]`
	gone := `["file:///Users/alice/src/acme","file:///Users/alice/src/other"]`
	rows := []string{
		fmt.Sprintf(`('%s','Fix the build','Run the tests',7,'2026-09-26 02:23:19.452133+00:00','%s','CASCADE_RUN_STATUS_IDLE',0,0,'2026-09-26 02:23:19+00:00')`, agyIdle, ws),
		fmt.Sprintf(`('%s','Refactor','Split the file',3,'2026-09-26 02:25:00.000001+00:00','%s','CASCADE_RUN_STATUS_RUNNING',0,0,'2026-09-26 02:25:00+00:00')`, agyWorking, ws),
		fmt.Sprintf(`('%s','Old one','',1,'2026-09-25 10:00:00+00:00','%s','CASCADE_RUN_STATUS_IDLE',0,1,'2026-09-25 10:00:00+00:00')`, agyKilled, gone),
		fmt.Sprintf(`('%s','Busy','',2,'2026-09-24 10:00:00+00:00','%s','CASCADE_RUN_STATUS_IDLE',1,0,'2026-09-24 10:00:00+00:00')`, agyBusy, gone),
	}
	sql := agySchema + "INSERT INTO conversation_summaries (conversation_id,title,preview,step_count,last_modified_time,workspace_uris,status,not_fully_idle,killed,last_user_input_time) VALUES " + strings.Join(rows, ",") + ";"
	if out, err := exec.Command("sqlite3", db, sql).CombinedOutput(); err != nil {
		t.Fatalf("sqlite3: %v\n%s", err, out)
	}
	return db
}

// agyCall is one recorded resume.
type agyCall struct {
	argv []string
	dir  string
}

type agyAgent struct {
	*permAgent
	mu    sync.Mutex
	calls []agyCall
}

func (a *agyAgent) recorded() []agyCall {
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]agyCall(nil), a.calls...)
}

// newAgyAgent is newPermAgent plus the v1.7 routes, with the database at db,
// hooks.json in a temp dir, and a fake runner that prints one line and exits 0.
func newAgyAgent(t *testing.T, wait time.Duration, db string) *agyAgent {
	t.Helper()
	store := NewStore(t.TempDir())
	act, err := store.EnsureToken()
	if err != nil {
		t.Fatal(err)
	}
	hook, err := store.EnsureHookToken()
	if err != nil {
		t.Fatal(err)
	}
	a := &agyAgent{}
	srv := &server{
		sampler:        NewSampler(time.Second, "", "", nil, nil),
		store:          store,
		perms:          newPermissionBroker(),
		permissionWait: wait,
		claudeSettings: filepath.Join(t.TempDir(), "settings.json"),
		hookCommand:    testHookCommand,
		agySummaries:   db,
		agyHooks:       filepath.Join(t.TempDir(), "hooks.json"),
		agyHookCommand: agyTestHookCommand,
		agyStream: func(ctx context.Context, argv []string, dir string, lines chan<- streamLine) (int, time.Duration) {
			defer close(lines)
			a.mu.Lock()
			a.calls = append(a.calls, agyCall{argv: argv, dir: dir})
			a.mu.Unlock()
			lines <- streamLine{Stream: "stdout", Text: "done"}
			return 0, time.Millisecond
		},
	}
	mux := http.NewServeMux()
	srv.permissionRoutes(mux)
	srv.antigravityRoutes(mux)
	hs := httptest.NewServer(mux)
	t.Cleanup(hs.Close)
	a.permAgent = &permAgent{srv: srv, http: hs, actTok: act, hookTok: hook, settings: srv.claudeSettings}
	return a
}

// park puts an Antigravity prompt for conversation id in the queue directly.
func (a *agyAgent) park(t *testing.T, id string) {
	t.Helper()
	now := time.Now()
	if _, _, ok := a.srv.perms.add(permissionRequest{Source: sourceAntigravity, SessionID: id, Tool: agyRunCommand, CreatedAt: now, ExpiresAt: now.Add(time.Minute)}); !ok {
		t.Fatal("queue full")
	}
}

// --- sessions ---

func TestAgySessionsFromTheDatabase(t *testing.T) {
	ws := t.TempDir()
	a := newAgyAgent(t, 5*time.Second, makeAgyDB(t, ws))
	a.park(t, agyIdle)

	resp, err := http.Get(a.http.URL + "/v1/antigravity/sessions")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var got agySessionsReply
	if err := json.NewDecoder(resp.Body).Decode(&got); err != nil {
		t.Fatal(err)
	}
	if !got.Available || got.Reason != "" {
		t.Fatalf("available=%v reason=%q", got.Available, got.Reason)
	}
	var ids, states []string
	for _, s := range got.Sessions {
		ids = append(ids, s.ID)
		states = append(states, s.State)
	}
	// Newest first; the parked prompt beats the IDLE status.
	wantIDs := []string{agyWorking, agyIdle, agyKilled, agyBusy}
	wantStates := []string{"working", "waiting_for_permission", "killed", "working"}
	if strings.Join(ids, ",") != strings.Join(wantIDs, ",") {
		t.Errorf("order = %v, want %v", ids, wantIDs)
	}
	if strings.Join(states, ",") != strings.Join(wantStates, ",") {
		t.Errorf("states = %v, want %v", states, wantStates)
	}
	first := got.Sessions[1]
	if first.Title != "Fix the build" || first.Preview != "Run the tests" || first.Steps != 7 ||
		first.Project != filepath.Base(ws) || first.UpdatedAt != "2026-09-26T02:23:19Z" {
		t.Errorf("session = %+v", first)
	}
	if got.Sessions[2].Project != "acme" {
		t.Errorf("project is the FIRST workspace's basename: %+v", got.Sessions[2])
	}
}

func TestAgySessionsWithoutADatabase(t *testing.T) {
	a := newAgyAgent(t, 5*time.Second, filepath.Join(t.TempDir(), "missing.db"))
	resp, err := http.Get(a.http.URL + "/v1/antigravity/sessions")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var got map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&got)
	if got["available"] != false || !strings.Contains(fmt.Sprint(got["reason"]), "missing.db") {
		t.Errorf("reply = %v", got)
	}
	if s, ok := got["sessions"].([]any); !ok || len(s) != 0 {
		t.Errorf("sessions must be [] not null: %v", got["sessions"])
	}
}

// The mapping, without sqlite3: every state, the cap, the boolean encodings
// SQLite may hand back, and a time that does not parse.
func TestAgySessionStateMappingAndCap(t *testing.T) {
	out := []byte(`[
	 {"conversation_id":"a","status":"CASCADE_RUN_STATUS_IDLE","not_fully_idle":0,"killed":0,"last_modified_time":"2026-09-26 02:00:00+00:00","workspace_uris":"[\"file:///Users/alice/src/acme\"]"},
	 {"conversation_id":"b","status":"CASCADE_RUN_STATUS_RUNNING","not_fully_idle":0,"killed":0,"last_modified_time":"2026-09-26 01:00:00+00:00","workspace_uris":"[]"},
	 {"conversation_id":"c","status":"CASCADE_RUN_STATUS_IDLE","not_fully_idle":"true","killed":"false","last_modified_time":"2026-09-26 00:30:00+00:00","workspace_uris":"not json"},
	 {"conversation_id":"d","status":"CASCADE_RUN_STATUS_RUNNING","not_fully_idle":1,"killed":1,"last_modified_time":"2026-09-26 00:00:00+00:00","workspace_uris":"[\"https://example.com\"]"},
	 {"conversation_id":"e","status":"","not_fully_idle":null,"killed":null,"last_modified_time":"yesterday","workspace_uris":""}
	]`)
	rows, err := parseAgyRows(out)
	if err != nil {
		t.Fatal(err)
	}
	got := agySessionsFrom(rows, map[string]bool{"b": true})
	want := map[string]string{"a": "idle", "b": "waiting_for_permission", "c": "working", "d": "killed", "e": "idle"}
	for _, s := range got {
		if s.State != want[s.ID] {
			t.Errorf("%s: state %q, want %q", s.ID, s.State, want[s.ID])
		}
	}
	if got[0].Project != "acme" || got[1].Project != "" || got[3].Project != "" {
		t.Errorf("projects = %q %q %q", got[0].Project, got[1].Project, got[3].Project)
	}
	if got[4].UpdatedAt != "yesterday" {
		t.Errorf("an unparseable time passes through: %q", got[4].UpdatedAt)
	}
	if rows, err := parseAgyRows(nil); err != nil || len(rows) != 0 {
		t.Errorf("no output is no rows: %v %v", rows, err)
	}

	var many []agyRow
	for i := 0; i < 30; i++ {
		many = append(many, agyRow{ConversationID: fmt.Sprint(i), LastModified: fmt.Sprintf("2026-09-26 00:00:%02d+00:00", i)})
	}
	capped := agySessionsFrom(many, nil)
	if len(capped) != agySessionsMax || capped[0].ID != "29" {
		t.Errorf("want the 20 newest, newest first: len %d first %s", len(capped), capped[0].ID)
	}
}

// --- resume ---

// readSSE returns the line texts and the event names of a stream.
func readSSE(t *testing.T, resp *http.Response) (texts, events []string) {
	t.Helper()
	sc := bufio.NewScanner(resp.Body)
	event := ""
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "event: "):
			event = strings.TrimPrefix(line, "event: ")
			events = append(events, event)
		case strings.HasPrefix(line, "data: ") && event == "line":
			var l streamLine
			_ = json.Unmarshal([]byte(strings.TrimPrefix(line, "data: ")), &l)
			texts = append(texts, l.Text)
		}
	}
	return texts, events
}

func (a *agyAgent) resume(t *testing.T, body string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest(http.MethodPost, a.http.URL+"/v1/antigravity/resume", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+a.actTok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	return resp
}

func TestAgyResumeArgvAndWorkingDirectory(t *testing.T) {
	ws := t.TempDir()
	a := newAgyAgent(t, 5*time.Second, makeAgyDB(t, ws))
	oldExec := execDir
	execDir = t.TempDir()
	t.Cleanup(func() { execDir = oldExec })

	for _, tc := range []struct {
		name, body string
		wantArgv   []string
		wantDir    string
	}{
		{
			"known conversation runs in its workspace",
			`{"conversation_id":"` + agyIdle + `","prompt":"carry on"}`,
			[]string{"agy", "-p", "carry on", "--output-format", "text", "--conversation", agyIdle},
			ws,
		},
		{
			"a workspace that no longer exists falls back to --exec-dir",
			`{"conversation_id":"` + agyKilled + `","prompt":"and now?"}`,
			[]string{"agy", "-p", "and now?", "--output-format", "text", "--conversation", agyKilled},
			execDir,
		},
		{
			"an id the database does not know falls back to --exec-dir",
			`{"conversation_id":"99999999-9999-4999-8999-999999999999","prompt":"hi"}`,
			[]string{"agy", "-p", "hi", "--output-format", "text", "--conversation", "99999999-9999-4999-8999-999999999999"},
			execDir,
		},
		{
			"no id starts a new conversation in --exec-dir",
			`{"conversation_id":"","prompt":"start; rm -rf / # stays one argument"}`,
			[]string{"agy", "-p", "start; rm -rf / # stays one argument", "--output-format", "text"},
			execDir,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			before := len(a.recorded())
			resp := a.resume(t, tc.body)
			if resp.StatusCode != http.StatusOK || resp.Header.Get("Content-Type") != "text/event-stream" {
				t.Fatalf("status %d, type %q", resp.StatusCode, resp.Header.Get("Content-Type"))
			}
			texts, events := readSSE(t, resp)
			if strings.Join(texts, "|") != "done" || len(events) == 0 || events[len(events)-1] != "exit" {
				t.Errorf("stream: texts %v events %v", texts, events)
			}
			calls := a.recorded()
			if len(calls) != before+1 {
				t.Fatalf("runner called %d times", len(calls)-before)
			}
			c := calls[len(calls)-1]
			if strings.Join(c.argv, "\x00") != strings.Join(tc.wantArgv, "\x00") {
				t.Errorf("argv = %q, want %q", c.argv, tc.wantArgv)
			}
			if c.dir != tc.wantDir {
				t.Errorf("dir = %q, want %q", c.dir, tc.wantDir)
			}
		})
	}
}

func TestAgyResumeValidatesBeforeRunning(t *testing.T) {
	a := newAgyAgent(t, 5*time.Second, filepath.Join(t.TempDir(), "none.db"))
	for name, body := range map[string]string{
		"id with a quote":  `{"conversation_id":"1111111-1111-4111-8111-111111111111'","prompt":"x"}`,
		"upper-case id":    `{"conversation_id":"AAAAAAAA-1111-4111-8111-111111111111","prompt":"x"}`,
		"short id":         `{"conversation_id":"1234","prompt":"x"}`,
		"flag as an id":    `{"conversation_id":"--dangerously-skip-permissions-xxxxxx","prompt":"x"}`,
		"empty prompt":     `{"conversation_id":"","prompt":"   "}`,
		"missing prompt":   `{"conversation_id":"` + agyIdle + `"}`,
		"prompt over 8KiB": `{"prompt":"` + strings.Repeat("a", agyPromptMaxBytes+1) + `"}`,
		"not JSON":         `nope`,
	} {
		t.Run(name, func(t *testing.T) {
			resp := a.resume(t, body)
			if resp.StatusCode != http.StatusBadRequest {
				t.Errorf("status %d, want 400", resp.StatusCode)
			}
		})
	}
	if n := len(a.recorded()); n != 0 {
		t.Errorf("runner called %d times for invalid requests", n)
	}
	// Exactly at the limit is fine.
	if err := validateAgyResume("", strings.Repeat("a", agyPromptMaxBytes)); err != nil {
		t.Errorf("8 KiB exactly: %v", err)
	}
}

func TestAgyEndpointsTiers(t *testing.T) {
	a := newAgyAgent(t, 5*time.Second, filepath.Join(t.TempDir(), "none.db"))
	for _, c := range []struct{ method, path, body string }{
		{http.MethodPost, "/v1/antigravity/resume", `{"prompt":"x"}`},
		{http.MethodGet, "/v1/antigravity/permissions/enabled", ""},
		{http.MethodPost, "/v1/antigravity/permissions/enabled", `{"enabled":true}`},
	} {
		req, _ := http.NewRequest(c.method, a.http.URL+c.path, strings.NewReader(c.body))
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("%s %s unpaired: %d, want 401", c.method, c.path, resp.StatusCode)
		}
	}
	if _, err := os.Stat(a.srv.agyHooks); !os.IsNotExist(err) {
		t.Error("an unpaired call wrote hooks.json")
	}
}

// --- hooks.json ---

const otherNamedHook = `{"response-contract":{"enabled":true,"PreInvocation":[{"matcher":"*","hooks":[{"type":"command","command":"/usr/local/bin/contract && echo ok","timeout":5}]}]}}`

func TestInstallAgyHookAddIdempotentRemove(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hooks.json")
	if err := os.WriteFile(path, []byte(otherNamedHook), 0o640); err != nil {
		t.Fatal(err)
	}

	if _, err := installAgyHook(path, false, agyTestHookCommand); err != nil {
		t.Fatal(err)
	}
	assertSameJSON(t, path, `{
	  "response-contract":{"enabled":true,"PreInvocation":[{"matcher":"*","hooks":[{"type":"command","command":"/usr/local/bin/contract && echo ok","timeout":5}]}]},
	  "vitruvian-remote-phone":{"enabled":true,"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"`+agyTestHookCommand+`","timeout":150}]}]}}`)
	assertSameJSON(t, path+".bak", otherNamedHook)
	if st, _ := os.Stat(path); st.Mode().Perm() != 0o640 {
		t.Errorf("permissions changed to %v", st.Mode().Perm())
	}
	if on, err := agyHookInstalled(path); err != nil || !on {
		t.Errorf("installed = %v, %v", on, err)
	}
	if b, _ := os.ReadFile(path); !strings.Contains(string(b), "&& echo ok") {
		t.Errorf("another hook's command was HTML-escaped:\n%s", b)
	}

	// Idempotent: a second add writes nothing (the .bak would change).
	_ = os.Remove(path + ".bak")
	msg, err := installAgyHook(path, false, agyTestHookCommand)
	if err != nil || !strings.Contains(msg, "nothing to do") {
		t.Errorf("second add: %q %v", msg, err)
	}
	if _, err := os.Stat(path + ".bak"); !os.IsNotExist(err) {
		t.Error("an idempotent add wrote the file")
	}

	// A moved binary is replaced, not duplicated.
	if msg, err := installAgyHook(path, false, "/elsewhere/vitruvian-remote-agent agy-permission-hook"); err != nil || !strings.HasPrefix(msg, "updated") {
		t.Errorf("update: %q %v", msg, err)
	}

	if _, err := installAgyHook(path, true, agyTestHookCommand); err != nil {
		t.Fatal(err)
	}
	assertSameJSON(t, path, otherNamedHook)
	if on, _ := agyHookInstalled(path); on {
		t.Error("still installed after remove")
	}
	msg, err = installAgyHook(path, true, agyTestHookCommand)
	if err != nil || !strings.Contains(msg, "nothing to remove") {
		t.Errorf("second remove: %q %v", msg, err)
	}
}

func TestInstallAgyHookRefusesInvalidJSON(t *testing.T) {
	for name, content := range map[string]string{
		"broken": `{"response-contract": {`,
		"array":  `[1,2]`,
		"null":   `null`,
	} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "hooks.json")
			if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
				t.Fatal(err)
			}
			for _, remove := range []bool{false, true} {
				if _, err := installAgyHook(path, remove, agyTestHookCommand); err == nil || !strings.Contains(err.Error(), "left it untouched") {
					t.Errorf("remove=%v: err = %v", remove, err)
				}
			}
			if b, _ := os.ReadFile(path); string(b) != content {
				t.Errorf("file changed to %q", b)
			}
			if _, err := os.Stat(path + ".bak"); !os.IsNotExist(err) {
				t.Error("a backup was written for a refused edit")
			}
		})
	}
}

func TestAgyHookSwitchedOffByHandReadsAsOff(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hooks.json")
	_ = os.WriteFile(path, []byte(`{"vitruvian-remote-phone":{"enabled":false,"PreToolUse":[]}}`), 0o600)
	if on, _ := agyHookInstalled(path); on {
		t.Error(`"enabled": false must read as off`)
	}
	if msg, err := installAgyHook(path, false, agyTestHookCommand); err != nil || !strings.HasPrefix(msg, "updated") {
		t.Errorf("enable rewrites it: %q %v", msg, err)
	}
	if on, _ := agyHookInstalled(path); !on {
		t.Error("not on after enabling")
	}
}

func TestAgyToggleEndpoints(t *testing.T) {
	a := newAgyAgent(t, 5*time.Second, filepath.Join(t.TempDir(), "none.db"))
	if err := os.WriteFile(a.srv.agyHooks, []byte(otherNamedHook), 0o600); err != nil {
		t.Fatal(err)
	}
	code, m := a.do(t, http.MethodGet, "/v1/antigravity/permissions/enabled", "")
	if code != 200 || m["enabled"] != false || m["hooks_path"] == "" {
		t.Errorf("GET: %d %v", code, m)
	}
	code, m = a.do(t, http.MethodPost, "/v1/antigravity/permissions/enabled", `{"enabled":true}`)
	if code != 200 || m["enabled"] != true {
		t.Errorf("POST true: %d %v", code, m)
	}
	if code, m = a.do(t, http.MethodGet, "/v1/antigravity/permissions/enabled", ""); m["enabled"] != true {
		t.Errorf("GET after enable: %d %v", code, m)
	}
	code, m = a.do(t, http.MethodPost, "/v1/antigravity/permissions/enabled", `{"enabled":false}`)
	if code != 200 || m["enabled"] != false {
		t.Errorf("POST false: %d %v", code, m)
	}
	assertSameJSON(t, a.srv.agyHooks, otherNamedHook)
	if code, _ = a.do(t, http.MethodPost, "/v1/antigravity/permissions/enabled", `{}`); code != 400 {
		t.Errorf("missing enabled: %d", code)
	}

	if err := os.WriteFile(a.srv.agyHooks, []byte(`{nope`), 0o600); err != nil {
		t.Fatal(err)
	}
	code, m = a.do(t, http.MethodPost, "/v1/antigravity/permissions/enabled", `{"enabled":true}`)
	if code != 500 || !strings.Contains(fmt.Sprint(m["error"]), "left it untouched") {
		t.Errorf("invalid JSON: %d %v", code, m)
	}
	if b, _ := os.ReadFile(a.srv.agyHooks); string(b) != `{nope` {
		t.Errorf("invalid file was overwritten: %q", b)
	}
}

// --- the shared queue carries its source ---

func TestPermissionQueueCarriesSource(t *testing.T) {
	a := newPermAgent(t, 5*time.Second)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	a.ask(ctx, bashAsk)
	a.ask(ctx, `{"source":"antigravity","session_id":"`+agyIdle+`","cwd":"/Users/alice/src/acme","tool_name":"run_command","tool_input":{"command":"make   deploy\nnow"}}`)
	pending := a.waitPending(t, 2)
	bySource := map[string]map[string]any{}
	for _, p := range pending {
		m := p.(map[string]any)
		bySource[fmt.Sprint(m["source"])] = m
	}
	if bySource["claude"] == nil || bySource["antigravity"] == nil {
		t.Fatalf("sources = %v", pending)
	}
	ag := bySource["antigravity"]
	if ag["tool"] != "run_command" || ag["summary"] != "make deploy now" || ag["detail"] != "make   deploy\nnow" ||
		ag["project"] != "acme" || ag["session_id"] != agyIdle {
		t.Errorf("antigravity item = %v", ag)
	}

	res := recv(t, a.ask(ctx, `{"source":"gemini","tool_name":"x"}`))
	if res.status != http.StatusBadRequest {
		t.Errorf("unknown source: %d", res.status)
	}
}
