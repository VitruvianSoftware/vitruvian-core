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
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"
)

func main() {
	var (
		baseFlag         = flag.String("base", "", "Base git commit/ref for diff comparison")
		headFlag         = flag.String("head", "", "Head git commit/ref (default: working tree)")
		eventFlag        = flag.String("event", "", "GitHub event name (pull_request, merge_group, push)")
		baseRefFlag      = flag.String("base-ref", "", "GitHub PR base_ref (e.g. main)")
		baseShaFlag      = flag.String("base-sha", "", "GitHub merge_group base_sha")
		beforeRevFlag    = flag.String("before-rev", "", "GitHub push event.before SHA")
		formatFlag       = flag.String("format", "json", "Output format: json, targets, matrix, text, github-matrix")
		githubMatrixFlag = flag.Bool("output-github-matrix", false, "Emit GitHub Actions step outputs to GITHUB_OUTPUT")
		outputFileFlag   = flag.String("output-file", "", "Write output to specific file path instead of stdout")
		repoRootFlag     = flag.String("repo-root", "", "Path to repository workspace root")
		// 15s could never finish: the rdeps query has to load ~5200 packages,
		// which takes ~110s cold on this repo (~1s once the analysis cache is
		// warm). Every plan therefore timed out and fell back to running
		// everything, so the affected-target engine had never once narrowed a
		// build. 300s leaves headroom on a cold CI runner while still bounding
		// a genuinely stuck query.
		timeoutSecFlag = flag.Int("timeout-sec", 300, "Timeout in seconds for analysis and query execution")
	)
	flag.Parse()

	repoRoot := *repoRootFlag
	if repoRoot == "" {
		if ws := os.Getenv("BUILD_WORKSPACE_DIRECTORY"); ws != "" {
			repoRoot = ws
		} else {
			var err error
			repoRoot, err = os.Getwd()
			if err != nil {
				fmt.Fprintf(os.Stderr, "failed to get current working directory: %v\n", err)
				os.Exit(1)
			}
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(*timeoutSecFlag)*time.Second)
	defer cancel()

	diffOpts := DiffOptions{
		RepoRoot:  repoRoot,
		Base:      *baseFlag,
		Head:      *headFlag,
		BaseRef:   *baseRefFlag,
		BaseSHA:   *baseShaFlag,
		BeforeRev: *beforeRevFlag,
		Event:     *eventFlag,
	}

	changedFiles, baseRev, err := ExtractChangedFiles(ctx, diffOpts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "warning: extract changed files error (%v), falling back to full sweep\n", err)
		// Fail-closed fallback
		changedFiles = []string{"MODULE.bazel"}
		baseRev = "unknown"
	}

	runner := &BazelQueryRunner{}
	engine := NewEngine(repoRoot, runner)

	p, err := engine.ComputePlan(ctx, changedFiles, baseRev, *headFlag)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error computing plan: %v\n", err)
		os.Exit(1)
	}

	// Handle GITHUB_OUTPUT emission if requested
	if *githubMatrixFlag || *formatFlag == "github-matrix" {
		matrixJSON, _ := json.Marshal(p.Matrix)
		hasUnits := "false"
		if len(p.Matrix) > 0 {
			hasUnits = "true"
		}
		docsOnly := "false"
		if p.IsDocsOnly {
			docsOnly = "true"
		}
		globalImpact := "false"
		if p.IsGlobalImpact {
			globalImpact = "true"
		}
		degraded := "false"
		if p.IsDegraded {
			degraded = "true"
		}

		ghOut := os.Getenv("GITHUB_OUTPUT")
		if ghOut != "" {
			f, err := os.OpenFile(ghOut, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0o644)
			if err == nil {
				defer f.Close()
				fmt.Fprintf(f, "matrix=%s\n", string(matrixJSON))
				fmt.Fprintf(f, "has_units=%s\n", hasUnits)
				fmt.Fprintf(f, "docs_only=%s\n", docsOnly)
				fmt.Fprintf(f, "affected_count=%d\n", len(p.Matrix))
				fmt.Fprintf(f, "is_global_impact=%s\n", globalImpact)
				fmt.Fprintf(f, "is_degraded=%s\n", degraded)
			}
		}

		fmt.Printf("matrix=%s\n", string(matrixJSON))
		fmt.Printf("has_units=%s\n", hasUnits)
		fmt.Printf("docs_only=%s\n", docsOnly)
		fmt.Printf("affected_count=%d\n", len(p.Matrix))
		fmt.Printf("is_global_impact=%s\n", globalImpact)
		fmt.Printf("is_degraded=%s\n", degraded)

		// A degraded plan is silent by design -- it just runs everything, which
		// looks identical to a healthy full sweep. Say it out loud, on stderr
		// as a GitHub annotation, so it surfaces in the job log instead of
		// being paid for indefinitely.
		if p.IsDegraded {
			fmt.Fprintf(os.Stderr, "::warning title=Affected-target analysis degraded::Could not determine what changed, so every pipeline unit will run. This is safe but wasteful. Reason: %s\n", p.SweepReason)
		}
		return
	}

	var output string
	switch *formatFlag {
	case "targets":
		var lines []string
		for _, t := range p.Targets {
			lines = append(lines, t)
		}
		output = strings.Join(lines, "\n")
		if output != "" {
			output += "\n"
		}
	case "matrix":
		b, _ := json.MarshalIndent(map[string]interface{}{"include": p.Matrix}, "", "  ")
		output = string(b) + "\n"
	case "text":
		var sb strings.Builder
		sb.WriteString("========================================================\n")
		sb.WriteString("            Smart Pipeline Execution Plan               \n")
		sb.WriteString("========================================================\n")
		fmt.Fprintf(&sb, "Base Revision:      %s\n", p.BaseRev)
		fmt.Fprintf(&sb, "Persona:            %s\n", p.Persona)
		fmt.Fprintf(&sb, "Operation:          %s\n", p.Operation)
		fmt.Fprintf(&sb, "Docs-Only:          %t\n", p.IsDocsOnly)
		fmt.Fprintf(&sb, "Global Impact:      %t (%s)\n", p.IsGlobalImpact, p.SweepReason)
		fmt.Fprintf(&sb, "Degraded:           %t%s\n", p.IsDegraded, degradedHint(p.IsDegraded))
		fmt.Fprintf(&sb, "Changed Files:      %d\n", len(p.ChangedFiles))
		fmt.Fprintf(&sb, "Affected Packages:  %d\n", len(p.AffectedPackages))
		fmt.Fprintf(&sb, "Affected Targets:   %d\n", len(p.Targets))
		fmt.Fprintf(&sb, "Pipeline Units:     %d\n", len(p.Matrix))
		fmt.Fprintf(&sb, "Duration:           %d ms\n", p.DurationMs)
		sb.WriteString("========================================================\n")
		output = sb.String()
	case "json":
		fallthrough
	default:
		b, err := json.MarshalIndent(p, "", "  ")
		if err != nil {
			fmt.Fprintf(os.Stderr, "failed to marshal plan JSON: %v\n", err)
			os.Exit(1)
		}
		output = string(b) + "\n"
	}

	if *outputFileFlag != "" {
		if err := os.WriteFile(*outputFileFlag, []byte(output), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "failed to write output file: %v\n", err)
			os.Exit(1)
		}
	} else {
		fmt.Print(output)
	}
}

// degradedHint spells out what a degraded plan means for whoever is reading
// the log, since "true" on its own reads like a status rather than a problem.
func degradedHint(degraded bool) string {
	if degraded {
		return " (could not determine what changed -- running everything, safe but wasteful)"
	}
	return ""
}
