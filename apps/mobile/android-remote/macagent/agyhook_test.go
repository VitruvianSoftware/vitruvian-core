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
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// agy-permission-hook, pinned against the real agent handler and a fake Mac
// dialog. No test here runs osascript: a unit test that pops a dialog on the
// developer's screen is a bug.

// agySettingsFile writes an agy settings.json with a few allow rules.
func agySettingsFile(t *testing.T) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "settings.json")
	body := `{"model":"x","permissions":{"allow":["command(grep)","command(git status)","read_file(*)","command()"," command(ps) "]}}`
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestAgyWouldPrompt(t *testing.T) {
	settings := agySettingsFile(t)
	broken := filepath.Join(t.TempDir(), "broken.json")
	_ = os.WriteFile(broken, []byte(`{"permissions":`), 0o600)
	missing := filepath.Join(t.TempDir(), "missing.json")

	for _, tc := range []struct {
		name, tool, cmd, settings string
		want                      bool
	}{
		{"allowed prefix with args", "run_command", "grep -r foo .", settings, false},
		{"allowed prefix alone, padded", "run_command", "  grep  ", settings, false},
		{"prefix without a space is not a match", "run_command", "grepx -r foo", settings, true},
		{"multi-word prefix", "run_command", "git status -s", settings, false},
		{"multi-word prefix exactly", "run_command", "git status", settings, false},
		{"multi-word prefix run on", "run_command", "git statusx", settings, true},
		{"same first word, other command", "run_command", "git push --force", settings, true},
		{"rule with spaces around it", "run_command", "ps aux", settings, false},
		{"not allowed", "run_command", "rm -rf build", settings, true},
		{"empty command", "run_command", "   ", settings, false},
		{"other tools are never routed", "view_file", "grepx", settings, false},
		{"write tools are never routed", "write_to_file", "", settings, false},
		{"unreadable settings would prompt", "run_command", "grep x", missing, true},
		{"unparseable settings would prompt", "run_command", "grep x", broken, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := agyWouldPrompt(tc.tool, tc.cmd, tc.settings); got != tc.want {
				t.Errorf("agyWouldPrompt(%q, %q) = %v, want %v", tc.tool, tc.cmd, got, tc.want)
			}
		})
	}
}

// fakeDialog is the Mac dialog. By default it stays up until cancelled.
type fakeDialog struct {
	mu        sync.Mutex
	commands  []string
	before    func()        // runs first, e.g. to wait for the phone side
	answer    string        // returned after delay
	err       error         // returned after delay
	delay     time.Duration // 0 with answer=="" && err==nil means "stay up"
	cancelled chan struct{}
}

func newFakeDialog() *fakeDialog { return &fakeDialog{cancelled: make(chan struct{})} }

func (f *fakeDialog) run(ctx context.Context, command string, wait time.Duration) (string, error) {
	f.mu.Lock()
	f.commands = append(f.commands, command)
	f.mu.Unlock()
	if f.before != nil {
		f.before()
	}
	var after <-chan time.Time
	if f.answer != "" || f.err != nil || f.delay > 0 {
		after = time.After(f.delay)
	}
	select {
	case <-after:
		return f.answer, f.err
	case <-ctx.Done():
		close(f.cancelled)
		return "", ctx.Err()
	}
}

func (f *fakeDialog) calls() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.commands...)
}

const agyRunInput = `{"conversationId":"` + agyIdle + `","stepIdx":4,"modelName":"m","workspacePaths":["/Users/alice/src/acme"],` +
	`"artifactDirectoryPath":"/tmp/a","toolCall":{"name":"run_command","args":{"CommandLine":"make deploy","Cwd":"/Users/alice/src/acme/web","toolSummary":"deploy"}}}`

// runHook runs the hook in the background against agent a (nil: agent down).
func runHook(t *testing.T, a *permAgent, dialog *fakeDialog, input string) <-chan []byte {
	t.Helper()
	d := agyHookDeps{
		settingsPath: agySettingsFile(t),
		client:       &http.Client{},
		dialogWait:   time.Minute,
		total:        10 * time.Second,
	}
	if a != nil {
		d.baseURL, d.token = a.http.URL, a.hookTok
	} else {
		down := httptest.NewServer(http.NotFoundHandler())
		d.baseURL, d.token = down.URL, "some-token"
		down.Close()
	}
	if dialog != nil {
		d.dialog = dialog.run
	}
	out := make(chan []byte, 1)
	go func() { out <- agyPermissionHookOutput(strings.NewReader(input), d) }()
	return out
}

func hookResult(t *testing.T, ch <-chan []byte) []byte {
	t.Helper()
	select {
	case b := <-ch:
		return b
	case <-time.After(8 * time.Second):
		t.Fatal("hook never returned")
		return nil
	}
}

