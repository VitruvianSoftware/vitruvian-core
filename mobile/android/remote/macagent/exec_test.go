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
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// argvFor is separated from running precisely so this test exists: the
// `claude` kind cannot be exercised for real -- launching an agent from a
// unit test is neither fast nor safe -- but the argv it would launch, and
// the three-minute budget it gets, can be pinned exactly.

func TestArgvForEachKind(t *testing.T) {
	for _, c := range []struct {
		kind    string
		command string
		want    []string
		timeout time.Duration
	}{
		// A LOGIN shell. Without -l, PATH is launchd's and every Homebrew
		// binary is "command not found" for a command that plainly works in
		// the user's terminal.
		{"shell", "echo hi", []string{"/bin/zsh", "-lc", "echo hi"}, 60 * time.Second},
		{"applescript", `display notification "x"`, []string{"osascript", "-e", `display notification "x"`}, 60 * time.Second},
		{"shortcut", "Start Focus", []string{"shortcuts", "run", "Start Focus"}, 60 * time.Second},
		// A model call, not a command: minutes, not seconds.
		{"claude", "summarise the diff", []string{"claude", "-p", "summarise the diff", "--output-format", "text"}, 180 * time.Second},
	} {
		argv, timeout, err := argvFor(c.kind, c.command)
		if err != nil {
			t.Fatalf("%s: %v", c.kind, err)
		}
		if strings.Join(argv, "\x00") != strings.Join(c.want, "\x00") {
			t.Errorf("%s argv = %q, want %q", c.kind, argv, c.want)
		}
		if timeout != c.timeout {
			t.Errorf("%s timeout = %s, want %s", c.kind, timeout, c.timeout)
		}
	}

	// The command is never concatenated into a program name, so an unknown
	// kind is refused rather than guessed at.
	if _, _, err := argvFor("rm", "-rf /"); err == nil {
		t.Error("an unknown kind was accepted")
	}
}

func TestClampTimeoutLowersButDoesNotRaise(t *testing.T) {
	def := 60 * time.Second
	if got := clampTimeout(0, def); got != def {
		t.Errorf("unset: %s", got)
	}
	if got := clampTimeout(-5, def); got != def {
		t.Errorf("negative: %s", got)
	}
	if got := clampTimeout(5, def); got != 5*time.Second {
		t.Errorf("lowering: %s", got)
	}
	// Raising past the cap is allowed up to maxTimeoutSec and no further: a
	// command left running by a phone that has gone out of range is a
	// process nobody will reap.
	if got := clampTimeout(100000, def); got != maxTimeoutSec*time.Second {
		t.Errorf("capped: %s", got)
	}
	// A claude call may exceed the shell default, because its own default
	// already does.
	if got := clampTimeout(240, 180*time.Second); got != 240*time.Second {
		t.Errorf("claude: %s", got)
	}
}

func TestCap64(t *testing.T) {
	s, truncated := cap64("hi\n")
	if s != "hi\n" || truncated {
		t.Errorf("short output: %q %v", s, truncated)
	}
	big := strings.Repeat("x", maxOutput+1)
	s, truncated = cap64(big)
	if len(s) != maxOutput || !truncated {
		t.Errorf("long output: %d bytes, truncated=%v", len(s), truncated)
	}
}

func TestFirstLineIsWhatAReasonIsMadeOf(t *testing.T) {
	// Docker's real refusal: one useful sentence, then advice. The phone has
	// room for the sentence.
	out := "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?\nSee 'docker run --help'.\n"
	if got := firstLine(out); got != "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" {
		t.Errorf("got %q", got)
	}
	if firstLine("   \n\n") != "" {
		t.Error("whitespace is not a reason")
	}
}

