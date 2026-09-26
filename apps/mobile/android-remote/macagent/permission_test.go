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
	"context"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
	"unicode/utf8"
)

// v1.6, pinned without Claude Code and without a phone. The "hook" is a plain
// HTTP POST carrying the JSON Claude Code would send, and the "phone" is a
// plain HTTP POST to decide -- both are exactly what the real ends put on the
// wire, which is the part that can break.

// --- harness ---

const testHookCommand = "/opt/test/vitruvian-remote-agent permission-hook"

type permAgent struct {
	srv      *server
	http     *httptest.Server
	actTok   string
	hookTok  string
	settings string
}

// newPermAgent mounts the v1.6 routes on a server whose store, settings file
// and hook command are all temp. wait is the permission wait, which a test
// sets short so a timeout costs milliseconds.
func newPermAgent(t *testing.T, wait time.Duration) *permAgent {
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
	srv := &server{
		sampler:        NewSampler(time.Second, "", "", nil, nil),
		store:          store,
		perms:          newPermissionBroker(),
		permissionWait: wait,
		claudeSettings: filepath.Join(t.TempDir(), "settings.json"),
		hookCommand:    testHookCommand,
	}
	mux := http.NewServeMux()
	srv.permissionRoutes(mux)
	hs := httptest.NewServer(mux)
	t.Cleanup(hs.Close)
	return &permAgent{srv: srv, http: hs, actTok: act, hookTok: hook, settings: srv.claudeSettings}
}

type askResult struct {
	status int
	body   map[string]any
	err    error
}

// ask is the hook's call, run in the background; the channel yields its
// answer. ctx lets a test hang up the way Claude Code does.
func (a *permAgent) ask(ctx context.Context, body string) <-chan askResult {
	out := make(chan askResult, 1)
	go func() {
		req, _ := http.NewRequestWithContext(ctx, http.MethodPost, a.http.URL+"/v1/claude/permission/ask", strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+a.hookTok)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			out <- askResult{err: err}
			return
		}
		defer resp.Body.Close()
		var m map[string]any
		_ = json.NewDecoder(resp.Body).Decode(&m)
		out <- askResult{status: resp.StatusCode, body: m}
	}()
	return out
}

// do is an act-tier call with the paired token.
func (a *permAgent) do(t *testing.T, method, path, body string) (int, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest(method, a.http.URL+path, strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+a.actTok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var m map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&m)
	return resp.StatusCode, m
}

