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

// Package unitfile reads pipeline_unit() declarations straight out of BUILD
// files, without running Bazel.
//
// Two tools need the same answer: the presubmit planner
// (//tools/pipeline/plan) decides which units a change affects, and the
// workflow generator (//tools/pipeline/gen) writes a job for each unit. They
// each used to carry their own regular expressions for this, and the two
// drifted: a ")" in a comment inside a call was fixed in the generator and
// not in the planner, which then read that unit as having no test targets
// and never selected it through a dependency. Nothing failed; the unit just
// did not run. One reader, used by both, cannot drift.
//
// The rule it holds to: a unit is either read completely or it is an error
// that names the file and the unit. It never returns a unit with attributes
// quietly missing.
package unitfile

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Defaults for attributes a declaration leaves out.
const (
	DefaultTier           = "L1"
	DefaultRunner         = "ubuntu-26.04"
	DefaultPersona        = "all"
	DefaultTimeoutMinutes = 20
)

// Unit is one pipeline_unit() declaration as written in a BUILD file.
type Unit struct {
	Name    string
	Package string
	// TestTargets are absolute labels: ":x" in package p is "//p:x".
	TestTargets    []string
	Tier           string
	Runner         string
	Persona        string
	TimeoutMinutes int
	DependsOn      []string
	NeedsEmulator  bool
	Env            map[string]string
	Artifacts      map[string]string
	BuildFlags     []string
	// Line is where the call starts in its BUILD file.
	Line int
}

// Parse reads every pipeline_unit() call in the text of one BUILD file. pkg
// is the file's package, "" for the repository root.
//
// The call may hold comments, strings and nested expressions with any
// brackets in them. The attributes this package reads must be literals: a
// unit whose test_targets is glob(...) or a constant cannot be read without
// running Bazel, and that is an error rather than an empty list.
func Parse(content, pkg string) ([]Unit, error) {
	// Most BUILD files declare no unit; do not scan those at all.
	if !strings.Contains(content, "pipeline_unit") {
		return nil, nil
	}
	calls, err := findCalls(content, "pipeline_unit")
	if err != nil {
		return nil, err
	}
	var units []Unit
	for _, c := range calls {
		u, err := unitFromCall(c, pkg)
		if err != nil {
			return nil, err
		}
		units = append(units, u)
	}
	return units, nil
}

func unitFromCall(c call, pkg string) (Unit, error) {
	nameArg, ok := c.args["name"]
	if !ok || nameArg.kind != stringValue || nameArg.str == "" {
		return Unit{}, fmt.Errorf("line %d: pipeline_unit(...): name must be a quoted string", c.line)
	}
	u := Unit{
		Name:           nameArg.str,
		Package:        pkg,
		Tier:           DefaultTier,
		Runner:         DefaultRunner,
		Persona:        DefaultPersona,
		TimeoutMinutes: DefaultTimeoutMinutes,
		Line:           c.line,
	}
	fail := func(format string, a ...any) (Unit, error) {
		return Unit{}, fmt.Errorf("line %d: pipeline_unit(name = %q): %s", c.line, u.Name, fmt.Sprintf(format, a...))
	}

	for attr, dst := range map[string]*string{"tier": &u.Tier, "runner": &u.Runner, "persona": &u.Persona} {
		v, ok := c.args[attr]
		if !ok {
			continue
		}
		if v.kind != stringValue {
			return fail("%s must be a quoted string", attr)
		}
		*dst = v.str
	}

	if v, ok := c.args["timeout_minutes"]; ok {
		if v.kind != intValue {
			return fail("timeout_minutes must be a whole number")
		}
		u.TimeoutMinutes = v.num
	}

	if v, ok := c.args["needs_emulator"]; ok {
		if v.kind != boolValue {
			return fail("needs_emulator must be True or False")
		}
		u.NeedsEmulator = v.truth
	}

	for attr, dst := range map[string]*[]string{"test_targets": &u.TestTargets, "depends_on": &u.DependsOn, "build_flags": &u.BuildFlags} {
		v, ok := c.args[attr]
		if !ok {
			continue
		}
		if v.kind != listValue {
			return fail("%s must be a list written out in the call, [\"...\", ...]; this reader does not run Bazel, so it cannot follow a name, glob() or select()", attr)
		}
		for _, item := range v.list {
			if item.kind != stringValue {
				return fail("every entry of %s must be a quoted string", attr)
			}
			*dst = append(*dst, item.str)
		}
	}

	for attr, dst := range map[string]*map[string]string{"env": &u.Env, "artifacts": &u.Artifacts} {
		v, ok := c.args[attr]
		if !ok {
			continue
		}
		if v.kind != dictValue {
			return fail("%s must be a dict written out in the call, {\"...\": \"...\"}", attr)
		}
		for _, kv := range v.dict {
			if kv[0].kind != stringValue || kv[1].kind != stringValue {
				return fail("every key and value of %s must be a quoted string", attr)
			}
			if *dst == nil {
				*dst = map[string]string{}
			}
			(*dst)[kv[0].str] = kv[1].str
		}
	}

	// The macro refuses a unit with no targets, so one that reads as empty
	// here was misread or is about to fail in Bazel. Either way it must not
	// reach the planner as "nothing to run".
	if len(u.TestTargets) == 0 {
		return fail("test_targets is missing or empty")
	}
	for i, t := range u.TestTargets {
		if strings.HasPrefix(t, ":") {
			u.TestTargets[i] = "//" + pkg + t
		}
	}
	return u, nil
}

// Discover reads every BUILD and BUILD.bazel file under root and returns the
// units they declare, sorted by name. Every unreadable declaration is
// reported, each with its file, and so is a name declared twice.
func Discover(root string) ([]Unit, error) {
	var units []Unit
	var errs []error
	declaredIn := map[string]string{}

	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		name := info.Name()
		if info.IsDir() {
			if name == ".git" || name == "node_modules" || name == ".claude" {
				return filepath.SkipDir
			}
			// Bazel's output links at the top of the workspace. A real
			// directory deeper down may carry the prefix (tools/bazel-cache).
			if strings.HasPrefix(name, "bazel-") && filepath.Dir(path) == root {
				return filepath.SkipDir
			}
			return nil
		}
		if name != "BUILD" && name != "BUILD.bazel" {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return nil
		}
		rel = filepath.ToSlash(rel)
		pkg := ""
		if i := strings.LastIndexByte(rel, '/'); i >= 0 {
			pkg = rel[:i]
		}

		content, err := os.ReadFile(path)
		if err != nil {
			// A BUILD file that cannot be read may hold a unit.
			errs = append(errs, fmt.Errorf("%s: %w", rel, err))
			return nil
		}
		parsed, err := Parse(string(content), pkg)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", rel, err))
			return nil
		}
		for _, u := range parsed {
			if first, dup := declaredIn[u.Name]; dup {
				errs = append(errs, fmt.Errorf("%s: line %d: pipeline_unit(name = %q) is already declared in %s; unit names must be unique across the repository", rel, u.Line, u.Name, first))
				continue
			}
			declaredIn[u.Name] = rel
			units = append(units, u)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	if len(errs) > 0 {
		return nil, fmt.Errorf("cannot read every pipeline unit:\n%w", errors.Join(errs...))
	}

	sort.Slice(units, func(i, j int) bool { return units[i].Name < units[j].Name })
	return units, nil
}
