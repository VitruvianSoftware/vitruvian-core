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

// verified-run runs the tests a pull request would run in CI, on the same
// remote build machines CI uses, and records a pass against the exact code
// (#3418, Step 2).
//
//	bazel run //tools/pipeline/verifiedrun
//	bazel run //tools/pipeline/verifiedrun -- --no-record
//
// See README.md for what it covers, what it leaves to CI, and how a record is
// meant to be checked.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/VitruvianSoftware/vitruvian-core/tools/pipeline/unitfile"
)

// Exit codes.
const (
	exitVerified    = 0 // passed remotely (and recorded, unless --no-record)
	exitNotVerified = 1 // a test failed, or the run cannot count as remote
	exitSetup       = 2 // could not start: dirty tree, no key, bad flags
	exitNotRecorded = 3 // passed remotely, but no record was written
)

// strictFlags make a build or test remote-only and tie it to the code. They
// go last on every build/test command line (see shimArgs), so they win.
//
// The three platform flags matter on a Mac: without them Bazel picks Mac
// toolchains and sends them to Linux machines. CI never needs them because
// its runners are Linux already.
func strictFlags(head, tree string) []string {
	return []string{
		"--config=remote",
		"--platforms=//tools/platforms:linux_x86_64",
		"--host_platform=//tools/platforms:linux_x86_64",
		"--extra_execution_platforms=//tools/platforms:linux_x86_64",
		"--spawn_strategy=remote",
		"--noremote_local_fallback",
		"--noremote_upload_local_results",
		"--disk_cache=",
		"--nocache_test_results",
		"--color=no",
		"--curses=no",
		"--build_metadata=ROLE=VERIFIED_RUN",
		"--build_metadata=REPO_URL=https://github.com/" + repoSlug,
		"--build_metadata=COMMIT_SHA=" + head,
		"--build_metadata=TREE_SHA=" + tree,
	}
}

// ---- git -------------------------------------------------------------------

