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
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/VitruvianSoftware/vitruvian-core/mobile/android/remote/macagent/metrics"
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
// execDir is where act commands run. Under launchd the agent's own cwd is ~,
// so a macro like `bazel run //:tidy` fails with "not within a workspace"
// unless --exec-dir points at the repo. Empty keeps the process cwd.
var execDir string

func runAct(ctx context.Context, req execRequest) (execResult, error) {
	argv, def, err := argvFor(req.Kind, req.Command)
	if err != nil {
		return execResult{}, err
	}
	return runArgv(ctx, argv, clampTimeout(req.TimeoutSeconds, def)), nil
}

// resumeArgv is POST /v1/claude/resume: the same `claude -p` as the exec
// kind, with --resume in front of it.
//
// Its own function rather than a fifth exec kind, because the contract's four
// kinds take one string and this takes two -- and a kind reachable from
// /v1/exec with an empty session id would run `claude --resume "" ...`, which
// resumes something arbitrary rather than failing.
func resumeArgv(sessionID, prompt string) []string {
	return []string{"claude", "--resume", sessionID, "-p", prompt, "--output-format", "text"}
}

// claudeResumeTimeoutSec is the contract's 300 s. Longer than a plain model
// call because resuming replays a session's context first.
const claudeResumeTimeoutSec = 300

