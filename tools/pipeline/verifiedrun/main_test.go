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
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/VitruvianSoftware/vitruvian-core/tools/pipeline/unitfile"
)

func gitT(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false"}, args...)...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_NOSYSTEM=1")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func newRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	gitT(t, dir, "init", "-q")
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("one\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitT(t, dir, "add", "a.txt")
	gitT(t, dir, "commit", "-q", "-m", "first")
	return dir
}

// The record keys on the tree hash because a rebase or a new commit message
// must not invalidate a pass, while any change to a file must.
func TestTreeHashFollowsFilesNotCommits(t *testing.T) {
	ctx := context.Background()
	dir := newRepo(t)
	tree1, err := treeHash(ctx, dir)
	if err != nil {
		t.Fatal(err)
	}
	if want := gitT(t, dir, "rev-parse", "HEAD^{tree}"); tree1 != want {
		t.Fatalf("tree %s, git says %s", tree1, want)
	}
	commit1 := gitT(t, dir, "rev-parse", "HEAD")

	gitT(t, dir, "commit", "-q", "--amend", "-m", "a different message")
	tree2, _ := treeHash(ctx, dir)
	if commit2 := gitT(t, dir, "rev-parse", "HEAD"); commit2 == commit1 {
		t.Fatal("the amend should have made a new commit")
	}
	if tree2 != tree1 {
		t.Fatalf("same files, new message: tree changed %s -> %s", tree1, tree2)
	}

	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("two\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	gitT(t, dir, "commit", "-q", "-am", "edit")
	if tree3, _ := treeHash(ctx, dir); tree3 == tree1 {
		t.Fatal("a file changed but the tree hash did not")
	}
}

func TestRequireCleanRefusesUncommittedAndUntrackedFiles(t *testing.T) {
	ctx := context.Background()
	dir := newRepo(t)
	if err := requireClean(ctx, dir); err != nil {
		t.Fatalf("clean repo refused: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "new.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := requireClean(ctx, dir); err == nil || !strings.Contains(err.Error(), "new.txt") {
		t.Fatalf("untracked file not refused: %v", err)
	}
	_ = os.Remove(filepath.Join(dir, "new.txt"))
	if err := os.WriteFile(filepath.Join(dir, "a.txt"), []byte("changed\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := requireClean(ctx, dir); err == nil {
		t.Fatal("modified file not refused")
	}
}

func TestKeyStartup(t *testing.T) {
	write := func(dir, content string) {
		if err := os.WriteFile(filepath.Join(dir, "user.bazelrc"), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	const key = "common --remote_header=x-buildbuddy-api-key=SECRET\n"

	ws, mainCo := t.TempDir(), t.TempDir()
	if _, err := keyStartup(ws, mainCo); err == nil || !strings.Contains(err.Error(), "no BuildBuddy key") {
		t.Fatalf("no key anywhere must refuse, got %v", err)
	}

	write(mainCo, key)
	got, err := keyStartup(ws, mainCo)
	if err != nil || len(got) != 1 || got[0] != "--bazelrc="+filepath.Join(mainCo, "user.bazelrc") {
		t.Fatalf("worktree without a key should load the main checkout's: %q %v", got, err)
	}
	if strings.Contains(strings.Join(got, " "), "SECRET") {
		t.Fatal("the key value must never be copied onto a command line")
	}

	// In the main checkout itself, %workspace%/user.bazelrc already loads it;
	// loading it twice would comma-join the header and break auth.
	if got, err := keyStartup(mainCo, mainCo); err != nil || got != nil {
		t.Fatalf("main checkout: want no extra bazelrc, got %q %v", got, err)
	}

	write(ws, key)
	if got, err := keyStartup(ws, mainCo); err != nil || got != nil {
		t.Fatalf("worktree with its own key: want no extra bazelrc, got %q %v", got, err)
	}
}

func TestClassifyMirrorsHowCIRunsEachUnit(t *testing.T) {
	units := map[string]unitfile.Unit{
		"linux":    {Name: "linux", Runner: "ubuntu-26.04", TestTargets: []string{"//a:t"}},
		"mac":      {Name: "mac", Runner: "xcode-27"},
		"macos":    {Name: "macos", Runner: "macos-15"},
		"emulator": {Name: "emulator", Runner: "ubuntu-26.04", NeedsEmulator: true},
		"files":    {Name: "files", Runner: "ubuntu-26.04", Artifacts: map[string]string{"apk": "x.apk"}},
		"linux2":   {Name: "linux2", Runner: "ubuntu-26.04"},
	}
	picked := []planEntry{{Name: "mac"}, {Name: "linux2"}, {Name: "emulator"}, {Name: "linux"}, {Name: "files"}, {Name: "macos"}}
	covered, left, err := classify(picked, units)
	if err != nil {
		t.Fatal(err)
	}
	if len(covered) != 2 || covered[0].Name != "linux" || covered[1].Name != "linux2" {
		t.Fatalf("covered %+v", covered)
	}
	for _, n := range []string{"mac", "macos", "emulator", "files"} {
		if left[n] == "" {
			t.Errorf("%s should be left to CI with a reason", n)
		}
	}
	if _, _, err := classify([]planEntry{{Name: "ghost"}}, units); err == nil {
		t.Fatal("a unit the planner names but nobody declares must refuse")
	}
}

// fakeRun drives verifier.run without Bazel, BuildBuddy or GitHub.
type fakeRun struct {
	plan      planResult
	planErr   error
	buildTest int
	unitRC    map[string]int
	invs      []invocation
	recordErr error
	recorded  []record
	ranUnits  []string
}

func (f *fakeRun) verifier(withRecord bool) (*verifier, *bytes.Buffer) {
	var out bytes.Buffer
	v := &verifier{
		out: &out, head: strings.Repeat("a", 40), tree: strings.Repeat("b", 40), base: strings.Repeat("c", 40),
		plan: func(context.Context) (planResult, error) { return f.plan, f.planErr },
		units: map[string]unitfile.Unit{
			"api": {Name: "api", Runner: "ubuntu-26.04", TestTargets: []string{"//api:test"}},
			"mac": {Name: "mac", Runner: "xcode-27", TestTargets: []string{"//mac:test"}},
		},
		runBuildTest: func(context.Context) (int, error) { return f.buildTest, nil },
		runUnit: func(_ context.Context, u unitfile.Unit) (int, error) {
			f.ranUnits = append(f.ranUnits, u.Name)
			return f.unitRC[u.Name], nil
		},
		invocations: func() ([]invocation, error) { return f.invs, nil },
	}
	if withRecord {
		v.record = func(_ context.Context, r record) error {
			f.recorded = append(f.recorded, r)
			return f.recordErr
		}
	}
	return v, &out
}

func remoteInv(lane, target string) invocation {
	return invocation{Lane: lane, Command: "test", Targets: []string{target}, URL: "https://app.buildbuddy.io/invocation/" + lane, SawSummary: true, Processes: "3 remote, 4 internal"}
}

func TestRunRecordsAPassThatRanRemotely(t *testing.T) {
	f := &fakeRun{
		plan: planResult{ChangedFiles: []string{"api/x.go"}, Matrix: []planEntry{{Name: "api"}, {Name: "mac"}}},
		invs: []invocation{remoteInv("build-test", "//api:lib_test"), remoteInv("unit:api", "//api:test")},
	}
	v, out := f.verifier(true)
	if rc := v.run(context.Background()); rc != exitVerified {
		t.Fatalf("rc %d\n%s", rc, out)
	}
	if strings.Join(f.ranUnits, ",") != "api" {
		t.Fatalf("ran units %v: the macOS unit must be left to CI", f.ranUnits)
	}
	if len(f.recorded) != 1 {
		t.Fatalf("recorded %d times", len(f.recorded))
	}
	r := f.recorded[0]
	if r.Tree != v.tree || r.Head != v.head || r.Base != v.base || strings.Join(r.Lanes, ",") != "build-test,unit:api" {
		t.Fatalf("record %+v", r)
	}
	for _, want := range []string{"unit mac: runs on a macOS runner", "PASSED on the remote machines", "Recorded on commit"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("output should say %q:\n%s", want, out)
		}
	}
}

func TestRunNeverRecordsAFailure(t *testing.T) {
	cases := map[string]*fakeRun{
		"build-test failed": {
			plan:      planResult{Matrix: []planEntry{{Name: "api"}}},
			buildTest: 3,
			invs:      []invocation{remoteInv("build-test", "//x:t")},
		},
		"a unit failed": {
			plan:   planResult{Matrix: []planEntry{{Name: "api"}}},
			unitRC: map[string]int{"api": 3},
			invs:   []invocation{remoteInv("unit:api", "//api:test")},
		},
		"the planner failed": {planErr: errors.New("query timed out")},
		"the plan is degraded": {
			plan: planResult{IsDegraded: true, SweepReason: "query failed"},
		},
		"the planner named an unknown unit": {
			plan: planResult{Matrix: []planEntry{{Name: "ghost"}}},
		},
		"work ran on the Mac": {
			invs: []invocation{func() invocation { i := remoteInv("build-test", "//x:t"); i.Processes = "2 darwin-sandbox"; return i }()},
		},
		"a run has no BuildBuddy link": {
			invs: []invocation{func() invocation { i := remoteInv("build-test", "//x:t"); i.URL = ""; return i }()},
		},
		"a logged run failed even though the script passed": {
			invs: []invocation{func() invocation { i := remoteInv("build-test", "//x:t"); i.Exit = 1; return i }()},
		},
	}
	for name, f := range cases {
		t.Run(name, func(t *testing.T) {
			v, out := f.verifier(true)
			if rc := v.run(context.Background()); rc != exitNotVerified {
				t.Fatalf("rc %d, want %d\n%s", rc, exitNotVerified, out)
			}
			if len(f.recorded) != 0 {
				t.Fatal("a failed or non-remote run was recorded")
			}
			if !strings.Contains(out.String(), "NOT VERIFIED") || !strings.Contains(out.String(), "Nothing was recorded") {
				t.Fatalf("output must say plainly that nothing was recorded:\n%s", out)
			}
		})
	}
}

func TestRunSaysPlainlyWhenTheRecorderIsMissing(t *testing.T) {
	f := &fakeRun{invs: []invocation{remoteInv("build-test", "//x:t")}, recordErr: errNoRecorder}
	v, out := f.verifier(true)
	if rc := v.run(context.Background()); rc != exitNotRecorded {
		t.Fatalf("rc %d, want %d\n%s", rc, exitNotRecorded, out)
	}
	if !strings.Contains(out.String(), "The tests passed, but: not recorded: there is no recorder identity yet") {
		t.Fatalf("output:\n%s", out)
	}
}

func TestRunWithNoRecordAndNothingToRun(t *testing.T) {
	f := &fakeRun{invs: []invocation{remoteInv("build-test", "//x:t")}}
	v, out := f.verifier(false)
	if rc := v.run(context.Background()); rc != exitVerified || !strings.Contains(out.String(), "Not recorded (--no-record)") {
		t.Fatalf("rc %d\n%s", rc, out)
	}

	empty := &fakeRun{}
	v, out = empty.verifier(true)
	if rc := v.run(context.Background()); rc != exitVerified || len(empty.recorded) != 0 || !strings.Contains(out.String(), "nothing to record") {
		t.Fatalf("nothing ran: rc %d, recorded %d\n%s", rc, len(empty.recorded), out)
	}
}

func TestStrictFlagsTieTheRunToTheCode(t *testing.T) {
	flags := strings.Join(strictFlags("HEADSHA", "TREESHA"), " ")
	for _, want := range []string{
		"--config=remote", "--spawn_strategy=remote", "--noremote_local_fallback",
		"--noremote_upload_local_results", "--disk_cache=", "--nocache_test_results",
		"--platforms=//tools/platforms:linux_x86_64", "--host_platform=//tools/platforms:linux_x86_64",
		"--extra_execution_platforms=//tools/platforms:linux_x86_64",
		"--build_metadata=COMMIT_SHA=HEADSHA", "--build_metadata=TREE_SHA=TREESHA",
	} {
		if !strings.Contains(flags, want) {
			t.Errorf("missing %s", want)
		}
	}
}
