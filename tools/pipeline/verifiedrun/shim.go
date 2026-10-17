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

// The bazel wrapper ("shim").
//
// WHY. The tests CI runs on a pull request are chosen in two places: the
// planner (which presubmit units) and tools/ci/affected-targets.sh (which
// targets build-test runs). Both call `bazel` themselves. Copying their logic
// here would drift; so the verified run runs them unchanged, with a `bazel`
// first on PATH that is this binary. For build and test it appends the flags
// that make the run remote-only, and it logs, per invocation, the BuildBuddy
// link and Bazel's own count of where each process ran. That log is the
// evidence the record is built from -- not anything a script prints.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

const (
	envRealBazel = "VERIFIED_RUN_REAL_BAZEL"
	envLog       = "VERIFIED_RUN_LOG"
	envStartup   = "VERIFIED_RUN_STARTUP"
	envStrict    = "VERIFIED_RUN_STRICT"
	envLane      = "VERIFIED_RUN_LANE"
)

// invocation is one bazel build/test the shim saw, as logged.
type invocation struct {
	Lane       string   `json:"lane"`
	Command    string   `json:"command"`
	Targets    []string `json:"targets"`
	Exit       int      `json:"exit"`
	URL        string   `json:"url"`
	Processes  string   `json:"processes"`
	SawSummary bool     `json:"saw_summary"`
}

// buildCommands are the commands that execute actions, so the only ones whose
// flags and output matter here.
var buildCommands = map[string]bool{"build": true, "test": true, "coverage": true}

// isKeyHeader matches the BuildBuddy key headers CI's scripts pass. The key
// comes from user.bazelrc instead; a second header for the same name would be
// comma-joined by Bazel ("KEY,KEY") and break auth.
func isKeyHeader(arg string) bool {
	return strings.HasPrefix(arg, "--remote_header=x-buildbuddy-api-key=") ||
		strings.HasPrefix(arg, "--bes_header=x-buildbuddy-api-key=")
}

// shimArgs rewrites one bazel command line. Startup options go first; for
// build/test the strict flags go LAST (before a `--`, if any) so nothing a
// script or unit passes can override them.
func shimArgs(args, startup, strict []string) (out []string, command string, targets []string) {
	i := 0
	for i < len(args) && strings.HasPrefix(args[i], "-") {
		i++
	}
	out = append(out, startup...)
	out = append(out, args[:i]...)
	if i == len(args) {
		return out, "", nil
	}
	command = args[i]
	rest := args[i+1:]
	if !buildCommands[command] {
		return append(append(out, command), rest...), command, nil
	}
	out = append(out, command)
	var tail []string
	afterDashes := false
	for _, a := range rest {
		switch {
		case afterDashes:
			tail = append(tail, a)
			targets = append(targets, a)
		case a == "--":
			afterDashes = true
			tail = append(tail, a)
		case isKeyHeader(a):
		case strings.HasPrefix(a, "-"):
			out = append(out, a)
		default:
			out = append(out, a)
			targets = append(targets, a)
		}
	}
	// A --config the caller already passed is not expanded a second time:
	// Bazel counts repeatable flags in it twice and warns about it.
	have := map[string]bool{}
	for _, a := range out {
		have[a] = true
	}
	for _, f := range strict {
		if strings.HasPrefix(f, "--config=") && have[f] {
			continue
		}
		out = append(out, f)
	}
	return append(out, tail...), command, targets
}

var (
	ansiRe      = regexp.MustCompile(`\x1b\[[0-9;?]*[A-Za-z]`)
	streamingRe = regexp.MustCompile(`Streaming build results to: (https://\S+)`)
	processesRe = regexp.MustCompile(`INFO: \d+ process(?:es)?(?:: (.*?))?\.?\s*$`)
)

// scanLine picks the two facts the record needs out of one line of Bazel's
// output: the BuildBuddy link, and the "N processes: ..." summary.
func scanLine(line string, inv *invocation) {
	line = ansiRe.ReplaceAllString(strings.TrimRight(line, "\r"), "")
	if m := streamingRe.FindStringSubmatch(line); m != nil {
		inv.URL = m[1]
	}
	if m := processesRe.FindStringSubmatch(line); m != nil {
		inv.SawSummary = true
		inv.Processes = strings.TrimSpace(m[1])
	}
}

