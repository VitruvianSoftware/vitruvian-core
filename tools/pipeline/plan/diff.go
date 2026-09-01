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
	"strings"
)

// DiffOptions holds parameters for git diff extraction.
type DiffOptions struct {
	RepoRoot  string
	Base      string
	Head      string
	BaseRef   string
	BaseSHA   string
	BeforeRev string
	Event     string
}

// ResolveDiffBase computes the base git revision for diff comparison.
func ResolveDiffBase(ctx context.Context, opts DiffOptions) (string, error) {
	if opts.Base != "" {
		return opts.Base, nil
	}
	if opts.BeforeRev != "" {
		return opts.BeforeRev, nil
	}
	if opts.BaseSHA != "" {
		return opts.BaseSHA, nil
	}
	if opts.BaseRef != "" {
		// Compute merge-base against origin/<BaseRef>
		ref := "origin/" + opts.BaseRef
		cmd := exec.CommandContext(ctx, "git", "merge-base", ref, "HEAD")
		if opts.RepoRoot != "" {
			cmd.Dir = opts.RepoRoot
		}
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err == nil {
			base := strings.TrimSpace(out.String())
			if base != "" {
				return base, nil
			}
		}
		// Fallback to base ref directly
		return ref, nil
	}

	// Default fallback: merge-base with origin/main or HEAD~1
	cmd := exec.CommandContext(ctx, "git", "merge-base", "origin/main", "HEAD")
	if opts.RepoRoot != "" {
		cmd.Dir = opts.RepoRoot
	}
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err == nil {
		base := strings.TrimSpace(out.String())
		if base != "" {
			return base, nil
		}
	}

	return "HEAD~1", nil
}

// ExtractChangedFiles executes git diff --name-only against the resolved base.
func ExtractChangedFiles(ctx context.Context, opts DiffOptions) ([]string, string, error) {
	base, err := ResolveDiffBase(ctx, opts)
	if err != nil {
		return nil, "", fmt.Errorf("resolve diff base: %w", err)
	}

	args := []string{"diff", "--name-only", base}
	if opts.Head != "" {
		args = append(args, opts.Head)
	}
	args = append(args, "--")

	cmd := exec.CommandContext(ctx, "git", args...)
	if opts.RepoRoot != "" {
		cmd.Dir = opts.RepoRoot
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, base, fmt.Errorf("git diff failed (%s): %w: %s", strings.Join(args, " "), err, stderr.String())
	}

	lines := strings.Split(strings.TrimSpace(stdout.String()), "\n")
	var files []string
	for _, l := range lines {
		trimmed := strings.TrimSpace(l)
		if trimmed != "" {
			files = append(files, trimmed)
		}
	}

	return files, base, nil
}
