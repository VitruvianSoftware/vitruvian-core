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
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTestFile(t *testing.T, root, rel, content string) {
	t.Helper()
	abs := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", abs, err)
	}
	if err := os.WriteFile(abs, []byte(content), 0o644); err != nil {
		t.Fatalf("write %s: %v", abs, err)
	}
}

func TestDiscoverPackagesMultiDocAndNested(t *testing.T) {
	root := t.TempDir()

	writeTestFile(t, root, "packages/gocompat/README.md", "# gocompat\n")
	writeTestFile(t, root, "packages/gocompat/catalog-info.yaml", `apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: gocompat
  description: Go standard-library helpers for Rust
  tags:
    - rust
    - process
  annotations:
    vitruvian.dev/bazel-target: //packages/gocompat:vitruvian_gocompat
spec:
  type: library
  owner: platform-team
`)

	writeTestFile(t, root, "packages/rust/vitruvian-pycompat/README.md", "# vitruvian-pycompat\n")
	writeTestFile(t, root, "packages/rust/vitruvian-pycompat/catalog-info.yaml", `apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: vitruvian-pycompat
  description: |
    Python string and JSON
    compatibility crate
  tags:
    - Rust
    - rust
    - json
  annotations:
    vitruvian.dev/bazel-target: //packages/rust/vitruvian-pycompat:vitruvian_pycompat, //packages/rust/vitruvian-pycompat:extra
spec:
  type: library
  owner: platform-team
`)

	writeTestFile(t, root, "packages/swift/SentryLite/README.md", "# SentryLite\n")
	writeTestFile(t, root, "packages/swift/SentryLite/catalog-info.yaml", `apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: sentry-lite
  description: Swift Sentry client | minimal
  tags:
    - swift
    - go
    - typescript
    - kotlin
    - javascript
    - python
    - cpp
    - telemetry
  annotations:
    vitruvian.dev/bazel-target: //packages/swift/SentryLite:SentryLite
spec:
  type: library
  owner: mobile-team
`)

	// Multi-document YAML: 2 library components + 1 reference-architecture + 1 System + 1 empty doc.
	writeTestFile(t, root, "packages/pulumi/README.md", "# Pulumi\n")
	writeTestFile(t, root, "packages/pulumi/library/go/README.md", "# Pulumi Go\n")
	writeTestFile(t, root, "packages/pulumi/library/ts/README.md", "# Pulumi TS\n")
	writeTestFile(t, root, "packages/pulumi/catalog-info.yaml", `---
---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: pulumi-library-ts
  description: Pulumi TypeScript library
  tags:
    - typescript
    - pulumi
  annotations:
    backstage.io/techdocs-ref: dir:./library/ts
    vitruvian.dev/bazel-target: //packages/pulumi/library/ts:pkg
spec:
  type: library
  owner: platform-team
---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: pulumi-library-go
  description: Pulumi Go library
  tags:
    - go
    - iac
  annotations:
    backstage.io/techdocs-ref: dir:./library/go
    vitruvian.dev/bazel-target: //packages/pulumi/library/go/pkg/app
spec:
  type: library
  owner: platform-team
---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: pulumi-example-foundation-go
  description: Example architecture
  tags:
    - go
spec:
  type: reference-architecture
  owner: platform-team
---
apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: pulumi-libraries
spec:
  owner: platform-team
`)

	// Ignored directories should not be walked.
	writeTestFile(t, root, "packages/node_modules/ignored/catalog-info.yaml", `kind: Component
metadata:
  name: ignored-pkg
spec:
  type: library
  owner: nobody
`)

	entries, err := DiscoverPackages(root)
	if err != nil {
		t.Fatalf("DiscoverPackages error: %v", err)
	}
	if len(entries) != 5 {
		t.Fatalf("expected 5 library entries, got %d: %+v", len(entries), entries)
	}

	gotNames := make([]string, len(entries))
	for i, e := range entries {
		gotNames[i] = e.Name
	}
	wantNames := []string{"gocompat", "pulumi-library-go", "pulumi-library-ts", "sentry-lite", "vitruvian-pycompat"}
	for i := range wantNames {
		if gotNames[i] != wantNames[i] {
			t.Fatalf("sorted order mismatch: got %v, want %v", gotNames, wantNames)
		}
	}

	if entries[0].ReadmeLink != "./gocompat/README.md" {
		t.Errorf("gocompat link = %q", entries[0].ReadmeLink)
	}
	if entries[1].ReadmeLink != "./pulumi/library/go/README.md" {
		t.Errorf("pulumi-library-go link = %q", entries[1].ReadmeLink)
	}
	if entries[2].ReadmeLink != "./pulumi/library/ts/README.md" {
		t.Errorf("pulumi-library-ts link = %q", entries[2].ReadmeLink)
	}
	if entries[3].Languages != "swift, go, typescript, kotlin, javascript, python, cpp" {
		t.Errorf("sentry-lite languages = %q", entries[3].Languages)
	}
	if entries[4].Languages != "rust" {
		t.Errorf("vitruvian-pycompat languages deduplication failed: %q", entries[4].Languages)
	}
	if entries[4].Description != "Python string and JSON compatibility crate" {
		t.Errorf("vitruvian-pycompat description = %q", entries[4].Description)
	}
	if entries[4].BazelTarget != "`//packages/rust/vitruvian-pycompat:vitruvian_pycompat`, `//packages/rust/vitruvian-pycompat:extra`" {
		t.Errorf("vitruvian-pycompat target = %q", entries[4].BazelTarget)
	}
}