func TestAgyHookPhoneAnswersFirst(t *testing.T) {
	for _, tc := range []struct{ name, decide, want string }{
		{"allow", `"decision":"allow"`, `{"decision":"allow"}` + "\n"},
		{"deny with a reason", `"decision":"deny","message":"not today"`, `{"decision":"deny","reason":"not today"}` + "\n"},
		{"deny without one", `"decision":"deny"`, `{"decision":"deny","reason":"Denied from the phone"}` + "\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			a := newPermAgent(t, 5*time.Second)
			dialog := newFakeDialog()
			out := runHook(t, a, dialog, agyRunInput)

			p := a.waitPending(t, 1)[0].(map[string]any)
			// The body the hook sent, normalised to Claude Code's shape.
			if p["source"] != "antigravity" || p["session_id"] != agyIdle || p["cwd"] != "/Users/alice/src/acme/web" ||
				p["tool"] != "run_command" || p["summary"] != "make deploy" || p["project"] != "web" {
				t.Errorf("pending = %v", p)
			}
			if code, _ := a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"`+p["id"].(string)+`",`+tc.decide+`}`); code != 200 {
				t.Fatalf("decide: %d", code)
			}
			if got := string(hookResult(t, out)); got != tc.want {
				t.Errorf("output = %q, want %q", got, tc.want)
			}
			select {
			case <-dialog.cancelled:
			default:
				t.Error("the Mac dialog was not taken down when the phone answered")
			}
			if c := dialog.calls(); len(c) != 1 || c[0] != "make deploy" {
				t.Errorf("dialog shown for %q", c)
			}
		})
	}
}

func TestAgyHookMacDialogAnswersFirst(t *testing.T) {
	for _, tc := range []struct{ answer, want string }{
		{"allow", `{"decision":"allow"}` + "\n"},
		{"deny", `{"decision":"deny","reason":"Denied on the Mac"}` + "\n"},
	} {
		t.Run(tc.answer, func(t *testing.T) {
			a := newPermAgent(t, 5*time.Second)
			dialog := newFakeDialog()
			// Answer only once the phone has the prompt, so the test also
			// proves the phone's copy is withdrawn.
			dialog.before = func() {
				deadline := time.Now().Add(5 * time.Second)
				for a.srv.perms.len() == 0 && time.Now().Before(deadline) {
					time.Sleep(2 * time.Millisecond)
				}
			}
			dialog.answer = tc.answer
			out := runHook(t, a, dialog, agyRunInput)
			if got := string(hookResult(t, out)); got != tc.want {
				t.Errorf("output = %q, want %q", got, tc.want)
			}
			a.waitPending(t, 0)
		})
	}
}

func TestAgyHookBothTimeOutPrintsNothing(t *testing.T) {
	a := newPermAgent(t, 30*time.Millisecond) // the agent gives up: "ask"
	dialog := newFakeDialog()
	dialog.delay = 80 * time.Millisecond // then the dialog gives up: ""
	if got := hookResult(t, runHook(t, a, dialog, agyRunInput)); got != nil {
		t.Errorf("output = %q, want nothing", got)
	}
}

func TestAgyHookAgentDownDialogStillWorks(t *testing.T) {
	dialog := newFakeDialog()
	dialog.answer = "allow"
	if got := string(hookResult(t, runHook(t, nil, dialog, agyRunInput))); got != `{"decision":"allow"}`+"\n" {
		t.Errorf("output = %q", got)
	}
}

func TestAgyHookDialogErrorPhoneStillWorks(t *testing.T) {
	a := newPermAgent(t, 5*time.Second)
	dialog := newFakeDialog()
	dialog.err = errors.New("osascript: execution error: not allowed (-1743)")
	out := runHook(t, a, dialog, agyRunInput)
	p := a.waitPending(t, 1)[0].(map[string]any)
	a.do(t, http.MethodPost, "/v1/claude/permissions/decide", `{"id":"`+p["id"].(string)+`","decision":"allow"}`)
	if got := string(hookResult(t, out)); got != `{"decision":"allow"}`+"\n" {
		t.Errorf("output = %q", got)
	}
}

func TestAgyHookStaysSilentWhenAgyWouldNotAsk(t *testing.T) {
	for name, input := range map[string]string{
		"allowed command": strings.Replace(agyRunInput, "make deploy", "grep -r TODO .", 1),
		"other tool":      `{"conversationId":"x","toolCall":{"name":"view_file","args":{"AbsolutePath":"/etc/hosts"}}}`,
		"not JSON":        `not json`,
		"empty":           ``,
	} {
		t.Run(name, func(t *testing.T) {
			a := newPermAgent(t, 5*time.Second)
			dialog := newFakeDialog()
			if got := hookResult(t, runHook(t, a, dialog, input)); got != nil {
				t.Errorf("output = %q, want nothing", got)
			}
			if n := len(dialog.calls()); n != 0 {
				t.Errorf("dialog shown %d times", n)
			}
			if n := a.srv.perms.len(); n != 0 {
				t.Errorf("%d prompts reached the phone", n)
			}
		})
	}
}

// The subcommand itself, on the paths that end before any dialog: nothing on
// stdout, no panic, whatever the flags.
func TestRunAgyPermissionHookSilentPaths(t *testing.T) {
	settings := agySettingsFile(t)
	for _, in := range []string{
		`garbage`,
		`{"toolCall":{"name":"view_file"}}`,
		strings.Replace(agyRunInput, "make deploy", "git status", 1),
	} {
		var out bytes.Buffer
		runAgyPermissionHook([]string{"--config-dir", t.TempDir(), "--agy-settings", settings, "--unknown-flag"}, strings.NewReader(in), &out)
		if out.Len() != 0 {
			t.Errorf("input %q printed %q", in, out.String())
		}
	}
}

func TestIsOurHookIgnoresTheAgyVerb(t *testing.T) {
	if isOurHook(agyTestHookCommand, testHookCommand) {
		t.Error("the Claude installer would treat the agy hook command as its own")
	}
}
