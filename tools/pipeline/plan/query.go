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

	setExpr := fmt.Sprintf("set(%s)", strings.Join(packages, " "))
	queryExpr := fmt.Sprintf("kind(\".*_test|.*_suite|service_test\", rdeps(//..., %s))", setExpr)

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
			// partial success with keep_going
		} else {
			return nil, fmt.Errorf("bazel query failed: %w: %s", err, stderr.String())
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
			return nil, fmt.Errorf("query pipeline units failed: %w: %s", err, stderr.String())
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
