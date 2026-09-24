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
	"fmt"
	"os/exec"
	"sort"
	"strings"
)

// QueryRunner abstracts Bazel query execution for hermetic testing.
type QueryRunner interface {
	QueryTestRdeps(ctx context.Context, repoRoot string, packages []string) ([]string, error)
	QueryPipelineUnits(ctx context.Context, repoRoot string) ([]string, error)
}

// BazelQueryRunner executes real bazel query commands.
type BazelQueryRunner struct{}

// QueryTestRdeps executes a fast package-level rdeps query over the Bazel target universe.
func (b *BazelQueryRunner) QueryTestRdeps(ctx context.Context, repoRoot string, packages []string) ([]string, error) {
	if len(packages) == 0 {
		return nil, nil
	}

	queryExpr := BuildTestRdepsQuery(packages)

	cmd := exec.CommandContext(ctx, "bazel", "query", queryExpr, "--output=label", "--keep_going")
	if repoRoot != "" {
		cmd.Dir = repoRoot
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		// Exit code 3 in bazel query indicates partial evaluation with --keep_going
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 3 {
			// Partial result under --keep_going. Bazel itself warns "results
			// may be inaccurate", so only accept it when every error is inside
			// an external repo: those cannot sit on a path from a test to a
			// package in this repo. An error in our own BUILD files could mean
			// a missing test, so fail and let the planner run everything.
			if bad := internalQueryErrors(stderr.String(), repoRoot); len(bad) > 0 {
				return nil, fmt.Errorf("bazel query was partial and some errors are in this repo, so tests may be missing: %s", strings.Join(bad, "\n"))
			}
		} else {
			return nil, fmt.Errorf("bazel query failed: %w: %s", err, lastLines(stderr.String(), 15))
		}
	}

	lines := strings.Split(strings.TrimSpace(stdout.String()), "\n")
	var targets []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" && strings.HasPrefix(trimmed, "//") {
			targets = append(targets, trimmed)
		}
	}
	sort.Strings(targets)
	return targets, nil
}

// QueryPipelineUnits discovers all pipeline units declared in the Bazel graph.
func (b *BazelQueryRunner) QueryPipelineUnits(ctx context.Context, repoRoot string) ([]string, error) {
	cmd := exec.CommandContext(ctx, "bazel", "query", "attr(tags, \"pipeline\", //...)", "--output=label", "--keep_going")
	if repoRoot != "" {
		cmd.Dir = repoRoot
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 3 {
			// keep_going partial success
		} else {
			return nil, fmt.Errorf("query pipeline units failed: %w: %s", err, lastLines(stderr.String(), 15))
		}
	}

	lines := strings.Split(strings.TrimSpace(stdout.String()), "\n")
	var units []string
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" && strings.HasPrefix(trimmed, "//") {
			units = append(units, trimmed)
		}
	}
	sort.Strings(units)
	return units, nil
}

// BuildTestRdepsQuery builds the bazel query that finds every test affected by
// a set of packages.
//
// `except attr(tags, manual, ...)` is load-bearing.
//
// This list is handed to `bazel test <explicit targets>`, and an explicit
// target IGNORES the manual tag -- manual only removes a target from
// wildcard patterns like //... So a test that cannot run unattended
// (//mobile/android/remote:boot_smoke needs a device and an emulator) is
// tagged manual, skipped by every wildcard build, and then handed straight
// to the affected lane anyway, which fails with "no adb found".
//
// Filtering here rather than in tools/ci/affected-targets.sh because this
// is where "what should CI run on its own" is decided; anything consuming
// the plan gets the same protection for free.
//
// Packages arrive as "//pkg:all", but `:all` is only the RULES in a package.
// A test that reads a source file directly (a data dep on //pkg:file.sh) is
// not a reverse dependency of any rule there, so it was never selected when
// only that file changed. `:*` includes the files. Found by checking every
// package against the dependency map, which walks the full graph (#2465).
func BuildTestRdepsQuery(packages []string) string {
	targets := make([]string, len(packages))
	for i, p := range packages {
		targets[i] = strings.TrimSuffix(p, ":all") + ":*"
	}
	setExpr := fmt.Sprintf("set(%s)", strings.Join(targets, " "))
	return fmt.Sprintf(
		"kind(\".*_test|.*_suite|service_test\", rdeps(//..., %s)) except attr(tags, \"manual\", //...)",
		setExpr,
	)
}

