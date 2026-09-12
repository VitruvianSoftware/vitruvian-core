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
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

// These run real commands, which is unusual for this package -- but the
// behaviour under test IS the process handling, and a fake process would
// test the fake. Everything used here (/bin/zsh, sleep, pgrep) is on every
// Mac and on the Linux CI runner alike.

// requireShell skips when there is no /bin/zsh. The `shell` kind hardcodes
// it, so a runner without one can only test the framing.
func requireShell(t *testing.T) {
	t.Helper()
	if _, err := os.Stat("/bin/zsh"); err != nil {
		t.Skip("no /bin/zsh on this runner")
	}
}

func TestRunStreamInterleavesStdoutAndStderr(t *testing.T) {
	requireShell(t)
	// The sleeps are load-bearing. Without a gap between the writes, which
	// of two goroutines reaches the channel first is a scheduling race, and
	// the ordering this asserts would be flaky rather than wrong. A quarter
	// of a second is far longer than the scheduler needs and short enough
	// not to slow the suite noticeably.
	lines := make(chan streamLine, 32)
	go func() {
		runStream(context.Background(), execRequest{
			Kind:    "shell",
			Command: `echo one; sleep 0.25; echo problem >&2; sleep 0.25; echo two`,
		}, lines)
	}()
	var got []streamLine
	for l := range lines {
		got = append(got, l)
	}
	if len(got) != 3 {
		t.Fatalf("want three lines, got %+v", got)
	}
	// stderr arrives on the same channel, in the order it was produced. A
	// version that drained stdout to completion first would hold "problem"
	// back until after "two" -- and on a long build, until the very end.
	if got[0].Text != "one" || got[0].Stream != "stdout" {
		t.Errorf("line 0: %+v", got[0])
	}
	if got[1].Text != "problem" || got[1].Stream != "stderr" {
		t.Errorf("line 1 should be the interleaved stderr: %+v", got[1])
	}
	if got[2].Text != "two" || got[2].Stream != "stdout" {
		t.Errorf("line 2: %+v", got[2])
	}
}

func TestRunStreamExitCode(t *testing.T) {
	requireShell(t)
	lines := make(chan streamLine, 8)
	done := make(chan int, 1)
	go func() {
		code, _ := runStream(context.Background(), execRequest{Kind: "shell", Command: "exit 7"}, lines)
		done <- code
	}()
	for range lines {
	}
	if code := <-done; code != 7 {
		t.Errorf("exit code = %d, want 7", code)
	}
}

// TestRunStreamKillsTheProcessGroup is the one that matters, and it is the
// bug this endpoint would otherwise ship with. `zsh -lc 'sleep 30'` leaves a
// sleep behind when only the shell is killed; the phone's Cancel button is a
// disconnect, so every cancelled command would leak a process.
func TestRunStreamKillsTheProcessGroup(t *testing.T) {
	requireShell(t)
	if _, err := exec.LookPath("pgrep"); err != nil {
		t.Skip("no pgrep on this runner")
	}
	// A sleep with a distinctive duration, so this test cannot see someone
	// else's sleep and cannot be seen by another test.
	const marker = "31.5"
	ctx, cancel := context.WithCancel(context.Background())
	lines := make(chan streamLine, 8)
	done := make(chan struct{})
	go func() {
		runStream(ctx, execRequest{Kind: "shell", Command: "sleep " + marker}, lines)
		close(done)
	}()
	go func() {
		for range lines {
		}
	}()

	// Wait for the sleep to actually exist before cancelling, or the test
	// proves nothing: killing a group that has not forked yet always works.
	if !waitFor(3*time.Second, func() bool { return pgrepCount(marker) > 0 }) {
		cancel()
		t.Skip("the sleep never appeared in pgrep; nothing to prove here")
	}
	cancel()
	<-done

	// killGroup sends TERM then KILL 200 ms later, so give it a moment.
	if !waitFor(5*time.Second, func() bool { return pgrepCount(marker) == 0 }) {
		t.Fatalf("a `sleep %s` survived the cancellation: the process group was not killed", marker)
	}
}

func waitFor(limit time.Duration, cond func() bool) bool {
	deadline := time.Now().Add(limit)
	for time.Now().Before(deadline) {
		if cond() {
			return true
		}
		time.Sleep(50 * time.Millisecond)
	}
	return cond()
}

func pgrepCount(arg string) int {
	out, _ := exec.Command("pgrep", "-f", "sleep "+arg).Output()
	n := 0
	for _, l := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if strings.TrimSpace(l) != "" {
			n++
		}
	}
	return n
}

