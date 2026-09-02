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
	"path/filepath"
	"regexp"
	"strings"
)

var (
	docsOnlyRegex   = regexp.MustCompile(`^(docs/|gitops/|\.agents/|devx/docs/)|\.(md|png|jpg|jpeg|svg|txt)$`)
	globalFileRegex = regexp.MustCompile(`^(MODULE\.bazel|MODULE\.bazel\.lock|\.bazelrc|\.bazelversion|BUILD|BUILD\.bazel|gazelle_python\.yaml)$`)
	inertToolsRegex = regexp.MustCompile(`^tools/(ci/|cluster/|conformance/|copybara/|deploy/|doctor/|format/|gcp-secrets/|gitops/|license/|lint/|release/|rotate-buildbuddy-key/|saas-cli/|scripts/|sync-env-secrets/|worktree/|owners/|boundaries/|pipeline/|repin$)`)
)

// IsDocsOnly returns true if every file in the changeset is docs/gitops/markdown/inert assets.
func IsDocsOnly(files []string) bool {
	if len(files) == 0 {
		return false
	}
	for _, f := range files {
		clean := filepath.ToSlash(f)
		if !docsOnlyRegex.MatchString(clean) {
			return false
		}
	}
	return true
}

// CheckGlobalImpact returns true and a reason if any file touches root toolchains or global build configs.
func CheckGlobalImpact(files []string) (bool, string) {
	for _, f := range files {
		clean := filepath.ToSlash(f)
		if globalFileRegex.MatchString(clean) {
			return true, "root build/toolchain config changed: " + clean
		}
		if strings.HasPrefix(clean, "tools/") {
			if !inertToolsRegex.MatchString(clean) {
				return true, "core toolchain directory changed: " + clean
			}
		}
	}
	return false, ""
}
