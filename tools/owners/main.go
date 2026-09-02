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
	"flag"
	"fmt"
	"os"
	"path/filepath"
)

func main() {
	outFlag := flag.String("out", "", "Output path for compiled CODEOWNERS file")
	checkFlag := flag.Bool("check", false, "Check that .github/CODEOWNERS matches compiled output")
	coverageFlag := flag.Bool("coverage-check", false, "Verify OWNERS coverage conformance across all subtrees")
	validateFlag := flag.Bool("validate-only", false, "Validate syntax of all OWNERS files without compiling")
	rootFlag := flag.String("root", "", "Repository root directory (defaults to current dir or workspace root)")
	flag.Parse()

	rootDir := *rootFlag
	if rootDir == "" {
		if ws := os.Getenv("BUILD_WORKSPACE_DIRECTORY"); ws != "" {
			rootDir = ws
		} else {
			rootDir = "."
		}
	}

	absRoot, err := filepath.Abs(rootDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error resolving root directory: %v\n", err)
		os.Exit(1)
	}

	engine := NewEngine(absRoot)
	if err := engine.Discover(); err != nil {
		fmt.Fprintf(os.Stderr, "Discovery error: %v\n", err)
		os.Exit(1)
	}

	if *validateFlag {
		fmt.Printf("All %d OWNERS files validated successfully.\n", len(engine.Nodes))
		return
	}

	if *coverageFlag {
		missing, err := engine.CheckCoverage()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Coverage audit FAILED:\n")
			for _, m := range missing {
				fmt.Fprintf(os.Stderr, "  - Missing OWNERS in %s\n", m)
			}
			os.Exit(1)
		}
		fmt.Printf("Coverage audit PASSED: all required subtrees have declared OWNERS.\n")
	}

	compiled, err := engine.Compile()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Compilation error: %v\n", err)
		os.Exit(1)
	}

	if *checkFlag {
		codeownersPath := filepath.Join(absRoot, ".github", "CODEOWNERS")
		current, err := os.ReadFile(codeownersPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading %s: %v\n", codeownersPath, err)
			os.Exit(1)
		}
		if string(current) != compiled {
			fmt.Fprintf(os.Stderr, "CODEOWNERS drift detected! Run `bazel run //tools/owners -- --out .github/CODEOWNERS` to regenerate.\n")
			os.Exit(1)
		}
		fmt.Printf(".github/CODEOWNERS is up to date.\n")
		return
	}

	if *outFlag != "" {
		outPath := *outFlag
		if !filepath.IsAbs(outPath) {
			outPath = filepath.Join(absRoot, outPath)
		}
		if err := os.MkdirAll(filepath.Dir(outPath), 0o755); err != nil {
			fmt.Fprintf(os.Stderr, "Error creating parent dirs for %s: %v\n", outPath, err)
			os.Exit(1)
		}
		if err := os.WriteFile(outPath, []byte(compiled), 0o644); err != nil {
			fmt.Fprintf(os.Stderr, "Error writing to %s: %v\n", outPath, err)
			os.Exit(1)
		}
		fmt.Printf("Wrote compiled CODEOWNERS to %s\n", outPath)
	} else if !*coverageFlag {
		fmt.Print(compiled)
	}
}
