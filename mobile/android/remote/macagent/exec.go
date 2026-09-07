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
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// THIS FILE IS THE ONLY PLACE THE AGENT EXECUTES ANYTHING. No other file
// imports os/exec, and a change that adds one should be rejected in review.
//
// v1.0 could say more than that: every argv was fixed and nothing from the
// network reached one. v1.1 gives that up on purpose -- POST /v1/exec runs
// what the phone asks for -- so the honest statement is narrower and worth
// being precise about:
//
//   - Sampling (readCmd and its callers in sampler.go) still has fixed
//     names and fixed arguments. No request reaches those argv.
//   - Acting (runAct, and the clipboard/audio/power helpers) runs caller
//     input, and is reachable ONLY through a bearer token issued by
//     pairing, which requires physical access to this Mac.
//
// So the boundary is the token, not the absence of exec. Anyone who can
// pair can run commands as this user; that is the feature. Everything an
// act path runs is logged first (see logAct), so the Mac keeps a record.

// cmdTimeout bounds the fast sampling commands; anything past it is a wedged
// tool, not a slow one. top gets its own, longer bound: two samples take
// ~4 s at normal priority and 14-17 s if the process is ever demoted to
// background QoS, and a timeout that kills it produces a CPU that is never
// ready. The optional tools (limactl, docker, kubectl) get 5 s, because a
// stopped daemon can hang far longer than a running one takes to answer.
const (
	cmdTimeout  = 10 * time.Second
	topTimeout  = 30 * time.Second
	toolTimeout = 5 * time.Second
)

// maxOutput caps each of stdout and stderr on an act call. 64 KiB is
// generous for a command's output and small enough that a runaway `yes`
// cannot fill the phone's memory or the agent's.
const maxOutput = 64 << 10

func run(ctx context.Context, name string, args ...string) (string, error) {
	return runWithin(ctx, cmdTimeout, name, args...)
}

func runWithin(ctx context.Context, limit time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, limit)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).Output()
	return string(out), err
}

// runTool is runWithin for the optional sources, and differs in one way that
// matters: it keeps stderr. "Cannot connect to the Docker daemon" is the
// entire value of asking, and a helper that discarded it would leave the
// phone with an empty list and no reason.
func runTool(ctx context.Context, name string, args ...string) (stdout, stderr string, err error) {
	ctx, cancel := context.WithTimeout(ctx, toolTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	var so, se bytes.Buffer
	cmd.Stdout, cmd.Stderr = &so, &se
	err = cmd.Run()
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		err = fmt.Errorf("%s: no answer within %s", name, toolTimeout)
	}
	return so.String(), se.String(), err
}

// firstLine is what a reason is made of. Docker prints one useful sentence
// and then a paragraph of advice; a phone has room for the sentence.
func firstLine(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	line, _, _ := strings.Cut(s, "\n")
	return strings.TrimSpace(line)
}

// --- act -----------------------------------------------------------------

// execRequest is the body of POST /v1/exec.
type execRequest struct {
	Kind           string `json:"kind"`
	Command        string `json:"command"`
	TimeoutSeconds int    `json:"timeout_seconds"`
}

// execResult is its reply. A non-zero ExitCode is a 200: the command ran and
// failed, which is an answer, not an HTTP error.
type execResult struct {
	ExitCode   int    `json:"exit_code"`
	Stdout     string `json:"stdout"`
	Stderr     string `json:"stderr"`
	DurationMS int64  `json:"duration_ms"`
	Truncated  bool   `json:"truncated"`
}

// Timeouts, in seconds. The caller may lower the default, never raise it
// past maxTimeout -- an unbounded command from a phone that has since gone
// out of range is a process nobody will ever reap.
const (
	defaultTimeoutSec = 60
	claudeTimeoutSec  = 180
	maxTimeoutSec     = 300
)

// argvFor turns a kind and a command into a fixed program and its arguments.
//
// Separated from the running so the dispatch can be tested without executing
// anything -- which is how the `claude` kind is covered: launching a real
// agent from a unit test is neither fast nor safe.
func argvFor(kind, command string) ([]string, time.Duration, error) {
	switch kind {
	case "shell":
		// A LOGIN shell (-l), so PATH is the one the user's terminal has.
		// Without it every Homebrew binary is missing and the phone gets
		// "command not found" for things that plainly exist.
		return []string{"/bin/zsh", "-lc", command}, defaultTimeoutSec * time.Second, nil
	case "applescript":
		return []string{"osascript", "-e", command}, defaultTimeoutSec * time.Second, nil
	case "shortcut":
		return []string{"shortcuts", "run", command}, defaultTimeoutSec * time.Second, nil
	case "claude":
		// A model call, not a command: minutes, not seconds. --output-format
		// text because the phone renders it as text.
		return []string{"claude", "-p", command, "--output-format", "text"}, claudeTimeoutSec * time.Second, nil
	default:
		return nil, 0, fmt.Errorf("unknown kind %q (want shell, applescript, shortcut or claude)", kind)
	}
}

