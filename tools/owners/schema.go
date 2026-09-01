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
	"bufio"
	"bytes"
	"fmt"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"
)

// Config represents the schema of an OWNERS file.
type Config struct {
	Approvers []string      `yaml:"approvers,omitempty"`
	Reviewers []string      `yaml:"reviewers,omitempty"`
	Owners    []string      `yaml:"owners,omitempty"`
	Options   Options       `yaml:"options,omitempty"`
	PerFile   []PerFileRule `yaml:"per_file,omitempty"`
}

// Options contains ownership inheritance settings.
type Options struct {
	NoParentOwners bool `yaml:"no_parent_owners,omitempty"`
}

// PerFileRule specifies per-file pattern overrides.
type PerFileRule struct {
	Pattern   string   `yaml:"pattern"`
	Approvers []string `yaml:"approvers,omitempty"`
	Reviewers []string `yaml:"reviewers,omitempty"`
	Owners    []string `yaml:"owners,omitempty"`
}

// EffectiveApprovers returns all approvers and owners combined.
func (c *Config) EffectiveApprovers() []string {
	var out []string
	seen := make(map[string]bool)
	for _, a := range c.Approvers {
		if !seen[a] && a != "" {
			seen[a] = true
			out = append(out, a)
		}
	}
	for _, o := range c.Owners {
		if !seen[o] && o != "" {
			seen[o] = true
			out = append(out, o)
		}
	}
	return out
}

var unquotedHandleRegex = regexp.MustCompile(`(?m)^(\s*-\s+)(@[^\s#"']+)`)

// ParseConfig parses an OWNERS file from raw bytes supporting YAML and simple line formats.
func ParseConfig(data []byte) (*Config, error) {
	trimmed := bytes.TrimSpace(data)
	if len(trimmed) == 0 {
		return nil, fmt.Errorf("OWNERS file is empty")
	}

	// Preprocess to allow unquoted @ in YAML list items
	sanitized := unquotedHandleRegex.ReplaceAll(data, []byte(`$1"$2"`))

	// Attempt YAML unmarshaling
	var cfg Config
	if err := yaml.Unmarshal(sanitized, &cfg); err == nil && (len(cfg.Approvers) > 0 || len(cfg.Owners) > 0 || len(cfg.Reviewers) > 0 || len(cfg.PerFile) > 0 || cfg.Options.NoParentOwners) {
		return &cfg, nil
	}

	// Fallback to line-based parsing
	cfg = Config{}
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if line == "set noparent" || strings.Contains(line, "no_parent_owners: true") {
			cfg.Options.NoParentOwners = true
			continue
		}
		fields := strings.Fields(line)
		for _, f := range fields {
			f = strings.Trim(f, "-,\"':")
			if strings.HasPrefix(f, "@") || strings.Contains(f, "/") {
				cfg.Approvers = append(cfg.Approvers, f)
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("reading line-based OWNERS: %w", err)
	}

	if len(cfg.Approvers) == 0 && len(cfg.Owners) == 0 && !cfg.Options.NoParentOwners {
		return nil, fmt.Errorf("no valid owners/approvers declared")
	}
	return &cfg, nil
}