// lastLines keeps the final n lines of s. A cold `bazel query` writes hundreds
// of progress lines to stderr; embedding all of them in an error buried the
// one line that says why it failed (a killed process, a timeout) where the CI
// log's tail could not reach it.
func lastLines(s string, n int) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, "\n")
}

// internalQueryErrors returns the ERROR lines from a --keep_going query that
// are NOT confined to an external repo. Unrecognised lines count as internal:
// the cost of a wrong "internal" is a full sweep, of a wrong "external" a
// skipped test.
func internalQueryErrors(stderr, repoRoot string) []string {
	var bad []string
	for _, line := range strings.Split(stderr, "\n") {
		msg, ok := strings.CutPrefix(strings.TrimSpace(line), "ERROR: ")
		if !ok {
			continue
		}
		switch {
		case strings.HasPrefix(msg, "Evaluation of query") && strings.Contains(msg, "errors were encountered"):
			// The summary line; the real errors are reported separately.
		case strings.HasPrefix(msg, "/"):
			// A BUILD-file location. Ours if it is under the workspace.
			if repoRoot == "" || strings.HasPrefix(msg, strings.TrimSuffix(repoRoot, "/")+"/") {
				bad = append(bad, line)
			}
		case strings.Contains(msg, "'//") || strings.Contains(msg, " //"):
			bad = append(bad, line)
		case strings.Contains(msg, "'@"):
			// Names only external labels.
		default:
			bad = append(bad, line)
		}
	}
	return bad
}

// testUniverseExpr is every test CI runs on its own. It must stay the same
// filter as BuildTestRdepsQuery, or the map and the live query disagree.
const testUniverseExpr = `kind(".*_test|.*_suite|service_test", //...) except attr(tags, "manual", //...)`

// BuildRdepsMap runs the three queries behind the dependency map. They are
// strict (no --keep_going): this runs off the critical path, and a map built
// from a partial graph must never be published.
func (b *BazelQueryRunner) BuildRdepsMap(ctx context.Context, repoRoot, commit string) (*RdepsMap, error) {
	tests, err := strictQuery(ctx, repoRoot, testUniverseExpr, "--output=label")
	if err != nil {
		return nil, err
	}
	pkgs, err := strictQuery(ctx, repoRoot, "//...", "--output=package")
	if err != nil {
		return nil, err
	}
	dot, err := strictQuery(ctx, repoRoot, "deps("+testUniverseExpr+")",
		"--output=graph", "--graph:factored=false", "--graph:node_limit=-1")
	if err != nil {
		return nil, err
	}
	edges, err := ParseGraphEdges(dot)
	if err != nil {
		return nil, err
	}
	return ComputeRdepsMap(commit, nonEmptyLines(tests), edges, nonEmptyLines(pkgs)), nil
}

func strictQuery(ctx context.Context, repoRoot, expr string, flags ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "bazel", append([]string{"query", expr}, flags...)...)
	if repoRoot != "" {
		cmd.Dir = repoRoot
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("bazel query %q failed: %w: %s", expr, err, lastLines(stderr.String(), 15))
	}
	return stdout.String(), nil
}

func nonEmptyLines(s string) []string {
	var out []string
	for _, l := range strings.Split(s, "\n") {
		if l = strings.TrimSpace(l); l != "" {
			out = append(out, l)
		}
	}
	return out
}