// waitPending polls the phone's list until n prompts are parked.
func (a *permAgent) waitPending(t *testing.T, n int) []any {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		_, m := a.do(t, http.MethodGet, "/v1/claude/permissions", "")
		if p, _ := m["pending"].([]any); len(p) == n {
			return p
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("never saw %d pending", n)
	return nil
}

func recv(t *testing.T, ch <-chan askResult) askResult {
	t.Helper()
	select {
	case r := <-ch:
		if r.err != nil {
			t.Fatal(r.err)
		}
		return r
	case <-time.After(5 * time.Second):
		t.Fatal("ask never answered")
		return askResult{}
	}
}

// syncBuffer is a log sink safe to read while handlers are still writing.
type syncBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

func captureLog(t *testing.T) *syncBuffer {
	t.Helper()
	buf := &syncBuffer{}
	old := log.Writer()
	log.SetOutput(buf)
	t.Cleanup(func() { log.SetOutput(old) })
	return buf
}

const bashAsk = `{"session_id":"s-1","cwd":"/Users/alice/src/acme","tool_name":"Bash",` +
	`"tool_input":{"command":"rm -rf build && make SECRET_ARG"},"transcript_path":"/t.jsonl","hook_event_name":"PermissionRequest"}`

// --- the round trip ---

// The feature in one test per answer: the hook parks a prompt, the phone
// sees it with the fields the contract lists, decides, and the hook gets that
// decision. The Mac's log names the tool and project and never the command.
func TestPermissionAskDecideRoundTrip(t *testing.T) {
	for _, tc := range []struct {
		name, decide, wantDecision, wantMessage string
	}{
		{"allow", `"decision":"allow"`, "allow", ""},
		{"deny with a reason", `"decision":"deny","message":"not on main"`, "deny", "not on main"},
		{"deny without one", `"decision":"deny"`, "deny", ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			logs := captureLog(t)
			a := newPermAgent(t, 5*time.Second)
			got := a.ask(context.Background(), bashAsk)

			pending := a.waitPending(t, 1)
			p := pending[0].(map[string]any)
			for k, want := range map[string]string{
				"id": "p-1", "session_id": "s-1", "project": "acme",
				"cwd": "/Users/alice/src/acme", "tool": "Bash",
				"summary": "rm -rf build && make SECRET_ARG", "detail": "rm -rf build && make SECRET_ARG",
			} {
				if p[k] != want {
					t.Errorf("pending[%s] = %v, want %q", k, p[k], want)
				}
			}
			created, _ := time.Parse(time.RFC3339Nano, p["created_at"].(string))
			expires, _ := time.Parse(time.RFC3339Nano, p["expires_at"].(string))
			if d := expires.Sub(created); d != 5*time.Second {
				t.Errorf("expires_at - created_at = %s, want the 5s wait", d)
			}

			status, body := a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"p-1",`+tc.decide+`}`)
			if status != http.StatusOK || len(body) != 0 {
				t.Fatalf("decide: %d %v, want 200 {}", status, body)
			}
			r := recv(t, got)
			if r.status != http.StatusOK || r.body["decision"] != tc.wantDecision {
				t.Fatalf("ask: %d %v, want decision %s", r.status, r.body, tc.wantDecision)
			}
			if msg, _ := r.body["message"].(string); msg != tc.wantMessage {
				t.Errorf("message = %q, want %q", msg, tc.wantMessage)
			}
			a.waitPending(t, 0)

			logged := logs.String()
			if !strings.Contains(logged, "act claude: "+tc.wantDecision+" Bash in acme") {
				t.Errorf("log %q lacks the act line", logged)
			}
			if strings.Contains(logged, "SECRET_ARG") {
				t.Errorf("the command leaked into the log: %q", logged)
			}
		})
	}
}

// No on/off gate in the agent: the hook running IS the switch, so an ask with
// no settings file at all still parks for the phone.
func TestPermissionAskIsNotGatedOnTheToggle(t *testing.T) {
	a := newPermAgent(t, 5*time.Second)
	if _, err := os.Stat(a.settings); !os.IsNotExist(err) {
		t.Fatalf("precondition: settings file should not exist, stat err %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	a.ask(ctx, bashAsk)
	a.waitPending(t, 1)
}

// Unanswered: the hook hears "ask" -- the Mac dialog -- and the prompt is gone
// from the phone.
func TestPermissionTimeoutFallsBackToAsk(t *testing.T) {
	a := newPermAgent(t, 150*time.Millisecond)
	start := time.Now()
	r := recv(t, a.ask(context.Background(), bashAsk))
	if r.status != http.StatusOK || r.body["decision"] != "ask" {
		t.Fatalf("got %d %v, want 200 ask", r.status, r.body)
	}
	if el := time.Since(start); el < 150*time.Millisecond {
		t.Errorf("answered after %s, before the wait ran out", el)
	}
	if n := a.srv.perms.len(); n != 0 {
		t.Errorf("%d prompts still parked after the timeout", n)
	}
	// And the phone deciding late is a 404, not a 200 nobody reads.
	if status, _ := a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"p-1","decision":"allow"}`); status != http.StatusNotFound {
		t.Errorf("late decide: %d, want 404", status)
	}
}

// Claude Code gave up (or the person answered on the Mac): the hook's request
// is cancelled, and the prompt must vanish from the phone.
func TestCancelledHookRequestDropsThePrompt(t *testing.T) {
	a := newPermAgent(t, 30*time.Second)
	ctx, cancel := context.WithCancel(context.Background())
	got := a.ask(ctx, bashAsk)
	a.waitPending(t, 1)
	cancel()
	<-got
	deadline := time.Now().Add(5 * time.Second)
	for a.srv.perms.len() != 0 {
		if time.Now().After(deadline) {
			t.Fatal("the cancelled prompt was never dropped")
		}
		time.Sleep(5 * time.Millisecond)
	}
	if status, _ := a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"p-1","decision":"allow"}`); status != http.StatusNotFound {
		t.Errorf("decide after cancel: %d, want 404", status)
	}
}

func TestDecideUnknownOrAnsweredIs404(t *testing.T) {
	a := newPermAgent(t, 5*time.Second)
	if status, _ := a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"p-99","decision":"allow"}`); status != http.StatusNotFound {
		t.Errorf("unknown id: %d, want 404", status)
	}
	got := a.ask(context.Background(), bashAsk)
	a.waitPending(t, 1)
	if status, _ := a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"p-1","decision":"deny"}`); status != http.StatusOK {
		t.Fatalf("first decide: %d", status)
	}
	recv(t, got)
	if status, _ := a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"p-1","decision":"allow"}`); status != http.StatusNotFound {
		t.Errorf("second decide: %d, want 404", status)
	}
}

