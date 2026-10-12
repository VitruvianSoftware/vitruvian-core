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

// Package actionpins provides the single source of truth for third-party
// GitHub Action pins used across the monorepo's workflow generators.
package actionpins

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// usesPattern matches:
//   - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
//     uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
var usesPattern = regexp.MustCompile(`(?m)^\s*(?:-\s*)?uses:\s*([^\s@]+)@([^\s#]+)(?:\s*#\s*(.*))?$`)

// shaPattern validates that action references use an immutable 40-character hex commit SHA.
var shaPattern = regexp.MustCompile(`^[0-9a-f]{40}$`)

// Pins holds the parsed map of action names to their full pinned string.
type Pins struct {
	pins map[string]string
}

// ParsePinLine parses a single workflow line containing an action pin.
// Returns the action name, the formatted pin string (including comment if present),
// or ("", "", nil) if the line does not define a uses: action@ref step.
func ParsePinLine(line string) (action, pin string, err error) {
	matches := usesPattern.FindStringSubmatch(line)
	if len(matches) == 0 {
		return "", "", nil
	}
	action = matches[1]
	sha := matches[2]
	if !shaPattern.MatchString(sha) {
		return "", "", fmt.Errorf("action %q has invalid ref %q: must be a 40-character hexadecimal commit SHA", action, sha)
	}
	comment := strings.TrimSpace(matches[3])
	pin = fmt.Sprintf("%s@%s", action, sha)
	if comment != "" {
		pin = fmt.Sprintf("%s # %s", pin, comment)
	}
	return action, pin, nil
}

// Load reads and parses an action pin manifest from the given path.
// It fails if the file cannot be read, contains invalid SHAs, contains duplicate
// entries, or defines zero valid pins.
func Load(path string) (*Pins, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open action pins manifest %s: %w", path, err)
	}
	defer f.Close()

	pins := make(map[string]string)
	scanner := bufio.NewScanner(f)
	lineNo := 0
	for scanner.Scan() {
		lineNo++
		line := scanner.Text()
		action, pinStr, parseErr := ParsePinLine(line)
		if parseErr != nil {
			return nil, fmt.Errorf("%s:%d: %w", path, lineNo, parseErr)
		}
		if action == "" {
			continue
		}
		if _, exists := pins[action]; exists {
			return nil, fmt.Errorf("%s:%d: duplicate action pin for %q", path, lineNo, action)
		}
		pins[action] = pinStr
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read action pins manifest %s: %w", path, err)
	}
	if len(pins) == 0 {
		return nil, fmt.Errorf("action pins manifest %s contained 0 valid pins", path)
	}
	return &Pins{pins: pins}, nil
}

// FindDefaultPath locates the .github/actions/pins/action.yml file.
func FindDefaultPath() (string, error) {
	relPath := filepath.Join(".github", "actions", "pins", "action.yml")

	// 1. If run via `bazel run`, BUILD_WORKSPACE_DIRECTORY points to the repo root.
	if ws := os.Getenv("BUILD_WORKSPACE_DIRECTORY"); ws != "" {
		candidate := filepath.Join(ws, relPath)
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}

	// 2. If run via `bazel test`, check runfiles.
	if srcdir := os.Getenv("TEST_SRCDIR"); srcdir != "" {
		ws := os.Getenv("TEST_WORKSPACE")
		if ws == "" {
			ws = "_main"
		}
		candidates := []string{
			filepath.Join(srcdir, ws, relPath),
			filepath.Join(srcdir, relPath),
		}
		for _, c := range candidates {
			if _, err := os.Stat(c); err == nil {
				return c, nil
			}
		}
	}

	// 3. Search upwards from cwd.
	dir, err := os.Getwd()
	if err == nil {
		for {
			candidate := filepath.Join(dir, relPath)
			if _, err := os.Stat(candidate); err == nil {
				return candidate, nil
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}

	return "", fmt.Errorf("could not locate %s", relPath)
}

// MustLoadDefault loads the pin manifest from the repository's default location.
func MustLoadDefault() *Pins {
	path, err := FindDefaultPath()
	if err != nil {
		panic(fmt.Sprintf("actionpins: failed to find pin manifest: %v", err))
	}
	pins, err := Load(path)
	if err != nil {
		panic(fmt.Sprintf("actionpins: failed to load pin manifest: %v", err))
	}
	return pins
}

// Lookup returns the full pinned action string or an error if unpinned.
func (p *Pins) Lookup(action string) (string, error) {
	if p == nil || p.pins == nil {
		return "", fmt.Errorf("actionpins: nil pins manifest")
	}
	pin, ok := p.pins[action]
	if !ok {
		return "", fmt.Errorf("actionpins: unpinned action %q (must be added to .github/actions/pins/action.yml)", action)
	}
	return pin, nil
}

// Resolve returns the full pinned action string (e.g. "actions/checkout@<sha> # <version>")
// for the given action name. Panics if the action is not in the manifest.
func (p *Pins) Resolve(action string) string {
	pin, err := p.Lookup(action)
	if err != nil {
		panic(err.Error())
	}
	return pin
}

// All returns a copy of all loaded action pins.
func (p *Pins) All() map[string]string {
	if p == nil || p.pins == nil {
		return nil
	}
	cp := make(map[string]string, len(p.pins))
	for k, v := range p.pins {
		cp[k] = v
	}
	return cp
}
