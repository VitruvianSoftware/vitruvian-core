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
)

func main() {
	fs := flag.NewFlagSet("packages-index", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)

	checkFlag := fs.Bool("check", false, "Verify packages/README.md matches packages/**/catalog-info.yaml (default)")
	writeFlag := fs.Bool("write", false, "Update the generated table in packages/README.md")
	rootFlag := fs.String("root", os.Getenv("BUILD_WORKSPACE_DIRECTORY"), "Repository root directory (defaults to BUILD_WORKSPACE_DIRECTORY)")

	if err := fs.Parse(os.Args[1:]); err != nil {
		os.Exit(2)
	}
	if fs.NArg() > 0 {
		_, _ = fmt.Fprintf(os.Stderr, "packages-index: unexpected positional arguments: %v\n", fs.Args())
		os.Exit(2)
	}
	if *checkFlag && *writeFlag {
		_, _ = fmt.Fprintln(os.Stderr, "packages-index: --check and --write are mutually exclusive")
		os.Exit(2)
	}
	if *rootFlag == "" {
		_, _ = fmt.Fprintln(os.Stderr, "packages-index: BUILD_WORKSPACE_DIRECTORY is not set; run via `bazel run //tools/packages-index -- [--check|--write]` or pass --root <dir>")
		os.Exit(2)
	}

	os.Exit(Run(*rootFlag, *writeFlag, os.Stdout, os.Stderr))
}