func TestClampStreamTimeout(t *testing.T) {
	if got := clampStreamTimeout(0); got != defaultStreamTimeoutSec*time.Second {
		t.Errorf("zero means the default, got %s", got)
	}
	if got := clampStreamTimeout(-1); got != defaultStreamTimeoutSec*time.Second {
		t.Errorf("negative means the default, got %s", got)
	}
	if got := clampStreamTimeout(120); got != 120*time.Second {
		t.Errorf("a lower request is honoured, got %s", got)
	}
	// The cap is the point: an unbounded command from a phone that has since
	// gone out of range is a process nobody will reap.
	if got := clampStreamTimeout(999999); got != maxStreamTimeoutSec*time.Second {
		t.Errorf("above the cap must clamp, got %s", got)
	}
	// And it is genuinely longer than the buffered endpoint's, which is the
	// whole reason the streaming one exists.
	if maxStreamTimeoutSec <= maxTimeoutSec {
		t.Error("the streaming cap must exceed the buffered one")
	}
}

// TestExecStreamServesSSE pins the wire format the phone parses.
func TestExecStreamServesSSE(t *testing.T) {
	requireShell(t)
	_, store, srv := newTestAgent(t)
	tok := pairedToken(t, store)

	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/exec/stream",
		strings.NewReader(`{"kind":"shell","command":"echo alpha; echo beta"}`))
	req.Header.Set("Authorization", "Bearer "+tok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		t.Errorf("Content-Type = %q", ct)
	}
	if cc := resp.Header.Get("Cache-Control"); cc != "no-store" {
		t.Errorf("Cache-Control = %q", cc)
	}

	var events []string
	var texts []string
	var exit streamExit
	sc := bufio.NewScanner(resp.Body)
	event := ""
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "event: "):
			event = strings.TrimPrefix(line, "event: ")
			events = append(events, event)
		case strings.HasPrefix(line, "data: "):
			data := strings.TrimPrefix(line, "data: ")
			switch event {
			case "line":
				var l streamLine
				if err := json.Unmarshal([]byte(data), &l); err != nil {
					t.Fatalf("line payload is not JSON: %q", data)
				}
				texts = append(texts, l.Text)
			case "exit":
				if err := json.Unmarshal([]byte(data), &exit); err != nil {
					t.Fatalf("exit payload is not JSON: %q", data)
				}
			}
		}
	}
	if len(texts) != 2 || texts[0] != "alpha" || texts[1] != "beta" {
		t.Errorf("lines = %v", texts)
	}
	// exit is always last, and always present.
	if len(events) == 0 || events[len(events)-1] != "exit" {
		t.Errorf("events = %v; exit must be last", events)
	}
	if exit.ExitCode != 0 {
		t.Errorf("exit = %+v", exit)
	}
}

// A bad kind must be a 400 with a JSON error, NOT a 200 event stream whose
// exit event says -1. Once the status line is spent there is no way to tell
// a client its request was malformed rather than its command broken.
func TestExecStreamRejectsABadRequestBeforeTheFirstByte(t *testing.T) {
	_, store, srv := newTestAgent(t)
	tok := pairedToken(t, store)

	for _, body := range []string{`{"kind":"rm","command":"-rf /"}`, `{"kind":"shell","command":"   "}`} {
		req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/exec/stream", strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+tok)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		var got map[string]string
		_ = json.NewDecoder(resp.Body).Decode(&got)
		resp.Body.Close()
		if resp.StatusCode != http.StatusBadRequest {
			t.Errorf("%s: got %d, want 400", body, resp.StatusCode)
		}
		if got["error"] == "" {
			t.Errorf("%s: no error message", body)
		}
	}
}

func TestFirstNCharsTruncatesOnRunes(t *testing.T) {
	if got := firstNChars("  echo\nhi  ", 80); got != "echo hi" {
		t.Errorf("got %q", got)
	}
	long := strings.Repeat("é", 100)
	got := firstNChars(long, 80)
	if !strings.HasSuffix(got, "...") || len([]rune(strings.TrimSuffix(got, "..."))) != 80 {
		t.Errorf("got %d runes: %q", len([]rune(got)), got)
	}
}

// pairedToken pairs the store and returns the token, so an act test can send
// a real credential rather than reaching into the store's internals.
func pairedToken(t *testing.T, store *Store) string {
	t.Helper()
	code := strconv.Itoa(482917)
	if err := store.WritePairing(code); err != nil {
		t.Fatal(err)
	}
	tok, err := store.ClaimPairing(code)
	if err != nil {
		t.Fatal(err)
	}
	return tok
}