// clampTimeout applies the caller's request to the kind's default: zero or
// negative means "use the default", anything above maxTimeout is capped.
func clampTimeout(requested int, def time.Duration) time.Duration {
	if requested <= 0 {
		return def
	}
	if requested > maxTimeoutSec {
		requested = maxTimeoutSec
	}
	return time.Duration(requested) * time.Second
}

// runAct runs one act request and always returns a result, including for a
// timeout: the phone needs to see how long it waited and why it stopped.
func runAct(ctx context.Context, req execRequest) (execResult, error) {
	argv, def, err := argvFor(req.Kind, req.Command)
	if err != nil {
		return execResult{}, err
	}
	limit := clampTimeout(req.TimeoutSeconds, def)

	runCtx, cancel := context.WithTimeout(ctx, limit)
	defer cancel()
	cmd := exec.CommandContext(runCtx, argv[0], argv[1:]...)
	var so, se bytes.Buffer
	cmd.Stdout, cmd.Stderr = &so, &se

	start := time.Now()
	err = cmd.Run()
	res := execResult{DurationMS: time.Since(start).Milliseconds()}
	res.Stdout, res.Truncated = cap64(so.String())
	stderr, truncErr := cap64(se.String())
	res.Stderr = stderr
	res.Truncated = res.Truncated || truncErr

	switch {
	case errors.Is(runCtx.Err(), context.DeadlineExceeded):
		// -1 is not an exit status any process produces, so a client can
		// tell "killed by us" from "exited non-zero".
		res.ExitCode = -1
		res.Stderr = strings.TrimSpace(res.Stderr + fmt.Sprintf("\nvitruvian-remote-agent: timed out after %s", limit))
	case err != nil:
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			res.ExitCode = ee.ExitCode()
		} else {
			// Never started at all -- a missing binary is the common one.
			res.ExitCode = -1
			res.Stderr = strings.TrimSpace(res.Stderr + "\nvitruvian-remote-agent: " + err.Error())
		}
	}
	return res, nil
}

// cap64 truncates to maxOutput and says whether it did. It cuts bytes, not
// runes, so a multi-byte character can be split at the boundary; the flag is
// the client's cue that the tail is missing either way.
func cap64(s string) (string, bool) {
	if len(s) <= maxOutput {
		return s, false
	}
	return s[:maxOutput], true
}

// pbpaste reads the Mac's clipboard.
func pbpaste(ctx context.Context) (string, error) {
	return runWithin(ctx, cmdTimeout, "pbpaste")
}

// pbcopy writes it. The text goes in on stdin, never in an argv: a clipboard
// full of a password would otherwise be visible in `ps` to every process on
// the machine.
func pbcopy(ctx context.Context, text string) error {
	ctx, cancel := context.WithTimeout(ctx, cmdTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "pbcopy")
	cmd.Stdin = strings.NewReader(text)
	return cmd.Run()
}

// setVolume sets the output volume, 0-100.
func setVolume(ctx context.Context, percent int) error {
	if percent < 0 {
		percent = 0
	}
	if percent > 100 {
		percent = 100
	}
	// Built from an int this function clamped, so nothing from the request
	// reaches the AppleScript as text.
	_, err := runWithin(ctx, cmdTimeout, "osascript", "-e", fmt.Sprintf("set volume output volume %d", percent))
	return err
}

// powerArgv is the fixed argv for each allowed power action. A map rather
// than a string built from the request: there is no action the caller can
// name that is not one of these two.
var powerArgv = map[string][]string{
	"sleep":   {"pmset", "sleepnow"},
	"restart": {"osascript", "-e", `tell app "System Events" to restart`},
}

func power(ctx context.Context, action string) error {
	argv, ok := powerArgv[action]
	if !ok {
		return fmt.Errorf("unknown action %q (want sleep or restart)", action)
	}
	_, err := runWithin(ctx, cmdTimeout, argv[0], argv[1:]...)
	return err
}