// runAct is exercised for real, but only with commands this test can afford
// to run: an echo and a false. The kinds that reach out to the machine or a
// model are covered by argvFor above.
func TestRunActReportsExitCodesRatherThanErrors(t *testing.T) {
	// The shell kind is /bin/zsh by design (it is the Mac's login shell) and
	// the Linux CI runner has no such file. Skipping there is honest about
	// what CI proves: this assertion is exercised on a Mac, by `bazel test`
	// on the machine the agent runs on, and nowhere else.
	if _, err := os.Stat("/bin/zsh"); err != nil {
		t.Skip("no /bin/zsh on this machine; the shell kind is macOS-only")
	}

	ok, err := runAct(t.Context(), execRequest{Kind: "shell", Command: "echo hi"})
	if err != nil {
		t.Fatal(err)
	}
	if ok.ExitCode != 0 || ok.Stdout != "hi\n" {
		t.Errorf("echo: %+v", ok)
	}

	// --exec-dir: under launchd the cwd is ~, where `bazel run` has no
	// workspace. Both exec paths (one-shot and streaming) must honour it.
	dir, _ := filepath.EvalSymlinks(t.TempDir())
	execDir = dir
	t.Cleanup(func() { execDir = "" })
	pwd, err := runAct(t.Context(), execRequest{Kind: "shell", Command: "pwd"})
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimSpace(pwd.Stdout); got != dir {
		t.Errorf("exec-dir: one-shot ran in %q, want %q", got, dir)
	}
	// runStream closes the channel itself once the process is gone.
	lines := make(chan streamLine, 16)
	runStream(t.Context(), execRequest{Kind: "shell", Command: "pwd"}, lines)
	var streamed string
	for l := range lines {
		if l.Stream == "stdout" {
			streamed = strings.TrimSpace(l.Text)
		}
	}
	if streamed != dir {
		t.Errorf("exec-dir: stream ran in %q, want %q", streamed, dir)
	}
	execDir = ""
	if ok.Truncated {
		t.Error("three bytes were reported truncated")
	}

	// A command that fails is a 200 with an exit code, not an error: the
	// phone shows the code and the stderr, which is the useful outcome.
	bad, err := runAct(t.Context(), execRequest{Kind: "shell", Command: "exit 42"})
	if err != nil {
		t.Fatal(err)
	}
	if bad.ExitCode != 42 {
		t.Errorf("exit 42: %+v", bad)
	}

	// A timeout is -1, which no process produces, so a client can tell
	// "killed by us" from "exited non-zero".
	slow, err := runAct(t.Context(), execRequest{Kind: "shell", Command: "sleep 5", TimeoutSeconds: 1})
	if err != nil {
		t.Fatal(err)
	}
	if slow.ExitCode != -1 || !strings.Contains(slow.Stderr, "timed out") {
		t.Errorf("timeout: %+v", slow)
	}
	if slow.DurationMS > 4000 {
		t.Errorf("the timeout did not bound the command: %d ms", slow.DurationMS)
	}
}

func TestToolPresenceUsesPath(t *testing.T) {
	dir := t.TempDir()
	fake := filepath.Join(dir, "xcodebuild")
	if err := os.WriteFile(fake, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir)
	got := toolPresence([]string{"xcodebuild", "definitely-not-a-tool"})
	// The fake exits 0, so it counts as a real Xcode; the shim case below does not.
	if !got.Tools["xcodebuild"].Available || got.Tools["xcodebuild"].Path != fake {
		t.Errorf("present tool: %+v", got.Tools["xcodebuild"])
	}
	if got.Tools["definitely-not-a-tool"].Available {
		t.Error("absent tool reported present")
	}
	// A shim that is on PATH but exits non-zero, like Command Line Tools'
	// /usr/bin/xcodebuild without Xcode, must NOT count as present.
	if err := os.WriteFile(fake, []byte("#!/bin/sh\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if toolPresence([]string{"xcodebuild"}).Tools["xcodebuild"].Available {
		t.Error("xcodebuild shim that cannot run reported as present")
	}
}
