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

// The dependency map (#2465).
//
// Answering "which tests depend on these packages?" live means a cold
// `bazel query` that loads ~8,400 external repos: 6-10 minutes on a fresh
// runner, before any unit can start. The answer only changes when main
// changes, so a push to main computes it once, off the critical path, and
// saves it keyed by that commit. A PR's plan restores the map for its diff
// base and looks the answer up in milliseconds.
//
// Why a map computed at the BASE is safe for a PR on top of it: a PR can only
// add a dependency edge by editing the BUILD file of the package that gains
// it, and every edited package is in the changed set, so its dependents are
// already selected. Two gaps remain and both are handled:
//   - a package the map has never seen (new in this PR) -> Lookup reports
//     !ok and the planner falls back to the live query;
//   - a new test in a changed package that no base-commit test depended on
//     -> the planner also selects any unit whose package contains a changed
//     package (see ComputePlan), which is where such a test would live.
// Anything else wrong with the map (missing, other commit, other schema) also
// falls back to the live query, so the worst case is today's behaviour.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
)

// RdepsMapSchema is bumped whenever the map's meaning changes, so a stale
// cached map is ignored instead of misread. The cache key carries it too.
const RdepsMapSchema = 1

// RdepsMap records, for one commit, which non-manual tests transitively
// depend on each main-repo package.
type RdepsMap struct {
	Schema int    `json:"schema"`
	Commit string `json:"commit"`
	// Packages is every main-repo package at Commit, so a lookup can tell
	// "no test depends on this package" apart from "never heard of it".
	Packages []string `json:"packages"`
	// Tests maps a package ("apps/x", no slashes or :all) to the tests that
	// depend on some target in it. Packages with no dependent test are absent.
	Tests map[string][]string `json:"tests"`
}

// ParseGraphEdges reads `bazel query --output=graph --graph:factored=false`
// and returns the adjacency list (label -> direct deps). Node-only lines
// register the node with no edges.
func ParseGraphEdges(dot string) (map[string][]string, error) {
	edges := make(map[string][]string)
	sc := bufio.NewScanner(strings.NewReader(dot))
	sc.Buffer(make([]byte, 1024*1024), 16*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if !strings.HasPrefix(line, `"`) {
			continue // digraph header, node attributes, closing brace
		}
		if from, to, ok := strings.Cut(line, `" -> "`); ok {
			from = strings.TrimPrefix(from, `"`)
			to = strings.TrimSuffix(to, `"`)
			if strings.Contains(from, "\\n") || strings.Contains(to, "\\n") {
				return nil, fmt.Errorf("factored graph node %q; query must use --graph:factored=false", from)
			}
			edges[from] = append(edges[from], to)
			continue
		}
		node := strings.Trim(line, `"`)
		if _, seen := edges[node]; !seen {
			edges[node] = nil
		}
	}
	return edges, sc.Err()
}

// mainRepoPackage returns the package of a main-repo label ("//a/b:c" ->
// "a/b") and false for external labels.
func mainRepoPackage(label string) (string, bool) {
	for _, p := range []string{"@@//", "@//"} {
		if strings.HasPrefix(label, p) {
			label = "//" + strings.TrimPrefix(label, p)
		}
	}
	if !strings.HasPrefix(label, "//") {
		return "", false
	}
	pkg, _, ok := strings.Cut(strings.TrimPrefix(label, "//"), ":")
	return pkg, ok
}

// ComputeRdepsMap walks each test's transitive deps (through external repos
// too) and records it against every main-repo package it reaches.
func ComputeRdepsMap(commit string, tests []string, edges map[string][]string, packages []string) *RdepsMap {
	byPkg := make(map[string]map[string]bool)
	for _, test := range tests {
		seen := map[string]bool{test: true}
		stack := []string{test}
		for len(stack) > 0 {
			n := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			if pkg, ok := mainRepoPackage(n); ok {
				if byPkg[pkg] == nil {
					byPkg[pkg] = make(map[string]bool)
				}
				byPkg[pkg][test] = true
			}
			for _, d := range edges[n] {
				if !seen[d] {
					seen[d] = true
					stack = append(stack, d)
				}
			}
		}
	}
	m := &RdepsMap{Schema: RdepsMapSchema, Commit: commit, Tests: make(map[string][]string, len(byPkg))}
	for pkg, set := range byPkg {
		for t := range set {
			m.Tests[pkg] = append(m.Tests[pkg], t)
		}
		sort.Strings(m.Tests[pkg])
	}
	m.Packages = append([]string(nil), packages...)
	sort.Strings(m.Packages)
	return m
}

// Lookup returns the tests that depend on the given packages (in the
// planner's "//a/b:all" form). ok is false if any package is unknown to the
// map, in which case the caller must not trust the answer.
func (m *RdepsMap) Lookup(packages []string) (tests []string, ok bool) {
	known := make(map[string]bool, len(m.Packages))
	for _, p := range m.Packages {
		known[p] = true
	}
	set := make(map[string]bool)
	for _, p := range packages {
		pkg := strings.TrimSuffix(strings.TrimPrefix(p, "//"), ":all")
		if !known[pkg] {
			return nil, false
		}
		for _, t := range m.Tests[pkg] {
			set[t] = true
		}
	}
	for t := range set {
		tests = append(tests, t)
	}
	sort.Strings(tests)
	return tests, true
}

// LoadRdepsMap reads a map and checks it describes wantCommit. A missing file
// is not an error: it just means there is no map. Every other problem is
// returned so the planner can say why it fell back to the live query.
func LoadRdepsMap(path, wantCommit string) (*RdepsMap, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var m RdepsMap
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if m.Schema != RdepsMapSchema {
		return nil, fmt.Errorf("map schema %d, want %d", m.Schema, RdepsMapSchema)
	}
	if wantCommit == "" || m.Commit != wantCommit {
		return nil, fmt.Errorf("map is for commit %q, diff base is %q", m.Commit, wantCommit)
	}
	if len(m.Packages) == 0 {
		return nil, fmt.Errorf("map lists no packages")
	}
	return &m, nil
}