func TestDiscoverPackagesRejectsDuplicates(t *testing.T) {
	root := t.TempDir()
	doc := `kind: Component
metadata:
  name: dup-pkg
  description: Duplicate
spec:
  type: library
  owner: platform-team
`
	writeTestFile(t, root, "packages/a/catalog-info.yaml", doc)
	writeTestFile(t, root, "packages/b/catalog-info.yaml", doc)

	_, err := DiscoverPackages(root)
	if err == nil || !strings.Contains(err.Error(), "duplicate library package name") {
		t.Fatalf("expected duplicate error, got %v", err)
	}
}

func TestReplaceGeneratedSectionPreservesHeaderAndEscapesPipes(t *testing.T) {
	header := "# Packages\n\nHand-written intro.\n\n"
	footer := "\n\nHand-written footer.\n"
	existing := header + BeginMarker + "\nstale\n" + EndMarker + footer

	rendered := RenderGeneratedSection([]PackageEntry{
		{
			Name:        "alpha",
			ReadmeLink:  "./alpha/README.md",
			Description: "Handles A | B cases",
			Languages:   "go",
			BazelTarget: "`//packages/alpha:alpha`",
			Owner:       "team-a",
		},
	})

	updated, err := ReplaceGeneratedSection(existing, rendered)
	if err != nil {
		t.Fatalf("ReplaceGeneratedSection error: %v", err)
	}
	if !strings.HasPrefix(updated, header) {
		t.Errorf("header mutated: %q", updated)
	}
	if !strings.HasSuffix(updated, footer) {
		t.Errorf("footer mutated: %q", updated)
	}
	if !strings.Contains(updated, "Handles A \\| B cases") {
		t.Errorf("expected pipe escaped in %q", updated)
	}

	if _, err := ReplaceGeneratedSection("no markers here", rendered); err == nil {
		t.Error("expected error on missing markers")
	}
	if _, err := ReplaceGeneratedSection(EndMarker+BeginMarker, rendered); err == nil {
		t.Error("expected error on reversed markers")
	}
	if _, err := ReplaceGeneratedSection(BeginMarker+BeginMarker+EndMarker, rendered); err == nil {
		t.Error("expected error on duplicate markers")
	}
}

func TestRunWriteAndCheckDrift(t *testing.T) {
	root := t.TempDir()
	writeTestFile(t, root, "packages/demo/README.md", "# Demo\n")
	writeTestFile(t, root, "packages/demo/catalog-info.yaml", `kind: Component
metadata:
  name: demo
  description: Original description
  tags:
    - go
  annotations:
    vitruvian.dev/bazel-target: //packages/demo:demo
spec:
  type: library
  owner: platform-team
`)
	writeTestFile(t, root, "packages/README.md", "# Packages\n\n"+BeginMarker+"\n"+EndMarker+"\n")

	var out, errBuf bytes.Buffer
	if code := Run(root, true, &out, &errBuf); code != 0 {
		t.Fatalf("--write failed (code=%d): %s", code, errBuf.String())
	}

	out.Reset()
	errBuf.Reset()
	if code := Run(root, false, &out, &errBuf); code != 0 {
		t.Fatalf("--check after --write failed (code=%d): %s", code, errBuf.String())
	}

	// Simulate catalog change causing drift.
	writeTestFile(t, root, "packages/demo/catalog-info.yaml", `kind: Component
metadata:
  name: demo
  description: Changed description
  tags:
    - go
  annotations:
    vitruvian.dev/bazel-target: //packages/demo:demo
spec:
  type: library
  owner: platform-team
`)

	out.Reset()
	errBuf.Reset()
	code := Run(root, false, &out, &errBuf)
	if code != 1 {
		t.Fatalf("expected exit 1 on drift, got %d", code)
	}
	msg := errBuf.String()
	if !strings.Contains(msg, "drift detected in packages/README.md") {
		t.Errorf("missing drift header in stderr: %q", msg)
	}
	if !strings.Contains(msg, "bazel run //tools/packages-index -- --write") {
		t.Errorf("missing remediation command in stderr: %q", msg)
	}
}