func TestDecideBadDecisionIs400(t *testing.T) {
	a := newPermAgent(t, 5*time.Second)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	a.ask(ctx, bashAsk)
	a.waitPending(t, 1)
	for _, body := range []string{`{"id":"p-1","decision":"ask"}`, `{"id":"p-1","decision":"ALLOW"}`, `{"id":"p-1"}`, `not json`} {
		if status, _ := a.do(t, http.MethodPost, "/v1/claude/permissions/decide", body); status != http.StatusBadRequest {
			t.Errorf("%s: %d, want 400", body, status)
		}
	}
	// A bad decide must not have consumed the prompt.
	a.waitPending(t, 1)
}

// A deny message is capped at the contract's 300 characters.
func TestDenyMessageIsCapped(t *testing.T) {
	a := newPermAgent(t, 5*time.Second)
	got := a.ask(context.Background(), bashAsk)
	a.waitPending(t, 1)
	long := strings.Repeat("é", 400)
	a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"p-1","decision":"deny","message":"`+long+`"}`)
	msg, _ := recv(t, got).body["message"].(string)
	if n := utf8.RuneCountInString(msg); n != 300 {
		t.Errorf("message is %d runes, want 300", n)
	}
}

// --- the locks ---

// The ask endpoint is loopback + hook token, 403 before 401, and neither the
// pairing token nor the MCP token opens it.
func TestPermissionAskLocks(t *testing.T) {
	a := newPermAgent(t, 50*time.Millisecond)
	mcp, err := a.srv.store.EnsureMCPToken()
	if err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	a.srv.permissionRoutes(mux)

	serve := func(addr, tok string) int {
		req := httptest.NewRequest(http.MethodPost, "/v1/claude/permission/ask", strings.NewReader(bashAsk))
		req.RemoteAddr = addr
		if tok != "" {
			req.Header.Set("Authorization", "Bearer "+tok)
		}
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, req)
		return rec.Code
	}
	for _, addr := range []string{"100.101.102.103:5000", "192.168.1.10:9000", "[2606:4700::1]:443"} {
		// The CORRECT token, so a 403 proves the address check.
		if code := serve(addr, a.hookTok); code != http.StatusForbidden {
			t.Errorf("%s: %d, want 403", addr, code)
		}
	}
	for name, tok := range map[string]string{"none": "", "wrong": "deadbeef", "pairing token": a.actTok, "mcp token": mcp} {
		if code := serve("127.0.0.1:5000", tok); code != http.StatusUnauthorized {
			t.Errorf("%s: %d, want 401", name, code)
		}
	}
	if code := serve("[::1]:5000", a.hookTok); code != http.StatusOK {
		t.Errorf("loopback with the hook token: %d, want 200", code)
	}
}

// The phone's three endpoints are act tier.
func TestPermissionPhoneEndpointsAreAct(t *testing.T) {
	a := newPermAgent(t, time.Second)
	for _, c := range []struct{ method, path, body string }{
		{http.MethodGet, "/v1/claude/permissions", ""},
		{http.MethodPost, "/v1/claude/permissions/enabled", `{"enabled":true}`},
		{http.MethodPost, "/v1/claude/permissions/decide", `{"id":"p-1","decision":"allow"}`},
	} {
		for tok, want := range map[string]int{"": http.StatusUnauthorized, "wrong": http.StatusForbidden, a.hookTok: http.StatusForbidden} {
			req, _ := http.NewRequest(c.method, a.http.URL+c.path, strings.NewReader(c.body))
			if tok != "" {
				req.Header.Set("Authorization", "Bearer "+tok)
			}
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatal(err)
			}
			resp.Body.Close()
			if resp.StatusCode != want {
				t.Errorf("%s %s with %q: %d, want %d", c.method, c.path, tok, resp.StatusCode, want)
			}
		}
	}
	if _, err := os.Stat(a.settings); !os.IsNotExist(err) {
		t.Error("an unauthorised enable touched the settings file")
	}
}

// --- the toggle ---

const existingSettings = `{
  "model": "opus",
  "permissions": {"allow": ["Bash(ls:*)"]},
  "hooks": {
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "speaker-broadcast done && echo <ok>", "timeout": 10}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "~/bin/log-prompt"}]}]
  },
  "big": 12345678901234567890
}
`

// The phone's toggle: on installs our hook, on again changes nothing, off
// takes it out, and GET reports the file's truth each time.
func TestEnabledTogglesTheHookInSettings(t *testing.T) {
	a := newPermAgent(t, time.Second)
	if err := os.WriteFile(a.settings, []byte(existingSettings), 0o600); err != nil {
		t.Fatal(err)
	}
	enabled := func() any {
		_, m := a.do(t, http.MethodGet, "/v1/claude/permissions", "")
		return m["enabled"]
	}
	if enabled() != false {
		t.Fatal("enabled before installing")
	}

	status, body := a.do(t, http.MethodPost, "/v1/claude/permissions/enabled", `{"enabled":true}`)
	if status != http.StatusOK || body["enabled"] != true || body["settings_path"] != tildePath(a.settings) {
		t.Fatalf("enable: %d %v", status, body)
	}
	if enabled() != true {
		t.Error("GET does not see the installed hook")
	}
	after, _ := os.ReadFile(a.settings)
	if !strings.Contains(string(after), testHookCommand) {
		t.Errorf("hook command not written:\n%s", after)
	}
	if bak, _ := os.ReadFile(a.settings + ".bak"); string(bak) != existingSettings {
		t.Error(".bak is not the original")
	}

	// Idempotent: the file does not change.
	a.do(t, http.MethodPost, "/v1/claude/permissions/enabled", `{"enabled":true}`)
	if again, _ := os.ReadFile(a.settings); !bytes.Equal(again, after) {
		t.Error("enabling twice changed the file")
	}

	status, body = a.do(t, http.MethodPost, "/v1/claude/permissions/enabled", `{"enabled":false}`)
	if status != http.StatusOK || body["enabled"] != false {
		t.Fatalf("disable: %d %v", status, body)
	}
	if enabled() != false {
		t.Error("GET still sees the hook")
	}
	assertSameJSON(t, a.settings, existingSettings)

	if status, _ := a.do(t, http.MethodPost, "/v1/claude/permissions/enabled", `{}`); status != http.StatusBadRequest {
		t.Errorf("{}: %d, want 400", status)
	}
}

// A settings.json that does not parse is never overwritten: 500, the reason,
// and the file byte for byte as it was, with no .bak written.
func TestEnabledRefusesInvalidSettings(t *testing.T) {
	a := newPermAgent(t, time.Second)
	for _, bad := range []string{`{"hooks": {`, `[1,2]`, `{"hooks": []}`, `{"hooks": {"PermissionRequest": {}}}`} {
		if err := os.WriteFile(a.settings, []byte(bad), 0o600); err != nil {
			t.Fatal(err)
		}
		status, body := a.do(t, http.MethodPost, "/v1/claude/permissions/enabled", `{"enabled":true}`)
		if status != http.StatusInternalServerError || !strings.Contains(body["error"].(string), "untouched") {
			t.Errorf("%s: %d %v, want 500 saying it was left untouched", bad, status, body)
		}
		if now, _ := os.ReadFile(a.settings); string(now) != bad {
			t.Errorf("%s: file changed to %s", bad, now)
		}
		if _, err := os.Stat(a.settings + ".bak"); !os.IsNotExist(err) {
			t.Errorf("%s: a .bak was written for a refused edit", bad)
		}
		_, m := a.do(t, http.MethodGet, "/v1/claude/permissions", "")
		if m["enabled"] != false {
			t.Errorf("%s: GET enabled = %v", bad, m["enabled"])
		}
	}
}

// --- derivation ---

func TestPermissionSummary(t *testing.T) {
	long := strings.Repeat("x", 200)
	for _, tc := range []struct{ tool, input, want string }{
		{"Bash", `{"command":"git push origin main","description":"push"}`, "git push origin main"},
		{"Bash", `{"command":"echo a\n\techo   b"}`, "echo a echo b"},
		{"Bash", `{"command":"` + long + `"}`, strings.Repeat("x", 119) + "…"},
		{"Edit", `{"file_path":"/r/main.go","old_string":"a","new_string":"b"}`, "edit /r/main.go"},
		{"Write", `{"file_path":"/r/new.go","content":"package x"}`, "edit /r/new.go"},
		{"MultiEdit", `{"file_path":"/r/a.go","edits":[]}`, "edit /r/a.go"},
		{"NotebookEdit", `{"notebook_path":"/r/n.ipynb","new_source":"x"}`, "edit /r/n.ipynb"},
		{"WebFetch", `{"url":"https://example.com/a","prompt":"read"}`, "https://example.com/a"},
		{"mcp__phone__sms_send", `{"to": "+1 555", "body": "hi"}`, `mcp__phone__sms_send {"to":"+1 555","body":"hi"}`},
		{"Bash", `{"nope":1}`, `Bash {"nope":1}`},
		{"Glob", ``, "Glob"},
	} {
		got := permissionSummary(tc.tool, json.RawMessage(tc.input))
		if got != tc.want {
			t.Errorf("%s %s:\n got %q\nwant %q", tc.tool, tc.input, got, tc.want)
		}
		if n := utf8.RuneCountInString(got); n > 120 {
			t.Errorf("%s: %d runes", tc.tool, n)
		}
	}
}

func TestPermissionDetail(t *testing.T) {
	if got := permissionDetail("Bash", json.RawMessage(`{"command":"a\nb"}`)); got != "a\nb" {
		t.Errorf("bash detail %q", got)
	}
	if got := permissionDetail("Edit", json.RawMessage(`{"file_path":"/x"}`)); got != "{\n  \"file_path\": \"/x\"\n}" {
		t.Errorf("edit detail %q", got)
	}
	// 4 KiB, cut on a rune boundary.
	big := permissionDetail("Bash", json.RawMessage(`{"command":"`+strings.Repeat("é", 5000)+`"}`))
	if len(big) > 4096 || !utf8.ValidString(big) || !strings.HasSuffix(big, "…") {
		t.Errorf("detail: %d bytes, valid=%v", len(big), utf8.ValidString(big))
	}
}

func TestClampPermissionWait(t *testing.T) {
	for in, want := range map[time.Duration]time.Duration{
		0: 5 * time.Second, time.Second: 5 * time.Second, 120 * time.Second: 120 * time.Second,
		140 * time.Second: 140 * time.Second, 10 * time.Minute: 140 * time.Second,
	} {
		if got := clampPermissionWait(in); got != want {
			t.Errorf("clamp(%s) = %s, want %s", in, got, want)
		}
	}
}

// assertSameJSON compares a file to a JSON document semantically.
func assertSameJSON(t *testing.T, path, want string) {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	norm := func(s []byte) string {
		dec := json.NewDecoder(bytes.NewReader(s))
		dec.UseNumber()
		var v any
		if err := dec.Decode(&v); err != nil {
			t.Fatalf("not JSON: %v\n%s", err, s)
		}
		var buf bytes.Buffer
		enc := json.NewEncoder(&buf)
		enc.SetEscapeHTML(false)
		_ = enc.Encode(v)
		return buf.String()
	}
	if got, w := norm(b), norm([]byte(want)); got != w {
		t.Errorf("settings differ:\n got %s\nwant %s", got, w)
	}
}
