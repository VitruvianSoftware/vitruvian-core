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
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// --- permission-hook ---

// The hook's stdout, byte for byte, for every reply the agent can give. The
// rule under test: allow and deny print the contract's JSON; everything else
// prints NOTHING, so Claude Code shows its own dialog.
func TestPermissionHookOutput(t *testing.T) {
	const allowOut = `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` + "\n"
	for _, tc := range []struct {
		name   string
		status int
		reply  string
		want   string
	}{
		{"allow", 200, `{"decision":"allow"}`, allowOut},
		{
			"deny with a message", 200, `{"decision":"deny","message":"not on main & not <now>"}`,
			`{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"not on main & not <now>"}}}` + "\n",
		},
		{
			"deny without one", 200, `{"decision":"deny"}`,
			`{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from the phone"}}}` + "\n",
		},
		{"ask", 200, `{"decision":"ask"}`, ""},
		{"an unknown decision", 200, `{"decision":"maybe"}`, ""},
		{"garbage", 200, `{"decision":`, ""},
		{"a 401", 401, `{"error":"no"}`, ""},
		{"a 500 that says allow", 500, `{"decision":"allow"}`, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var gotAuth, gotBody string
			agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/v1/claude/permission/ask" || r.Method != http.MethodPost {
					t.Errorf("hook called %s %s", r.Method, r.URL.Path)
				}
				gotAuth = r.Header.Get("Authorization")
				b := new(bytes.Buffer)
				_, _ = b.ReadFrom(r.Body)
				gotBody = b.String()
				w.WriteHeader(tc.status)
				_, _ = w.Write([]byte(tc.reply))
			}))
			defer agent.Close()

			out := permissionHookOutput(strings.NewReader(bashAsk), agent.URL, "tok", newHookClient())
			if string(out) != tc.want {
				t.Errorf("stdout:\n got %q\nwant %q", out, tc.want)
			}
			if gotAuth != "Bearer tok" || gotBody != bashAsk {
				t.Errorf("sent auth %q body %q; want the token and stdin verbatim", gotAuth, gotBody)
			}
		})
	}
}

// Nothing at all for every way the agent can fail to be there.
func TestPermissionHookFallsThroughWhenTheAgentIsDown(t *testing.T) {
	down := httptest.NewServer(http.NotFoundHandler())
	url := down.URL
	down.Close()
	if out := permissionHookOutput(strings.NewReader(bashAsk), url, "tok", newHookClient()); out != nil {
		t.Errorf("agent down: printed %q", out)
	}

	called := false
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		_, _ = w.Write([]byte(`{"decision":"allow"}`))
	}))
	defer agent.Close()
	if out := permissionHookOutput(strings.NewReader(bashAsk), agent.URL, "", newHookClient()); out != nil || called {
		t.Errorf("no token: printed %q, called %v", out, called)
	}
	if out := permissionHookOutput(strings.NewReader("not json"), agent.URL, "tok", newHookClient()); out != nil || called {
		t.Errorf("bad stdin: printed %q, called %v", out, called)
	}
}

// The subcommand itself: with no token file it prints nothing (and, being a
// function that returns, does not exit non-zero).
func TestRunPermissionHookWithoutATokenPrintsNothing(t *testing.T) {
	var out bytes.Buffer
	runPermissionHook([]string{"--config-dir", t.TempDir(), "--unknown-flag"}, strings.NewReader(bashAsk), &out)
	if out.Len() != 0 {
		t.Errorf("printed %q", out.String())
	}
}

