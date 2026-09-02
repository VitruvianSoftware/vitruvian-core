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
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const SchemaVersion = 1

// Unit represents a single pipeline verification unit decoded from JSON or query.
type Unit struct {
	Schema           int               `json:"schema"`
	Name             string            `json:"name"`
	Package          string            `json:"package"`
	TestTargets      []string          `json:"test_targets"`
	Tier             string            `json:"tier"`
	Runner           string            `json:"runner"`
	Persona          string            `json:"persona"`
	ConcurrencyGroup string            `json:"concurrency_group"`
	TimeoutMinutes   int               `json:"timeout_minutes"`
	Env              map[string]string `json:"env,omitempty"`
	DependsOn        []string          `json:"depends_on,omitempty"`
	Tags             []string          `json:"tags,omitempty"`
}

// DecodeUnit unmarshals and validates a pipeline unit JSON payload.
func DecodeUnit(b []byte) (Unit, error) {
	var u Unit
	if err := json.Unmarshal(b, &u); err != nil {
		return u, fmt.Errorf("decode unit json: %w", err)
	}
	if u.Schema != SchemaVersion {
		return u, fmt.Errorf("unit %q: unsupported schema version %d (expected %d)", u.Name, u.Schema, SchemaVersion)
	}
	if strings.TrimSpace(u.Name) == "" {
		return u, errors.New("unit name must not be empty")
	}
	if len(u.TestTargets) == 0 {
		return u, fmt.Errorf("unit %q has no test targets", u.Name)
	}
	if u.Runner == "" {
		u.Runner = "ubuntu-latest"
	}
	if u.TimeoutMinutes <= 0 {
		u.TimeoutMinutes = 30
	}
	if u.Tier == "" {
		u.Tier = "L1"
	}
	if u.Persona == "" {
		u.Persona = "all"
	}
	if u.ConcurrencyGroup == "" {
		u.ConcurrencyGroup = "pipeline-" + u.Name
	}
	return u, nil
}

// LoadUnits reads and validates multiple unit JSON files.
func LoadUnits(paths []string) ([]Unit, error) {
	units := make([]Unit, 0, len(paths))
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			return nil, fmt.Errorf("read unit %s: %w", p, err)
		}
		u, err := DecodeUnit(b)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", p, err)
		}
		units = append(units, u)
	}

	// Deterministic sort by name
	sort.Slice(units, func(i, j int) bool { return units[i].Name < units[j].Name })

	// Check for duplicates
	for i := 1; i < len(units); i++ {
		if units[i].Name == units[i-1].Name {
			return nil, fmt.Errorf("duplicate pipeline unit name %q — unit names must be unique repo-wide", units[i].Name)
		}
	}
	return units, nil
}

// FindUnitFiles searches a directory tree for *.pipeline.json files.
func FindUnitFiles(root string) ([]string, error) {
	var paths []string
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			name := info.Name()
			if name == ".git" || name == "bazel-out" || name == "bazel-bin" || name == "node_modules" {
				return filepath.SkipDir
			}
			return nil
		}
		if strings.HasSuffix(info.Name(), ".pipeline.json") {
			paths = append(paths, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(paths)
	return paths, nil
}
