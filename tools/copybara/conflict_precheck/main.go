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
	"regexp"
	"strings"
)

const exportLabel = "MONOREPO_REV_ID"

// importLabel derives the per-component IMPORT label:
// "mcp-slack" -> "MCP_SLACK_REV_ID", "devx" -> "DEVX_REV_ID".
func importLabel(component string) string {
	upper := strings.ToUpper(strings.ReplaceAll(component, "-", "_"))
	return upper + "_REV_ID"
}

// latestRev returns the first sha found in the most-recent commit message
// that contains "<label>:" in repoDir's current-branch log.
// Returns "" if no such commit exists.
func latestRev(repoDir, label string) string {
	out, err := exec.Command("git", "-C", repoDir, "log", "-1",
		"--grep="+label+":", "--format=%B").Output()
	if err != nil {
		return ""
	}
	re := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(label) + `: ([0-9a-f]{7,40})`)
	m := re.FindSubmatch(out)
	if m == nil {
		return ""
	}
	return string(m[1])
}

// genuineCommits returns the one-line log of commits in repoDir over revRange
// that do NOT carry peerLabel in their message, limited to the given pathspecs.
// Merge commits are excluded. Returns "" (empty) if none.
func genuineCommits(repoDir, revRange, peerLabel string, pathspecs ...string) string {
	args := []string{
		"-C", repoDir,
		"log", revRange,
		"--no-merges",
		"--invert-grep",
		"--grep=" + peerLabel + ":",
		"--format=  %h %s",
		"--",
	}
	args = append(args, pathspecs...)
	out, err := exec.Command("git", args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// monorepoOnlyExcludes returns the set of pathspec excludes for the monorepo-only
// Bazel BUILD files for a given component.
func monorepoOnlyExcludes(c string) []string {
	return []string{
		":(exclude,glob)" + c + "/**/BUILD",
		":(exclude,glob)" + c + "/**/BUILD.bazel",
		":(exclude)" + c + "/BUILD",
		":(exclude)" + c + "/BUILD.bazel",
	}
}

// catFileReachable checks whether <sha>^{commit} is reachable in repoDir.
func catFileReachable(repoDir, sha string) bool {
	err := exec.Command("git", "-C", repoDir, "cat-file", "-e", sha+"^{commit}").Run()
	return err == nil
}

// run implements the full conflict-precheck logic.
// args: [direction, component, monorepoDir, standaloneDir, standalone_only...]
// Returns the exit code (0, 1, or 2).
func run(args []string) int {
	if len(args) < 4 {
		fmt.Fprintln(os.Stderr, "usage: conflict_precheck <export|import> <component> <monorepo_dir> <standalone_dir> [standalone_only...]")
		return 2
	}
	direction := args[0]
	component := args[1]
	monorepoDir := args[2]
	standaloneDir := args[3]
	standaloneOnly := args[4:]

	importLbl := importLabel(component)

	var base, pending, what string

	switch direction {
	case "export":
		// mono->standalone: fail if standalone has genuine change not yet imported.
		base = latestRev(monorepoDir, importLbl)
		if base == "" {
			fmt.Println("[precheck/export] no import baseline yet — skipping")
			return 0
		}
		if !catFileReachable(standaloneDir, base) {
			fmt.Printf("::warning::[precheck/export] import baseline %s not reachable in standalone — skipping\n", base)
			return 0
		}
		scan := []string{"."}
		for _, p := range standaloneOnly {
			scan = append(scan, ":(exclude)"+p)
		}
		pending = genuineCommits(standaloneDir, base+"..HEAD", exportLabel, scan...)
		what = "standalone change not yet imported into the monorepo"

	case "import":
		// standalone->mono: fail if monorepo <component>/ has genuine change not yet exported.
		base = latestRev(standaloneDir, exportLabel)
		if base == "" {
			fmt.Println("[precheck/import] no export baseline yet — skipping")
			return 0
		}
		if !catFileReachable(monorepoDir, base) {
			fmt.Printf("::warning::[precheck/import] export baseline %s not reachable in monorepo — skipping\n", base)
			return 0
		}
		pathspecs := append([]string{component + "/"}, monorepoOnlyExcludes(component)...)
		pending = genuineCommits(monorepoDir, base+"..HEAD", importLbl, pathspecs...)
		what = "monorepo " + component + "/ change not yet exported to the standalone"

	default:
		fmt.Fprintf(os.Stderr, "unknown direction: %s (use export|import)\n", direction)
		return 2
	}

	if pending != "" {
		fmt.Printf("::error title=Copybara conflict pre-check::Refusing to %s %s — the peer repo has an un-synced %s. Syncing now would overwrite it (concurrent conflicting edit). Reconcile by hand, then re-run.\n",
			direction, component, what)
		fmt.Println("Offending un-synced commit(s):")
		fmt.Println(pending)
		return 1
	}
	fmt.Printf("[precheck/%s] OK (%s) — no un-synced genuine peer changes (baseline %s).\n",
		direction, component, base)
	return 0
}

func main() {
	os.Exit(run(os.Args[1:]))
}
