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
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeRunner is a test double for the runner interface.
// Each call pops the next exitCode from codes; if exhausted it returns the last one.
// callCount records how many times it was called.
type fakeRunner struct {
	codes        []int
	callCount    int
	capturedArgs [][]string
}

func (f *fakeRunner) run(image string, dockerArgs []string) (int, error) {
	f.callCount++
	f.capturedArgs = append(f.capturedArgs, dockerArgs)
	idx := f.callCount - 1
	if idx >= len(f.codes) {
		idx = len(f.codes) - 1
	}
	return f.codes[idx], nil
}

// noopSleeper is injected into tests so backoff sleeps are instant.
func noopSleeper(_ int) {}

// ---------------------------------------------------------------------------
// workflowName tests
// ---------------------------------------------------------------------------

func TestWorkflowName_ImportHyphenated(t *testing.T) {
	got := workflowName("import", "mcp-slack")
	if got != "import_mcp_slack" {
		t.Errorf("workflowName = %q, want %q", got, "import_mcp_slack")
	}
}

func TestWorkflowName_ExportSimple(t *testing.T) {
	got := workflowName("export", "devx")
	if got != "export_devx" {
		t.Errorf("workflowName = %q, want %q", got, "export_devx")
	}
}

func TestWorkflowName_MultiHyphen(t *testing.T) {
	got := workflowName("import", "nexus-agent")
	if got != "import_nexus_agent" {
		t.Errorf("workflowName = %q, want %q", got, "import_nexus_agent")
	}
}

// ---------------------------------------------------------------------------
// exit code classification
// ---------------------------------------------------------------------------

func TestExit0_IsSuccess(t *testing.T) {
	fr := &fakeRunner{codes: []int{0}}
	code := run([]string{"export", "devx"}, fr, noopSleeper)
	if code != 0 {
		t.Errorf("exit code = %d, want 0", code)
	}
	if fr.callCount != 1 {
		t.Errorf("runner called %d times, want 1", fr.callCount)
	}
}

func TestExit4_IsSuccess(t *testing.T) {
	fr := &fakeRunner{codes: []int{4}}
	code := run([]string{"export", "devx"}, fr, noopSleeper)
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (exit 4 = no-op)", code)
	}
}

// ---------------------------------------------------------------------------
// export: no retry
// ---------------------------------------------------------------------------

func TestExport_Failure_NoRetry(t *testing.T) {
	fr := &fakeRunner{codes: []int{1}}
	code := run([]string{"export", "devx"}, fr, noopSleeper)
	if code != 1 {
		t.Errorf("exit code = %d, want 1", code)
	}
	if fr.callCount != 1 {
		t.Errorf("runner called %d times, want 1 (no retry for export)", fr.callCount)
	}
}

// ---------------------------------------------------------------------------
// import: retry up to 3 attempts
// ---------------------------------------------------------------------------

func TestImport_Failure_3Attempts(t *testing.T) {
	// All three attempts fail with exit 1.
	fr := &fakeRunner{codes: []int{1, 1, 1}}
	code := run([]string{"import", "devx"}, fr, noopSleeper)
	if code != 1 {
		t.Errorf("exit code = %d, want 1 (all attempts failed)", code)
	}
	if fr.callCount != 3 {
		t.Errorf("runner called %d times, want 3 (max attempts)", fr.callCount)
	}
}

func TestImport_SuccessOnRetry(t *testing.T) {
	// First attempt fails, second succeeds.
	fr := &fakeRunner{codes: []int{1, 0}}
	code := run([]string{"import", "devx"}, fr, noopSleeper)
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (success on retry)", code)
	}
	if fr.callCount != 2 {
		t.Errorf("runner called %d times, want 2", fr.callCount)
	}
}

func TestImport_NoOpOnRetry_IsSuccess(t *testing.T) {
	// First attempt fails, second returns 4 (no-op).
	fr := &fakeRunner{codes: []int{1, 4}}
	code := run([]string{"import", "devx"}, fr, noopSleeper)
	if code != 0 {
		t.Errorf("exit code = %d, want 0 (exit 4 = success)", code)
	}
}