// runArgv is runAct once the argv and the bound are settled. Split out so
// /v1/claude/resume can share every part of this -- the timeout handling, the
// output cap, the -1 that distinguishes "we killed it" from "it exited" --
// without going through the kind dispatch.
func runArgv(ctx context.Context, argv []string, limit time.Duration) execResult {
	runCtx, cancel := context.WithTimeout(ctx, limit)
	defer cancel()
	cmd := exec.CommandContext(runCtx, argv[0], argv[1:]...)
	cmd.Dir = execDir
	var so, se bytes.Buffer
	cmd.Stdout, cmd.Stderr = &so, &se

	start := time.Now()
	err := cmd.Run()
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
	return res
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

// toolPresence answers "is this program on PATH" for each name. LookPath,
// not a shell `which`: it is the exact resolution exec uses, so a tool the
// agent reports present is one it can run.
func toolPresence(names []string) metrics.Tools {
	t := metrics.Tools{Tools: map[string]metrics.Tool{}}
	for _, n := range names {
		p, err := exec.LookPath(n)
		avail := err == nil
		// Command Line Tools ships /usr/bin/xcodebuild as a shim that only
		// prints "requires Xcode" and exits 1 when Xcode itself is absent.
		// On the path is not the same as usable, so Xcode is confirmed by
		// asking it -- the one tool here where the shim makes LookPath lie.
		if avail && n == "xcodebuild" {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			avail = exec.CommandContext(ctx, p, "-version").Run() == nil
			cancel()
		}
		t.Tools[n] = metrics.Tool{Available: avail, Path: p}
	}
	return t
}

// runToolWithin is runTool with its own bound, for the few tools (agy) that
// go to the network and legitimately take longer than the fast commands.
func runToolWithin(ctx context.Context, limit time.Duration, name string, args ...string) (string, string, error) {
	ctx, cancel := context.WithTimeout(ctx, limit)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

// --- streaming act (v1.2) ------------------------------------------------

// Timeouts for POST /v1/exec/stream. Far longer than the buffered endpoint's,
// and deliberately: the reason to stream is that the command takes minutes,
// and a `bazel test //...` cut off at 300 s is worse than useless. The caller
// may still ask for less, and may not ask for more than an hour.
const (
	defaultStreamTimeoutSec = 600
	maxStreamTimeoutSec     = 3600
)

// streamLine is one `event: line` payload.
type streamLine struct {
	Stream string `json:"stream"`
	Text   string `json:"text"`
}

// streamExit is the `event: exit` payload, and is always the last event.
type streamExit struct {
	ExitCode   int   `json:"exit_code"`
	DurationMS int64 `json:"duration_ms"`
}

// clampStreamTimeout is clampTimeout against the streaming bounds.
func clampStreamTimeout(requested int) time.Duration {
	if requested <= 0 {
		return defaultStreamTimeoutSec * time.Second
	}
	if requested > maxStreamTimeoutSec {
		requested = maxStreamTimeoutSec
	}
	return time.Duration(requested) * time.Second
}

// runStream runs one act request and sends each line of output to lines as
// it is produced, closing the channel once the process has exited and both
// pipes are drained. It returns the exit code and how long the run took.
//
// Three things here are not what the obvious version would do, and each is a
// bug someone would otherwise hit:
//
//   - The child starts in its own PROCESS GROUP (Setpgid), and cancelling
//     kills the group with a negative pid rather than the child. `zsh -lc
//     'sleep 30'` execs into sleep or forks it; killing only the shell leaves
//     the sleep running with no parent, and a phone that walked out of range
//     leaks a process per cancelled command. This is how Cancel cancels.
//   - stdout and stderr are scanned by two goroutines feeding ONE channel, so
//     the order the caller sees is the order the lines were produced.
//     Draining one pipe first would hold back every stderr line until the end.
//   - The scanner buffer is raised to maxOutput. bufio's 64 KiB default turns
//     one very long line -- a minified bundle, a base64 blob -- into an error
//     that silently ends the stream.
func runStream(ctx context.Context, req execRequest, lines chan<- streamLine) (int, time.Duration) {
	defer close(lines)

	argv, _, err := argvFor(req.Kind, req.Command)
	if err != nil {
		// Not reachable in practice: the handler validates the kind before
		// it commits to an event stream, because a 400 is only possible
		// before the first byte. Kept as an exit event rather than a panic.
		lines <- streamLine{Stream: "stderr", Text: err.Error()}
		return -1, 0
	}
	limit := clampStreamTimeout(req.TimeoutSeconds)
	runCtx, cancel := context.WithTimeout(ctx, limit)
	defer cancel()

	// exec.Command, not CommandContext: CommandContext kills the child only,
	// and the whole point here is to kill the group.
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Dir = execDir
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		lines <- streamLine{Stream: "stderr", Text: "vitruvian-remote-agent: " + err.Error()}
		return -1, 0
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		lines <- streamLine{Stream: "stderr", Text: "vitruvian-remote-agent: " + err.Error()}
		return -1, 0
	}

	start := time.Now()
	if err := cmd.Start(); err != nil {
		lines <- streamLine{Stream: "stderr", Text: "vitruvian-remote-agent: " + err.Error()}
		return -1, time.Since(start)
	}

	// The killer. It outlives nothing: done closes once the process has been
	// waited for, so a finished command leaves no goroutine parked on a
	// context that may never be cancelled.
	done := make(chan struct{})
	go func() {
		select {
		case <-runCtx.Done():
			killGroup(cmd.Process.Pid)
		case <-done:
		}
	}()

	var wg sync.WaitGroup
	scan := func(r io.Reader, name string) {
		defer wg.Done()
		sc := bufio.NewScanner(r)
		sc.Buffer(make([]byte, 0, 64<<10), maxOutput)
		for sc.Scan() {
			lines <- streamLine{Stream: name, Text: sc.Text()}
		}
		if err := sc.Err(); err != nil && !errors.Is(err, os.ErrClosed) {
			lines <- streamLine{Stream: "stderr", Text: "vitruvian-remote-agent: " + name + ": " + err.Error()}
		}
	}
	wg.Add(2)
	go scan(stdout, "stdout")
	go scan(stderr, "stderr")
	wg.Wait()

	err = cmd.Wait()
	close(done)
	dur := time.Since(start)

	code := 0
	switch {
	case errors.Is(runCtx.Err(), context.DeadlineExceeded):
		code = -1
		lines <- streamLine{Stream: "stderr", Text: fmt.Sprintf("vitruvian-remote-agent: timed out after %s", limit)}
	case errors.Is(runCtx.Err(), context.Canceled):
		// The client hung up. Said out loud rather than left as a bare -1,
		// because in the log this is the difference between "the phone
		// cancelled" and "the command crashed".
		code = -1
		lines <- streamLine{Stream: "stderr", Text: "vitruvian-remote-agent: cancelled by the client; process group killed"}
	case err != nil:
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			code = ee.ExitCode()
		} else {
			code = -1
			lines <- streamLine{Stream: "stderr", Text: "vitruvian-remote-agent: " + err.Error()}
		}
	}
	return code, dur
}

