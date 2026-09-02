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
	"path/filepath"
	"strings"
)

// RequiredSubtrees are the top-level / key packages that MUST have declared OWNERS.
var RequiredSubtrees = []string{
	"devx",
	"homelab",
	"mcp-slack",
	"nexus-agent",
	"oauth-user-inspector",
	"tabula",
	"backstage",
	"packages/design-system",
	"infrastructure",
	"gitops",
	"tools",
}

// CheckCoverage audits the repository to ensure all required subtrees have explicit OWNERS declarations.
func (e *Engine) CheckCoverage() ([]string, error) {
	var missing []string

	for _, req := range RequiredSubtrees {
		dirPath := filepath.Join(e.RootDir, req)
		info, err := os.Stat(dirPath)
		if err != nil || !info.IsDir() {
			continue // Skip if path does not exist in workspace
		}

		if _, ok := e.Nodes[req]; !ok {
			// Check if OWNERS or OWNERS.yaml file exists
			ownersPath := filepath.Join(dirPath, "OWNERS")
			ownersYamlPath := filepath.Join(dirPath, "OWNERS.yaml")
			ownersYmlPath := filepath.Join(dirPath, "OWNERS.yml")
			if _, err1 := os.Stat(ownersPath); err1 != nil {
				if _, err2 := os.Stat(ownersYamlPath); err2 != nil {
					if _, err3 := os.Stat(ownersYmlPath); err3 != nil {
						missing = append(missing, req)
					}
				}
			}
		}
	}

	// Check root OWNERS
	if _, ok := e.Nodes[""]; !ok {
		rootOwnersPath := filepath.Join(e.RootDir, "OWNERS")
		rootOwnersYamlPath := filepath.Join(e.RootDir, "OWNERS.yaml")
		if _, err1 := os.Stat(rootOwnersPath); err1 != nil {
			if _, err2 := os.Stat(rootOwnersYamlPath); err2 != nil {
				missing = append(missing, "(root)")
			}
		}
	}

	if len(missing) > 0 {
		return missing, fmt.Errorf("missing OWNERS declarations in %d required subtree(s): %s", len(missing), strings.Join(missing, ", "))
	}
	return nil, nil
}