// ---------------------------------------------------------------------------
// unknown direction
// ---------------------------------------------------------------------------

func TestUnknownDirection_Exit2(t *testing.T) {
	fr := &fakeRunner{codes: []int{0}}
	code := run([]string{"sideways", "devx"}, fr, noopSleeper)
	if code != 2 {
		t.Errorf("exit code = %d, want 2", code)
	}
	if fr.callCount != 0 {
		t.Errorf("runner should not be called for unknown direction")
	}
}

// ---------------------------------------------------------------------------
// docker args contain the workflow name
// ---------------------------------------------------------------------------

func TestDockerArgs_ContainPinnedImage(t *testing.T) {
	fr := &fakeRunner{codes: []int{0}}
	run([]string{"export", "devx"}, fr, noopSleeper)
	if fr.callCount == 0 {
		t.Fatal("runner was not called")
	}
	// Check that COPYBARA_WORKFLOW appears in the docker args.
	found := false
	for _, arg := range fr.capturedArgs[0] {
		if strings.Contains(arg, "export_devx") {
			found = true
		}
	}
	if !found {
		t.Errorf("docker args %v don't contain workflow name export_devx", fr.capturedArgs[0])
	}
}

// ---------------------------------------------------------------------------
// --options flag is threaded through to COPYBARA_OPTIONS
// ---------------------------------------------------------------------------

func TestOptions_Default(t *testing.T) {
	fr := &fakeRunner{codes: []int{0}}
	run([]string{"export", "devx"}, fr, noopSleeper)
	found := false
	for _, arg := range fr.capturedArgs[0] {
		if arg == "COPYBARA_OPTIONS=--ignore-noop" {
			found = true
		}
	}
	if !found {
		t.Errorf("default --ignore-noop not in docker args: %v", fr.capturedArgs[0])
	}
}

func TestOptions_Custom(t *testing.T) {
	fr := &fakeRunner{codes: []int{0}}
	run([]string{"export", "devx", "--options", "--force --ignore-noop"}, fr, noopSleeper)
	found := false
	for _, arg := range fr.capturedArgs[0] {
		if arg == "COPYBARA_OPTIONS=--force --ignore-noop" {
			found = true
		}
	}
	if !found {
		t.Errorf("custom options not threaded through: %v", fr.capturedArgs[0])
	}
}

// ---------------------------------------------------------------------------
// sleeper receives correct backoff values (attempt*5)
// ---------------------------------------------------------------------------

func TestImport_BackoffValues(t *testing.T) {
	var sleepCalls []int
	sleeper := func(secs int) {
		sleepCalls = append(sleepCalls, secs)
	}
	fr := &fakeRunner{codes: []int{1, 1, 1}}
	run([]string{"import", "devx"}, fr, sleeper)
	// attempt 2 → sleep 2*5=10; attempt 3 → sleep 3*5=15
	// (no sleep before attempt 1, no sleep after final failure)
	want := []int{10, 15}
	if fmt.Sprint(sleepCalls) != fmt.Sprint(want) {
		t.Errorf("sleep calls = %v, want %v", sleepCalls, want)
	}
}

// ---------------------------------------------------------------------------
// one-way import_pr
// ---------------------------------------------------------------------------