// killGroup kills a process group by its leader's pid. TERM first, so a shell
// script gets to run its trap, then KILL a moment later for anything that
// ignored it -- which is what a wedged process does by definition.
func killGroup(pid int) {
	if pid <= 0 {
		return
	}
	_ = syscall.Kill(-pid, syscall.SIGTERM)
	time.Sleep(200 * time.Millisecond)
	_ = syscall.Kill(-pid, syscall.SIGKILL)
}

// --- the v1.2 fixed argv -------------------------------------------------
//
// Everything below is sampling or a named action, so it is back on the v1.0
// side of the line: fixed programs, fixed flags, and the only caller input
// (a repo, a number, an app name) passed as its own argument where the tool
// treats it as a value and never as part of a command line.

func ghSearchArgv(author string) []string {
	return []string{
		"search", "prs", "--author", author, "--state", "open",
		"--json", "number,repository,title,url,updatedAt", "--limit", "20",
	}
}

// ghSearchRepoArgv is the same query for a repo named by --gh-extra-repos:
// every open PR, whoever wrote it. That is the point of the flag -- the PRs
// worth a glance from a phone are not only one's own.
func ghSearchRepoArgv(repo string) []string {
	return []string{
		"search", "prs", "--repo", repo, "--state", "open",
		"--json", "number,repository,title,url,updatedAt", "--limit", "20",
	}
}

func ghViewArgv(repo string, number int) []string {
	return []string{
		"pr", "view", strconv.Itoa(number), "--repo", repo,
		"--json", "isDraft,headRefName,baseRefName,mergeStateStatus,reviewDecision,statusCheckRollup,autoMergeRequest,author",
	}
}

// prActionArgv is the fixed argv for each allowed PR action, in the same
// shape as powerArgv and for the same reason: there is no action a caller can
// name that is not one of these four, and no way to smuggle a flag into one.
func prActionArgv(action, repo string, number int) ([]string, error) {
	n := strconv.Itoa(number)
	switch action {
	case "approve":
		return []string{"pr", "review", n, "--repo", repo, "--approve"}, nil
	case "merge":
		return []string{"pr", "merge", n, "--repo", repo, "--merge"}, nil
	case "auto_merge":
		return []string{"pr", "merge", n, "--repo", repo, "--auto", "--merge"}, nil
	case "ready":
		return []string{"pr", "ready", n, "--repo", repo}, nil
	default:
		return nil, fmt.Errorf("unknown action %q (want approve, merge, auto_merge or ready)", action)
	}
}

// kubectlArgs prefixes the cluster selection the agent was started with. The
// same two flags /v1/k8s needs, and for the same reason: the lab cluster's
// config is not ~/.kube/config and its context is not the current one.
func kubectlArgs(kubeconfig, kubeContext string, rest ...string) []string {
	args := []string{}
	if kubeconfig != "" {
		args = append(args, "--kubeconfig", kubeconfig)
	}
	if kubeContext != "" {
		args = append(args, "--context", kubeContext)
	}
	return append(args, rest...)
}