// End to end through the real agent handlers: hook -> ask -> phone decides
// -> hook prints allow.
func TestPermissionHookAgainstTheRealAgent(t *testing.T) {
	a := newPermAgent(t, 5*time.Second)
	done := make(chan []byte, 1)
	go func() {
		done <- permissionHookOutput(strings.NewReader(bashAsk), a.http.URL, a.hookTok, newHookClient())
	}()
	a.waitPending(t, 1)
	a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"p-1","decision":"allow"}`)
	select {
	case out := <-done:
		var v map[string]any
		if err := json.Unmarshal(out, &v); err != nil {
			t.Fatalf("hook printed %q: %v", out, err)
		}
		if !strings.Contains(string(out), `"behavior":"allow"`) {
			t.Errorf("hook printed %q", out)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("hook never returned")
	}
}

// --- install-claude-hook ---

func TestInstallClaudeHookAddIdempotentRemove(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := os.WriteFile(path, []byte(existingSettings), 0o600); err != nil {
		t.Fatal(err)
	}

	msg, err := installClaudeHook(path, false, testHookCommand)
	if err != nil || !strings.HasPrefix(msg, "added") {
		t.Fatalf("add: %q %v", msg, err)
	}
	added, _ := os.ReadFile(path)
	var s struct {
		Hooks map[string][]struct {
			Matcher *string `json:"matcher"`
			Hooks   []struct {
				Type    string `json:"type"`
				Command string `json:"command"`
				Timeout int    `json:"timeout"`
			} `json:"hooks"`
		} `json:"hooks"`
	}
	if err := json.Unmarshal(added, &s); err != nil {
		t.Fatal(err)
	}
	pr := s.Hooks["PermissionRequest"]
	if len(pr) != 1 || pr[0].Matcher == nil || *pr[0].Matcher != "" || len(pr[0].Hooks) != 1 ||
		pr[0].Hooks[0].Type != "command" || pr[0].Hooks[0].Command != testHookCommand || pr[0].Hooks[0].Timeout != 150 {
		t.Errorf("PermissionRequest entry wrong:\n%s", added)
	}
	// The neighbours survive, verbatim where it matters: && and <ok> not
	// escaped, a 20-digit number not rounded.
	for _, keep := range []string{`"speaker-broadcast done && echo <ok>"`, `"~/bin/log-prompt"`, `12345678901234567890`, `"Bash(ls:*)"`, `"model": "opus"`} {
		if !strings.Contains(string(added), keep) {
			t.Errorf("lost %s:\n%s", keep, added)
		}
	}
	if st, _ := os.Stat(path); st.Mode().Perm() != 0o600 {
		t.Errorf("perm %v, want 0600", st.Mode().Perm())
	}
	if bak, _ := os.ReadFile(path + ".bak"); string(bak) != existingSettings {
		t.Error(".bak is not the original")
	}
	if on, err := claudeHookInstalled(path, testHookCommand); !on || err != nil {
		t.Errorf("installed = %v, %v", on, err)
	}

	msg, err = installClaudeHook(path, false, testHookCommand)
	if err != nil || !strings.Contains(msg, "already") {
		t.Errorf("second add: %q %v", msg, err)
	}
	if again, _ := os.ReadFile(path); !bytes.Equal(again, added) {
		t.Error("second add changed the file")
	}

	msg, err = installClaudeHook(path, true, testHookCommand)
	if err != nil || !strings.HasPrefix(msg, "removed") {
		t.Fatalf("remove: %q %v", msg, err)
	}
	assertSameJSON(t, path, existingSettings)
	if on, _ := claudeHookInstalled(path, testHookCommand); on {
		t.Error("still installed after remove")
	}
	msg, err = installClaudeHook(path, true, testHookCommand)
	if err != nil || !strings.Contains(msg, "nothing to remove") {
		t.Errorf("second remove: %q %v", msg, err)
	}
}

// A hook of ours from an older build ("~/..." path) or another install
// location is recognised and replaced, not duplicated; a user's own
// PermissionRequest hook in the same group is kept.
func TestInstallClaudeHookReplacesAStaleEntryAndKeepsOthers(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	stale := `{"hooks":{"PermissionRequest":[{"matcher":"","hooks":[` +
		`{"type":"command","command":"~/.local/bin/vitruvian-remote-agent permission-hook","timeout":150},` +
		`{"type":"command","command":"my-own-audit-hook"}]}]}}`
	if err := os.WriteFile(path, []byte(stale), 0o644); err != nil {
		t.Fatal(err)
	}
	if on, _ := claudeHookInstalled(path, testHookCommand); !on {
		t.Error("the stale entry should count as installed")
	}
	msg, err := installClaudeHook(path, false, testHookCommand)
	if err != nil || !strings.HasPrefix(msg, "updated") {
		t.Fatalf("add over stale: %q %v", msg, err)
	}
	b, _ := os.ReadFile(path)
	if strings.Count(string(b), "permission-hook") != 1 || !strings.Contains(string(b), testHookCommand) ||
		!strings.Contains(string(b), "my-own-audit-hook") {
		t.Errorf("after update:\n%s", b)
	}
	if st, _ := os.Stat(path); st.Mode().Perm() != 0o644 {
		t.Errorf("perm %v, want the original 0644", st.Mode().Perm())
	}
	if _, err := installClaudeHook(path, true, testHookCommand); err != nil {
		t.Fatal(err)
	}
	assertSameJSON(t, path, `{"hooks":{"PermissionRequest":[{"matcher":"","hooks":[{"type":"command","command":"my-own-audit-hook"}]}]}}`)
}

// No settings file yet: created at 0600, no .bak, and removing afterwards
// leaves {} rather than an empty "hooks".
func TestInstallClaudeHookCreatesTheFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "settings.json")
	if _, err := installClaudeHook(path, false, testHookCommand); err != nil {
		t.Fatal(err)
	}
	if st, err := os.Stat(path); err != nil || st.Mode().Perm() != 0o600 {
		t.Fatalf("stat %v %v", st, err)
	}
	if _, err := os.Stat(path + ".bak"); !os.IsNotExist(err) {
		t.Error("a .bak for a file that did not exist")
	}
	if _, err := installClaudeHook(path, true, testHookCommand); err != nil {
		t.Fatal(err)
	}
	assertSameJSON(t, path, `{}`)
}

// Writing through a symlink edits the target and keeps the link.
func TestInstallClaudeHookFollowsASymlink(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "dotfiles-settings.json")
	link := filepath.Join(dir, "settings.json")
	if err := os.WriteFile(target, []byte(`{}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, link); err != nil {
		t.Skip("no symlinks here:", err)
	}
	if _, err := installClaudeHook(link, false, testHookCommand); err != nil {
		t.Fatal(err)
	}
	if st, _ := os.Lstat(link); st.Mode()&os.ModeSymlink == 0 {
		t.Error("the symlink was replaced by a file")
	}
	if b, _ := os.ReadFile(target); !strings.Contains(string(b), testHookCommand) {
		t.Error("the target was not edited")
	}
}

func TestShellQuoteAndIsOurHook(t *testing.T) {
	if got := shellQuote("/Users/j/.local/bin/vitruvian-remote-agent"); got != "/Users/j/.local/bin/vitruvian-remote-agent" {
		t.Errorf("plain path quoted: %s", got)
	}
	if got := shellQuote("/Users/j/My Apps/it's"); got != `'/Users/j/My Apps/it'\''s'` {
		t.Errorf("quoted: %s", got)
	}
	for c, want := range map[string]bool{
		testHookCommand: true,
		"~/.local/bin/vitruvian-remote-agent permission-hook":       true,
		"'/Users/j/My Apps/vitruvian-remote-agent' permission-hook": true,
		"vitruvian-remote-agent token":                              false,
		"other-tool permission-hook":                                false,
		"speaker-broadcast done":                                    false,
	} {
		if got := isOurHook(c, testHookCommand); got != want {
			t.Errorf("isOurHook(%q) = %v", c, got)
		}
	}
}
