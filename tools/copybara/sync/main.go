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
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	pinnedImage    = "olivr/copybara@sha256:87e2e9089344e64693faebb2ee0ed33b8797358c0420b0fa98325ca611e98679"
	defaultOptions = "--ignore-noop"
	maxAttempts    = 3
)

// runner is the interface the sync logic uses to invoke Docker.
// The real implementation shells out; tests inject a fake.
type runner interface {
	run(image string, dockerArgs []string) (exitCode int, err error)
}

// dockerRunner is the real implementation: calls `docker run`.
type dockerRunner struct{}

func (dockerRunner) run(image string, dockerArgs []string) (int, error) {
	args := append([]string{"run"}, dockerArgs...)
	args = append(args, image, "copybara")
	cmd := exec.Command("docker", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return exitErr.ExitCode(), nil
		}
		return -1, err
	}
	return 0, nil
}

// workflowName derives the Copybara workflow identifier:
// ("import", "mcp-slack") → "import_mcp_slack".
func workflowName(direction, component string) string {
	return direction + "_" + strings.ReplaceAll(component, "-", "_")
}

// isSuccess treats exit codes 0 and 4 (NO_OP) as success.
func isSuccess(code int) bool {
	return code == 0 || code == 4
}

// resolveWorkspace returns the workspace directory: prefers BUILD_WORKSPACE_DIRECTORY
// (set by `bazel run`), then GITHUB_WORKSPACE, then current working directory.
func resolveWorkspace() string {
	if v := os.Getenv("BUILD_WORKSPACE_DIRECTORY"); v != "" {
		return v
	}
	if v := os.Getenv("GITHUB_WORKSPACE"); v != "" {
		return v
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "."
	}
	return cwd
}

// run is the testable core. args = [direction, component, (--options "<opts>")?]
// r is the runner used to invoke Docker; sleeper is called with seconds to sleep (for retry backoff).
// Returns the process exit code.
func run(args []string, r runner, sleeper func(int)) int {
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: sync <export|import> <component> [--options \"<opts>\"]")
		fmt.Fprintln(os.Stderr, "       sync import_pr <component> <pr-number> [--options \"<opts>\"]")
		return 2
	}

	direction := args[0]
	component := args[1]

	// One-way PR-import has its own arg shape (<component> <pr-number>), its own
	// config rewrite (@@PR_NUMBER@@ -> real PR number), and its own auth (HTTPS
	// App token, no SSH deploy key), so it is handled separately from the bidi
	// export/import path below.
	if direction == "import_pr" {
		return runImportPR(args, component, r)
	}

	options := defaultOptions

	// Parse optional --options flag.
	for i := 2; i < len(args)-1; i++ {
		if args[i] == "--options" {
			options = args[i+1]
		}
	}

	switch direction {
	case "export", "import":
		// valid
	default:
		fmt.Fprintf(os.Stderr, "unknown direction: %s (use export|import)\n", direction)
		return 2
	}

	wf := workflowName(direction, component)
	workspace := resolveWorkspace()
	home := os.Getenv("HOME")

	dockerArgs := []string{
		"--rm",
		"-v", workspace + ":/usr/src/app",
		"-v", home + "/.ssh/id_rsa:/root/.ssh/id_rsa",
		"-v", home + "/.ssh/known_hosts:/root/.ssh/known_hosts",
		"-v", workspace + "/tools/copybara/copy.bara.sky:/root/copy.bara.sky",
		"-v", home + "/.git-credentials:/root/.git-credentials",
		"-v", home + "/.gitconfig:/root/.gitconfig",
		"-e", "COPYBARA_CONFIG=/root/copy.bara.sky",
		"-e", "COPYBARA_WORKFLOW=" + wf,
		"-e", "COPYBARA_OPTIONS=" + options,
	}

	attempt := 1
	for {
		exitCode, err := r.run(pinnedImage, dockerArgs)
		if err != nil {
			fmt.Fprintf(os.Stderr, "docker error: %v\n", err)
			return 1
		}

		if isSuccess(exitCode) {
			fmt.Printf("Copybara OK (exit %d; 4 = no-op/up-to-date)\n", exitCode)
			return 0
		}

		// Failure path.
		if direction != "import" || attempt >= maxAttempts {
			fmt.Fprintf(os.Stderr, "Copybara failed (exit %d", exitCode)
			if direction == "import" && attempt >= maxAttempts {
				fmt.Fprintf(os.Stderr, " after %d attempts", maxAttempts)
			}
			fmt.Fprintln(os.Stderr, ")")
			return exitCode
		}

		// Import retry: sleep attempt*5 seconds then retry.
		attempt++
		fmt.Printf("Copybara exit %d (attempt %d/%d) — retrying after re-fetch (likely a concurrent import race)\n",
			exitCode, attempt-1, maxAttempts)
		sleeper(attempt * 5)
	}
}