// setupWorkspace creates a temp workspace containing tools/copybara/copy.bara.sky
// with an @@PR_NUMBER@@ placeholder and points resolveWorkspace at it.
func setupWorkspace(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	cfgDir := filepath.Join(dir, "tools", "copybara")
	if err := os.MkdirAll(cfgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	body := "x = \"import-pr-@@PR_NUMBER@@\"\n"
	if err := os.WriteFile(filepath.Join(cfgDir, "copy.bara.sky"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("BUILD_WORKSPACE_DIRECTORY", "")
	t.Setenv("GITHUB_WORKSPACE", dir)
	return dir
}

func argsContain(args []string, want string) bool {
	for _, a := range args {
		if a == want {
			return true
		}
	}
	return false
}

func TestWorkflowName_ImportPR(t *testing.T) {
	got := workflowName("import_pr", "nexus-agent")
	if got != "import_pr_nexus_agent" {
		t.Errorf("workflowName = %q, want %q", got, "import_pr_nexus_agent")
	}
}

func TestImportPR_MissingPRNumber_Exit2(t *testing.T) {
	fr := &fakeRunner{codes: []int{0}}
	code := run([]string{"import_pr", "devx"}, fr, noopSleeper)
	if code != 2 {
		t.Errorf("exit = %d, want 2", code)
	}
	if fr.callCount != 0 {
		t.Errorf("runner called %d times, should be 0", fr.callCount)
	}
}

func TestImportPR_NonDigitPRNumber_Exit2(t *testing.T) {
	fr := &fakeRunner{codes: []int{0}}
	code := run([]string{"import_pr", "devx", "12x"}, fr, noopSleeper)
	if code != 2 {
		t.Errorf("exit = %d, want 2", code)
	}
	if fr.callCount != 0 {
		t.Errorf("runner called for non-digit pr number")
	}
}

func TestImportPR_Success_DockerArgs(t *testing.T) {
	setupWorkspace(t)
	fr := &fakeRunner{codes: []int{0}}
	code := run([]string{"import_pr", "mcp-slack", "123"}, fr, noopSleeper)
	if code != 0 {
		t.Errorf("exit = %d, want 0", code)
	}
	if fr.callCount != 1 {
		t.Fatalf("runner called %d times, want 1", fr.callCount)
	}
	args := fr.capturedArgs[0]
	if !argsContain(args, "COPYBARA_WORKFLOW=import_pr_mcp_slack") {
		t.Errorf("missing import_pr workflow name: %v", args)
	}
	if !argsContain(args, "COPYBARA_SOURCEREF=123") {
		t.Errorf("missing COPYBARA_SOURCEREF: %v", args)
	}
	if !argsContain(args, "GITHUB_TOKEN") {
		t.Errorf("missing GITHUB_TOKEN pass-through: %v", args)
	}
	// import_pr is HTTPS App-token auth: no SSH key should be mounted.
	for _, a := range args {
		if strings.Contains(a, "id_rsa") {
			t.Errorf("import_pr must not mount an SSH key, got %q", a)
		}
	}
}

func TestImportPR_Failure_NoRetry(t *testing.T) {
	setupWorkspace(t)
	fr := &fakeRunner{codes: []int{1}}
	code := run([]string{"import_pr", "devx", "5"}, fr, noopSleeper)
	if code != 1 {
		t.Errorf("exit = %d, want 1", code)
	}
	if fr.callCount != 1 {
		t.Errorf("runner called %d times, want 1 (import_pr does not retry)", fr.callCount)
	}
}

func TestImportPR_Exit4_IsSuccess(t *testing.T) {
	setupWorkspace(t)
	fr := &fakeRunner{codes: []int{4}}
	code := run([]string{"import_pr", "devx", "5"}, fr, noopSleeper)
	if code != 0 {
		t.Errorf("exit = %d, want 0 (exit 4 = no-op)", code)
	}
}

func TestResolveImportPRConfig_RewritesPlaceholder(t *testing.T) {
	dir := t.TempDir()
	cfgDir := filepath.Join(dir, "tools", "copybara")
	if err := os.MkdirAll(cfgDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(cfgDir, "copy.bara.sky"),
		[]byte("x = \"import-pr-@@PR_NUMBER@@\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	path, err := resolveImportPRConfig(dir, "77")
	if err != nil {
		t.Fatalf("resolveImportPRConfig: %v", err)
	}
	defer os.Remove(path)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "@@PR_NUMBER@@") {
		t.Errorf("placeholder not replaced: %s", data)
	}
	if !strings.Contains(string(data), "import-pr-77") {
		t.Errorf("resolved config missing the PR number: %s", data)
	}
}