func splitEnvList(v string) []string {
	if v == "" {
		return nil
	}
	return strings.Split(v, "\n")
}

// shimMain is what runs when a script calls `bazel`.
func shimMain(args []string) int {
	real := os.Getenv(envRealBazel)
	if real == "" {
		fmt.Fprintln(os.Stderr, "verified-run: the bazel wrapper was run without the real bazel's path")
		return 2
	}
	out, command, targets := shimArgs(args, splitEnvList(os.Getenv(envStartup)), splitEnvList(os.Getenv(envStrict)))
	cmd := exec.Command(real, out...)
	cmd.Stdin, cmd.Stdout = os.Stdin, os.Stdout
	if !buildCommands[command] {
		cmd.Stderr = os.Stderr
		return exitCode(cmd.Run())
	}

	inv := invocation{Lane: os.Getenv(envLane), Command: command, Targets: targets}
	pr, pw := io.Pipe()
	cmd.Stderr = pw
	done := make(chan struct{})
	go func() {
		defer close(done)
		sc := bufio.NewScanner(pr)
		sc.Buffer(make([]byte, 64*1024), 4*1024*1024)
		for sc.Scan() {
			fmt.Fprintln(os.Stderr, sc.Text())
			scanLine(sc.Text(), &inv)
		}
		_, _ = io.Copy(os.Stderr, pr)
	}()
	err := cmd.Run()
	_ = pw.Close()
	<-done
	inv.Exit = exitCode(err)

	if path := os.Getenv(envLog); path != "" {
		if f, ferr := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600); ferr == nil {
			_ = json.NewEncoder(f).Encode(inv)
			_ = f.Close()
		} else {
			fmt.Fprintf(os.Stderr, "verified-run: could not log this bazel run: %v\n", ferr)
			if inv.Exit == 0 {
				return 1
			}
		}
	}
	return inv.Exit
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return ee.ExitCode()
	}
	return 1
}

// readInvocations reads the shim's log back.
func readInvocations(path string) ([]invocation, error) {
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var invs []invocation
	dec := json.NewDecoder(f)
	for dec.More() {
		var inv invocation
		if err := dec.Decode(&inv); err != nil {
			return nil, fmt.Errorf("the run log is unreadable: %w", err)
		}
		invs = append(invs, inv)
	}
	return invs, nil
}

// allowedKinds are the only places Bazel may report work happening for a run
// to count as remote. "internal" is Bazel's own bookkeeping (symlinks, status
// files). "action cache hit" is a build step this output base already holds;
// tests never count that way because the run passes --nocache_test_results.
// Anything else -- darwin-sandbox, local, worker, disk cache hit -- means work
// happened on the laptop.
var allowedKinds = map[string]bool{
	"internal":         true,
	"remote":           true,
	"remote cache hit": true,
	"action cache hit": true,
}

// checkInvocation says why one bazel run cannot count as a remote run, or nil.
func checkInvocation(inv invocation) error {
	name := fmt.Sprintf("bazel %s (%s)", inv.Command, laneLabel(inv.Lane))
	if inv.Exit != 0 && inv.Exit != 4 {
		return fmt.Errorf("%s failed with exit code %d", name, inv.Exit)
	}
	if inv.URL == "" {
		return fmt.Errorf("%s has no BuildBuddy link, so there is no proof of where it ran", name)
	}
	if !inv.SawSummary {
		if inv.Exit == 4 {
			return nil // "no test targets": nothing ran
		}
		return fmt.Errorf("%s did not report where its work ran", name)
	}
	if inv.Processes == "" {
		return nil // "INFO: 0 processes."
	}
	for _, part := range strings.Split(inv.Processes, ",") {
		part = strings.TrimSpace(part)
		n, kind, ok := strings.Cut(part, " ")
		if !ok {
			return fmt.Errorf("%s: could not read %q in Bazel's process summary", name, part)
		}
		if !allowedKinds[kind] {
			return fmt.Errorf("%s ran %s process(es) on this machine (%q), not on the remote machines", name, n, kind)
		}
	}
	return nil
}

func laneLabel(lane string) string {
	if lane == "" {
		return "no lane"
	}
	return lane
}