func git(ctx context.Context, dir string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Dir = dir
	var out, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("git %s: %v: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return strings.TrimSpace(out.String()), nil
}

var hashRe = regexp.MustCompile(`^[0-9a-f]{40}([0-9a-f]{24})?$`)

// treeHash is git's hash of every file at HEAD. It is equal exactly when the
// files are byte-for-byte equal, whatever the commit message or how the
// commit was made, which is why the record keys on it.
func treeHash(ctx context.Context, dir string) (string, error) {
	t, err := git(ctx, dir, "rev-parse", "--verify", "HEAD^{tree}")
	if err != nil {
		return "", err
	}
	if !hashRe.MatchString(t) {
		return "", fmt.Errorf("unexpected tree hash %q", t)
	}
	return t, nil
}

// requireClean refuses uncommitted or untracked files: the tests would run
// on them, but the record would name HEAD's tree, which does not have them.
func requireClean(ctx context.Context, dir string) error {
	s, err := git(ctx, dir, "status", "--porcelain", "--untracked-files=normal")
	if err != nil {
		return err
	}
	if s != "" {
		return fmt.Errorf("the working tree has uncommitted or untracked files, so a pass would not describe HEAD. Commit or remove them first:\n%s", s)
	}
	return nil
}

// ---- BuildBuddy key ----------------------------------------------------------

const keyMarker = "x-buildbuddy-api-key="

func hasKey(path string) bool {
	b, err := os.ReadFile(path)
	return err == nil && bytes.Contains(b, []byte(keyMarker))
}

// keyStartup finds the laptop's BuildBuddy key without ever reading its
// value out. A worktree usually has no user.bazelrc, so the main checkout's
// is loaded with --bazelrc. Never both: two key headers are comma-joined by
// Bazel and break auth.
func keyStartup(workspace, mainCheckout string) ([]string, error) {
	if hasKey(filepath.Join(workspace, "user.bazelrc")) {
		return nil, nil
	}
	main := filepath.Join(mainCheckout, "user.bazelrc")
	if mainCheckout != "" && filepath.Clean(mainCheckout) != filepath.Clean(workspace) && hasKey(main) {
		return []string{"--bazelrc=" + main}, nil
	}
	return nil, errors.New("there is no BuildBuddy key in user.bazelrc (here or in the main checkout), so nothing can run on the remote machines. A local-only run is not offered: CI could not trust it")
}

// ---- plan ------------------------------------------------------------------

type planEntry struct {
	Name   string `json:"name"`
	Runner string `json:"runner"`
}

type planResult struct {
	IsDegraded   bool        `json:"is_degraded"`
	SweepReason  string      `json:"sweep_reason"`
	ChangedFiles []string    `json:"changed_files"`
	Matrix       []planEntry `json:"matrix"`
}

// classify splits the units the planner picked into the ones this run can
// verify the way CI runs them (a Linux runner with --config=remote) and the
// ones it must leave to CI, with the reason. Mirrors render.go in
// tools/pipeline/gen, which decides each unit's flags.
func classify(picked []planEntry, units map[string]unitfile.Unit) (covered []unitfile.Unit, left map[string]string, err error) {
	left = map[string]string{}
	for _, e := range picked {
		u, ok := units[e.Name]
		if !ok {
			return nil, nil, fmt.Errorf("the planner picked unit %q, but no pipeline_unit by that name was found", e.Name)
		}
		switch {
		case strings.HasPrefix(u.Runner, "macos") || strings.HasPrefix(u.Runner, "xcode"):
			left[u.Name] = "runs on a macOS runner; the remote machines are Linux"
		case u.NeedsEmulator:
			left[u.Name] = "needs an Android emulator"
		case len(u.Artifacts) > 0:
			left[u.Name] = "builds files CI uploads, and CI runs it with local execution"
		default:
			covered = append(covered, u)
		}
	}
	sort.Slice(covered, func(i, j int) bool { return covered[i].Name < covered[j].Name })
	return covered, left, nil
}

// ---- the run ---------------------------------------------------------------

// verifier is the run, with every outside effect behind a field so tests can
// drive it without Bazel, BuildBuddy or GitHub.
type verifier struct {
	out          io.Writer
	head, tree   string
	base         string
	plan         func(ctx context.Context) (planResult, error)
	units        map[string]unitfile.Unit
	runBuildTest func(ctx context.Context) (int, error)
	runUnit      func(ctx context.Context, u unitfile.Unit) (int, error)
	invocations  func() ([]invocation, error)
	record       func(ctx context.Context, r record) error // nil: --no-record
}

func (v *verifier) say(format string, a ...any) { fmt.Fprintf(v.out, format+"\n", a...) }

func (v *verifier) refuse(format string, a ...any) int {
	v.say("\nNOT VERIFIED: "+format, a...)
	v.say("Nothing was recorded.")
	return exitNotVerified
}

func (v *verifier) run(ctx context.Context) int {
	v.say("verified-run: commit %s, files (tree) %s", short(v.head), v.tree)
	v.say("Compared with %s, the merge base with origin/main.", short(v.base))

	p, err := v.plan(ctx)
	if err != nil {
		return v.refuse("the planner failed: %v", err)
	}
	if p.IsDegraded {
		return v.refuse("the planner could not work out what changed (%s). CI would run everything; fix the cause first.", p.SweepReason)
	}
	covered, left, err := classify(p.Matrix, v.units)
	if err != nil {
		return v.refuse("%v", err)
	}

	v.say("\n%d changed file(s). What runs here, and why:", len(p.ChangedFiles))
	v.say("  - build-test: the affected targets, chosen by tools/ci/affected-targets.sh exactly as on a PR.")
	for _, u := range covered {
		v.say("  - unit %s: picked by the planner; %d target(s).", u.Name, len(u.TestTargets))
	}
	if len(covered) == 0 {
		v.say("  - no presubmit units: the planner picked none this run can cover.")
	}
	names := make([]string, 0, len(left))
	for n := range left {
		names = append(names, n)
	}
	sort.Strings(names)
	if len(names) > 0 {
		v.say("Left to CI (not covered by this record):")
		for _, n := range names {
			v.say("  - unit %s: %s", n, left[n])
		}
	}
	v.say("Also left to CI: the fast checks and every other CI job (macOS build, race tests, lint, ...).\n")

	if rc, err := v.runBuildTest(ctx); err != nil || rc != 0 {
		return v.refuse("build-test did not pass (exit %d%s).", rc, errSuffix(err))
	}
	for _, u := range covered {
		if rc, err := v.runUnit(ctx, u); err != nil || rc != 0 {
			return v.refuse("unit %s did not pass (exit %d%s).", u.Name, rc, errSuffix(err))
		}
	}

	invs, err := v.invocations()
	if err != nil {
		return v.refuse("%v", err)
	}
	if len(invs) == 0 {
		v.say("\nNothing needed building or testing for this change, so there is nothing to record.")
		return exitVerified
	}
	for _, inv := range invs {
		if err := checkInvocation(inv); err != nil {
			return v.refuse("%v.", err)
		}
	}

	r := newRecord(v.head, v.tree, v.base, invs)
	v.say("\nPASSED on the remote machines: %d Bazel run(s), lanes %s.", len(invs), strings.Join(r.Lanes, ", "))
	v.say("Build results: %s", r.TargetURL)
	v.say("Record: context %q, %s", statusContext, r.description())

	if v.record == nil {
		v.say("Not recorded (--no-record).")
		return exitVerified
	}
	if err := v.record(ctx, r); err != nil {
		v.say("\nThe tests passed, but: %v", err)
		return exitNotRecorded
	}
	v.say("Recorded on commit %s.", short(v.head))
	return exitVerified
}

func errSuffix(err error) string {
	if err == nil {
		return ""
	}
	return ": " + err.Error()
}

// ---- wiring ----------------------------------------------------------------

// childEnv is the environment for every script and bazel call: the shim first
// on PATH, no runfiles variables from our own `bazel run`, and no GitHub
// tokens (nothing here should act on GitHub except the recorder).
func childEnv(shimDir string, extra ...string) []string {
	var env []string
	for _, kv := range withoutGitHubTokens(os.Environ()) {
		k, _, _ := strings.Cut(kv, "=")
		switch k {
		case "PATH", "RUNFILES_DIR", "RUNFILES_MANIFEST_FILE", "JAVA_RUNFILES", "GITHUB_STEP_SUMMARY", "GITHUB_OUTPUT":
			continue
		}
		env = append(env, kv)
	}
	env = append(env, "PATH="+shimDir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return append(env, extra...)
}

func runCmd(ctx context.Context, dir string, env []string, name string, args ...string) (int, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Dir, cmd.Env = dir, env
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	err := cmd.Run()
	if _, ok := err.(*exec.ExitError); ok {
		return exitCode(err), nil
	}
	return exitCode(err), err
}

// runfile resolves a $(rlocationpath) handed to us by the BUILD file.
func runfile(rloc string) (string, error) {
	var roots []string
	if d := os.Getenv("RUNFILES_DIR"); d != "" {
		roots = append(roots, d)
	}
	if exe, err := os.Executable(); err == nil {
		roots = append(roots, exe+".runfiles")
	}
	for _, r := range roots {
		p := filepath.Join(r, rloc)
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}
	return "", fmt.Errorf("cannot find %s in the runfiles; run this with `bazel run`", rloc)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "__shim" {
		os.Exit(shimMain(os.Args[2:]))
	}
	os.Exit(realMain())
}

func realMain() int {
	plannerLoc := flag.String("planner", "", "runfiles path of the planner (set by the BUILD file)")
	agentAppLoc := flag.String("agent-app", "", "runfiles path of agent-app.sh (set by the BUILD file)")
	noRecord := flag.Bool("no-record", false, "run and check, but do not write a record")
	flag.Parse()

	fail := func(format string, a ...any) int {
		fmt.Fprintf(os.Stderr, "verified-run: "+format+"\n", a...)
		return exitSetup
	}
	root := os.Getenv("BUILD_WORKSPACE_DIRECTORY")
	if root == "" {
		return fail("run this with `bazel run //tools/pipeline/verifiedrun`")
	}
	planner, err := runfile(*plannerLoc)
	if err != nil {
		return fail("%v", err)
	}
	agentApp, err := runfile(*agentAppLoc)
	if err != nil {
		return fail("%v", err)
	}
	self, err := os.Executable()
	if err != nil {
		return fail("%v", err)
	}
	realBazel, err := exec.LookPath("bazel")
	if err != nil {
		return fail("bazel is not on PATH")
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	if _, err := git(ctx, root, "fetch", "--quiet", "origin", "main"); err != nil {
		fmt.Fprintf(os.Stderr, "verified-run: warning: could not fetch origin/main, using the copy already here: %v\n", err)
	}
	if err := requireClean(ctx, root); err != nil {
		return fail("%v", err)
	}
	head, err := git(ctx, root, "rev-parse", "--verify", "HEAD^{commit}")
	if err != nil {
		return fail("%v", err)
	}
	tree, err := treeHash(ctx, root)
	if err != nil {
		return fail("%v", err)
	}
	base, err := git(ctx, root, "merge-base", "origin/main", "HEAD")
	if err != nil {
		return fail("cannot find where this branch left origin/main: %v", err)
	}
	common, err := git(ctx, root, "rev-parse", "--path-format=absolute", "--git-common-dir")
	if err != nil {
		return fail("%v", err)
	}
	mainCheckout := filepath.Dir(common)
	startup, err := keyStartup(root, mainCheckout)
	if err != nil {
		return fail("%v", err)
	}
	units, err := unitfile.Discover(root)
	if err != nil {
		return fail("cannot read the pipeline units: %v", err)
	}
	unitMap := map[string]unitfile.Unit{}
	for _, u := range units {
		unitMap[u.Name] = u
	}

	work, err := os.MkdirTemp("", "verified-run-")
	if err != nil {
		return fail("%v", err)
	}
	defer os.RemoveAll(work)
	shimDir := filepath.Join(work, "bin")
	if err := os.Mkdir(shimDir, 0o700); err != nil {
		return fail("%v", err)
	}
	wrapper := fmt.Sprintf("#!/bin/sh\nexec %q __shim \"$@\"\n", self)
	if err := os.WriteFile(filepath.Join(shimDir, "bazel"), []byte(wrapper), 0o700); err != nil {
		return fail("%v", err)
	}
	logPath := filepath.Join(work, "invocations.jsonl")
	shimEnv := []string{
		envRealBazel + "=" + realBazel,
		envLog + "=" + logPath,
		envStartup + "=" + strings.Join(startup, "\n"),
		envStrict + "=" + strings.Join(strictFlags(head, tree), "\n"),
	}
	rdepsMap := filepath.Join(work, "pipeline-rdeps-map.json")

	v := &verifier{
		out:  os.Stdout,
		head: head, tree: tree, base: base,
		units: unitMap,
		plan: func(ctx context.Context) (planResult, error) {
			// Same dependency map and planner flags as the presubmit plan job.
			if _, err := runCmd(ctx, root, childEnv(shimDir, shimEnv...), "bash", "tools/ci/rdeps-map-ref.sh", "fetch", rdepsMap, base); err != nil {
				fmt.Fprintf(os.Stderr, "verified-run: no dependency map (%v); the planner will query instead\n", err)
			}
			cmd := exec.CommandContext(ctx, planner,
				"--base="+base, "--head=HEAD", "--event=pull_request", "--timeout-sec=900",
				"--rdeps-map="+rdepsMap, "--rdeps-map-max-behind=9",
				"--format=json", "--repo-root="+root)
			cmd.Dir, cmd.Env = root, childEnv(shimDir, shimEnv...)
			var out bytes.Buffer
			cmd.Stdout, cmd.Stderr = &out, os.Stderr
			if err := cmd.Run(); err != nil {
				return planResult{}, err
			}
			var p planResult
			if err := json.Unmarshal(out.Bytes(), &p); err != nil {
				return planResult{}, fmt.Errorf("unreadable plan: %w", err)
			}
			return p, nil
		},
		runBuildTest: func(ctx context.Context) (int, error) {
			// The key placeholder is stripped by the shim; the real key comes
			// from user.bazelrc. affected-targets.sh needs the variable set.
			env := childEnv(shimDir, append(shimEnv,
				envLane+"=build-test",
				"BASE_REF=main",
				"RDEPS_MAP="+rdepsMap,
				"PLAN_BIN="+planner,
				"BUILDBUDDY_API_KEY=from-user-bazelrc")...)
			return runCmd(ctx, root, env, "bash", "tools/ci/affected-targets.sh")
		},
		runUnit: func(ctx context.Context, u unitfile.Unit) (int, error) {
			// Same command as the generated presubmit job, including "exit 4
			// means no test targets, so build them instead".
			env := childEnv(shimDir, append(shimEnv, envLane+"=unit:"+u.Name)...)
			args := append(append([]string{}, u.BuildFlags...), u.TestTargets...)
			rc, err := runCmd(ctx, root, env, filepath.Join(shimDir, "bazel"), append([]string{"test"}, args...)...)
			if err == nil && rc == 4 {
				return runCmd(ctx, root, env, filepath.Join(shimDir, "bazel"), append([]string{"build"}, args...)...)
			}
			return rc, err
		},
		invocations: func() ([]invocation, error) { return readInvocations(logPath) },
	}
	if !*noRecord {
		keyDir := os.Getenv("AGENT_KEY_DIR")
		if keyDir == "" {
			keyDir = filepath.Join(mainCheckout, "tools", "sync-env-secrets", "agent-keys")
		}
		rec := statusRecorder{
			configPath: filepath.Join(root, recorderFile),
			keyDir:     keyDir,
			mint:       agentAppMinter(agentApp),
			apiBase:    "https://api.github.com",
		}
		v.record = rec.record
	}
	return v.run(ctx)
}
