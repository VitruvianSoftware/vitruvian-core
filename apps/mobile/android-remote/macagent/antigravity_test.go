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
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// v1.7, pinned without agy. The summaries database is built by the test with
// agy's own schema (as measured on agy 1.2.11), and the resume runner is a
// fake that records what it was asked to run.

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

// newAgyAgent is newPermAgent plus the v1.7 routes, with the database at db
// and a fake runner that prints one line and exits 0.
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

// --- sessions ---

func TestAgySessionsFromTheDatabase(t *testing.T) {
	ws := t.TempDir()
	a := newAgyAgent(t, 5*time.Second, makeAgyDB(t, ws))

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
	// Newest first.
	wantIDs := []string{agyWorking, agyIdle, agyKilled, agyBusy}
	wantStates := []string{"working", "idle", "killed", "working"}
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
	got := agySessionsFrom(rows)
	want := map[string]string{"a": "idle", "b": "working", "c": "working", "d": "killed", "e": "idle"}
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
	capped := agySessionsFrom(many)
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
	if n := len(a.recorded()); n != 0 {
		t.Errorf("an unpaired resume ran agy %d times", n)
	}
}
