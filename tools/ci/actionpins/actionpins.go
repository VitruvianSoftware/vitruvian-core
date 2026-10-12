// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

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

// Pins holds the parsed map of action names to their full pinned string.
type Pins struct {
	pins map[string]string
}

// Load reads and parses an action pin manifest from the given path.
func Load(path string) (*Pins, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open action pins manifest %s: %w", path, err)
	}
	defer f.Close()

	pins := make(map[string]string)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		matches := usesPattern.FindStringSubmatch(line)
		if len(matches) > 0 {
			action := matches[1]
			sha := matches[2]
			comment := strings.TrimSpace(matches[3])
			pinStr := fmt.Sprintf("%s@%s", action, sha)
			if comment != "" {
				pinStr = fmt.Sprintf("%s # %s", pinStr, comment)
			}
			pins[action] = pinStr
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("read action pins manifest %s: %w", path, err)
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

// Resolve returns the full pinned action string (e.g. "actions/checkout@<sha> # <version>")
// for the given action name. Panics if the action is not in the manifest.
func (p *Pins) Resolve(action string) string {
	pin, ok := p.pins[action]
	if !ok {
		panic(fmt.Sprintf("actionpins: unpinned action %q (must be added to .github/actions/pins/action.yml)", action))
	}
	return pin
}

// All returns a copy of all loaded action pins.
func (p *Pins) All() map[string]string {
	cp := make(map[string]string, len(p.pins))
	for k, v := range p.pins {
		cp[k] = v
	}
	return cp
}
