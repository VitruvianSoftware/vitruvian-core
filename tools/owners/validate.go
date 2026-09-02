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
	"path/filepath"
	"regexp"
	"strings"
)

var (
	// GitHub team format: @Org/team-slug
	teamHandleRegex = regexp.MustCompile(`^@[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$`)
	// GitHub user handle format: @username
	userHandleRegex = regexp.MustCompile(`^@[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$`)
	// Email regex
	emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
	// Bare username format: username
	bareUserRegex = regexp.MustCompile(`^[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$`)
)

// ValidateHandle validates whether a given owner/approver handle is syntactically valid.
func ValidateHandle(handle string) error {
	handle = strings.TrimSpace(handle)
	if handle == "" {
		return fmt.Errorf("empty handle")
	}
	if teamHandleRegex.MatchString(handle) {
		return nil
	}
	if userHandleRegex.MatchString(handle) {
		return nil
	}
	if emailRegex.MatchString(handle) {
		return nil
	}
	if bareUserRegex.MatchString(handle) {
		return nil
	}
	return fmt.Errorf("invalid handle syntax %q (expected @Org/team or @username)", handle)
}

// ValidateConfig validates an entire Config.
func ValidateConfig(path string, cfg *Config) error {
	approvers := cfg.EffectiveApprovers()
	if len(approvers) == 0 && !cfg.Options.NoParentOwners {
		return fmt.Errorf("%s: must declare at least one owner or approver", path)
	}
	for _, a := range approvers {
		if err := ValidateHandle(a); err != nil {
			return fmt.Errorf("%s: invalid approver %w", path, err)
		}
	}
	for _, r := range cfg.Reviewers {
		if err := ValidateHandle(r); err != nil {
			return fmt.Errorf("%s: invalid reviewer %w", path, err)
		}
	}
	for _, pf := range cfg.PerFile {
		if pf.Pattern == "" {
			return fmt.Errorf("%s: per_file rule has empty pattern", path)
		}
		// Validate pattern syntax
		if _, err := filepath.Match(pf.Pattern, "test.txt"); err != nil {
			return fmt.Errorf("%s: invalid per_file glob pattern %q: %w", path, pf.Pattern, err)
		}
		for _, a := range pf.Approvers {
			if err := ValidateHandle(a); err != nil {
				return fmt.Errorf("%s: invalid per_file approver %w", path, err)
			}
		}
		for _, o := range pf.Owners {
			if err := ValidateHandle(o); err != nil {
				return fmt.Errorf("%s: invalid per_file owner %w", path, err)
			}
		}
	}
	return nil
}