// isDigits reports whether s is a non-empty run of ASCII digits.
func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// resolveImportPRConfig writes a throwaway copy of copy.bara.sky with the
// @@PR_NUMBER@@ placeholder replaced by prNumber, and returns its path. The
// pinned 2023-01 copybara image does not resolve ${GITHUB_PR_NUMBER} templates
// in pr_branch/title/body, so the one-way import_pr workflows reference
// @@PR_NUMBER@@ and we bake in the real number here. The caller removes the file.
func resolveImportPRConfig(workspace, prNumber string) (string, error) {
	src := filepath.Join(workspace, "tools", "copybara", "copy.bara.sky")
	data, err := os.ReadFile(src)
	if err != nil {
		return "", fmt.Errorf("read %s: %w", src, err)
	}
	resolved := strings.ReplaceAll(string(data), "@@PR_NUMBER@@", prNumber)
	f, err := os.CreateTemp("", "copy.bara.*.sky")
	if err != nil {
		return "", err
	}
	if _, err := f.WriteString(resolved); err != nil {
		f.Close()
		os.Remove(f.Name())
		return "", err
	}
	if err := f.Close(); err != nil {
		os.Remove(f.Name())
		return "", err
	}
	return f.Name(), nil
}

// runImportPR drives the one-way PR-import: a labelled standalone PR -> a
// monorepo PR under <component>/. args = [import_pr, component, pr-number,
// (--options "<opts>")?]. Auth is the HTTPS App token (GITHUB_TOKEN env, passed
// through to the container) plus the ~/.git-credentials store; no SSH key is
// used. Single attempt (no retry): each PR maps to its own destination branch,
// so the concurrent-race retry the bidi import needs does not apply here.
func runImportPR(args []string, component string, r runner) int {
	if len(args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: sync import_pr <component> <pr-number> [--options \"<opts>\"]")
		return 2
	}
	prNumber := args[2]
	if !isDigits(prNumber) {
		fmt.Fprintf(os.Stderr, "import_pr: pr-number must be digits, got %q\n", prNumber)
		return 2
	}

	options := defaultOptions
	for i := 3; i < len(args)-1; i++ {
		if args[i] == "--options" {
			options = args[i+1]
		}
	}

	workspace := resolveWorkspace()
	cfgPath, err := resolveImportPRConfig(workspace, prNumber)
	if err != nil {
		fmt.Fprintf(os.Stderr, "import_pr: %v\n", err)
		return 1
	}
	defer os.Remove(cfgPath)

	home := os.Getenv("HOME")
	wf := workflowName("import_pr", component)
	dockerArgs := []string{
		"--rm",
		"-v", workspace + ":/usr/src/app",
		"-v", cfgPath + ":/root/copy.bara.sky",
		"-v", home + "/.git-credentials:/root/.git-credentials",
		"-v", home + "/.gitconfig:/root/.gitconfig",
		"-e", "COPYBARA_CONFIG=/root/copy.bara.sky",
		"-e", "COPYBARA_WORKFLOW=" + wf,
		"-e", "COPYBARA_SOURCEREF=" + prNumber,
		"-e", "COPYBARA_OPTIONS=" + options,
		// Pass the App token through from the host env (set by the workflow); the
		// value is NOT placed in argv, so it never shows up in `ps`.
		"-e", "GITHUB_TOKEN",
	}

	exitCode, err := r.run(pinnedImage, dockerArgs)
	if err != nil {
		fmt.Fprintf(os.Stderr, "docker error: %v\n", err)
		return 1
	}
	if isSuccess(exitCode) {
		fmt.Printf("Copybara import_pr OK (exit %d; 4 = no-op) for %s PR #%s\n", exitCode, component, prNumber)
		return 0
	}
	fmt.Fprintf(os.Stderr, "Copybara import_pr failed (exit %d) for %s PR #%s\n", exitCode, component, prNumber)
	return exitCode
}

func main() {
	sleeper := func(secs int) { time.Sleep(time.Duration(secs) * time.Second) }
	os.Exit(run(os.Args[1:], dockerRunner{}, sleeper))
}