// argoSyncArgv patches an Application with an empty sync operation, which is
// how the ArgoCD controller is asked to sync without the argocd CLI or a
// session against its API. initiatedBy names this agent, so the history in
// the ArgoCD UI says who did it rather than "unknown".
func argoSyncArgv(kubeconfig, kubeContext, namespace, name string) []string {
	return kubectlArgs(kubeconfig, kubeContext, "-n", namespace, "patch", "application", name,
		"--type", "merge", "-p", `{"operation":{"initiatedBy":{"username":"vitruvian-remote"},"sync":{}}}`)
}

// --- screen peek ---------------------------------------------------------

// screenshotJPEG captures the main display and returns the JPEG bytes,
// downscaled to width.
//
// Two commands, both writing to a file under os.MkdirTemp: screencapture
// cannot write to a pipe, and sips edits in place. The directory is removed
// on the way out, so a screenshot never outlives the request that asked for
// it -- which matters more here than anywhere else in this agent, because
// this is the one endpoint whose output is a picture of whatever was on the
// screen, banking tab included.
//
// The permission failure is the interesting path, and it looks like this on
// macOS 26 -- verified on this machine, where Screen Recording is NOT granted
// to the agent:
//
//	$ screencapture -x -t jpg /tmp/x.jpg
//	could not create image from display <exit 1>
//
// So it is an exit code and a sentence, not a black picture, and it is
// recognised by that sentence rather than by "screencapture failed": a full
// disk and a bad path fail too, and telling someone to open the Screen
// Recording pane would send them to the wrong place. A run that exits 0 and
// leaves no file is treated the same way, because a version of macOS that
// refuses silently would otherwise return an empty JPEG.
func screenshotJPEG(ctx context.Context, width int) ([]byte, error) {
	if width < minScreenWidth {
		width = minScreenWidth
	}
	if width > maxScreenWidth {
		width = maxScreenWidth
	}
	dir, err := os.MkdirTemp("", "vitruvian-remote-screen")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(dir)
	path := filepath.Join(dir, "screen.jpg")

	// -x: no shutter sound. -t jpg: a phone does not want a 12 MB PNG.
	if _, stderr, err := runToolWithin(ctx, 15*time.Second, "screencapture", "-x", "-t", "jpg", path); err != nil {
		if isScreenDenied(stderr) {
			return nil, errScreenRecordingDenied
		}
		return nil, fmt.Errorf("screencapture: %s", firstOr(firstLine(stderr), err.Error()))
	}
	fi, err := os.Stat(path)
	if err != nil || fi.Size() == 0 {
		// Exited 0 and produced nothing. Not seen on macOS 26, but a silent
		// refusal is the only thing this can reasonably be.
		return nil, errScreenRecordingDenied
	}
	if _, stderr, err := runToolWithin(ctx, 15*time.Second, "sips", "--resampleWidth", strconv.Itoa(width), path); err != nil {
		return nil, fmt.Errorf("sips: %s", firstOr(firstLine(stderr), err.Error()))
	}
	return os.ReadFile(path)
}

// Screen width bounds, from the contract. Below 200 the picture is unusable
// and above 1600 it is a megabyte over a phone network for no more detail
// than the screen has.
const (
	minScreenWidth     = 200
	maxScreenWidth     = 1600
	defaultScreenWidth = 800
)

// errScreenRecordingDenied is the one failure worth its own type, because it
// has a next step and every other one does not.
var errScreenRecordingDenied = errors.New(screenDeniedReason)

// screenDeniedReason is verbatim from the contract: the phone shows it, and
// it names the exact pane in System Settings.
const screenDeniedReason = "Screen Recording is not granted to the agent — System Settings → Privacy & Security → Screen Recording"

// isScreenDenied recognises the permission refusal in screencapture's own
// words. Matched loosely (lower-cased, on the distinctive fragment) because
// the exact sentence has changed across macOS releases and the phrase
// "create image" has survived every one of them.
func isScreenDenied(stderr string) bool {
	s := strings.ToLower(stderr)
	return strings.Contains(s, "could not create image") ||
		strings.Contains(s, "not authorized") ||
		strings.Contains(s, "screen recording")
}

func firstOr(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
