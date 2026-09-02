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
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// ResolvePackages maps a list of repository-relative changed file paths to the set of enclosing Bazel packages.
func ResolvePackages(repoRoot string, files []string) ([]string, error) {
	pkgSet := make(map[string]bool)

	for _, relPath := range files {
		clean := filepath.ToSlash(relPath)
		// Clean up leading slashes or dots
		clean = strings.TrimPrefix(clean, "./")
		clean = strings.TrimPrefix(clean, "/")
		if clean == "" {
			continue
		}

		dir := filepath.Dir(clean)

		for dir != "." && dir != "/" && dir != "" {
			buildFile := filepath.Join(repoRoot, dir, "BUILD")
			buildBazelFile := filepath.Join(repoRoot, dir, "BUILD.bazel")

			if fileExists(buildFile) || fileExists(buildBazelFile) {
				pkgSet["//"+filepath.ToSlash(dir)+":all"] = true
				break
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}

	packages := make([]string, 0, len(pkgSet))
	for pkg := range pkgSet {
		packages = append(packages, pkg)
	}
	sort.Strings(packages)
	return packages, nil
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
