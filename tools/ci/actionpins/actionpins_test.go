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

package actionpins_test

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/VitruvianSoftware/vitruvian-core/tools/ci/actionpins"
)

func TestParsePins(t *testing.T) {
	manifest := `# Sample action pins
name: "Action Pins"
runs:
  using: "composite"
  steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    - uses: actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
    - uses: astral-sh/setup-uv@1c37ad07a6a961277cf70c0d37d6f313000f5884 # v10.3.0
`
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "action.yml")
	if err := os.WriteFile(path, []byte(manifest), 0o644); err != nil {
		t.Fatalf("failed to write temp manifest: %v", err)
	}

	pins, err := actionpins.Load(path)
	if err != nil {
		t.Fatalf("Load() unexpected error: %v", err)
	}

	if got := pins.Resolve("actions/checkout"); got != "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" {
		t.Errorf("Resolve(actions/checkout) = %q, want %q", got, "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1")
	}

	if got := pins.Resolve("actions/cache/save"); got != "actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6" {
		t.Errorf("Resolve(actions/cache/save) = %q, want %q", got, "actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6")
	}

	if got := pins.Resolve("astral-sh/setup-uv"); got != "astral-sh/setup-uv@1c37ad07a6a961277cf70c0d37d6f313000f5884 # v10.3.0" {
		t.Errorf("Resolve(astral-sh/setup-uv) = %q, want %q", got, "astral-sh/setup-uv@1c37ad07a6a961277cf70c0d37d6f313000f5884 # v10.3.0")
	}
}

func TestEmptyManifestErrors(t *testing.T) {
	manifest := `# Empty manifest
runs:
  using: "composite"
  steps: []
`
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "action.yml")
	if err := os.WriteFile(path, []byte(manifest), 0o644); err != nil {
		t.Fatalf("failed to write temp manifest: %v", err)
	}

	if _, err := actionpins.Load(path); err == nil {
		t.Fatal("expected error loading empty manifest, got nil")
	}
}

func TestDuplicateActionErrors(t *testing.T) {
	manifest := `runs:
  steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
`
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "action.yml")
	if err := os.WriteFile(path, []byte(manifest), 0o644); err != nil {
		t.Fatalf("failed to write temp manifest: %v", err)
	}

	if _, err := actionpins.Load(path); err == nil {
		t.Fatal("expected error loading manifest with duplicate action, got nil")
	}
}

func TestInvalidShaRefErrors(t *testing.T) {
	manifest := `runs:
  steps:
    - uses: actions/checkout@v4 # tag not SHA
`
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "action.yml")
	if err := os.WriteFile(path, []byte(manifest), 0o644); err != nil {
		t.Fatalf("failed to write temp manifest: %v", err)
	}

	if _, err := actionpins.Load(path); err == nil {
		t.Fatal("expected error loading manifest with tag reference instead of SHA, got nil")
	}
}

func TestResolveUnknown(t *testing.T) {
	manifest := `runs:
  steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
`
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "action.yml")
	if err := os.WriteFile(path, []byte(manifest), 0o644); err != nil {
		t.Fatalf("failed to write temp manifest: %v", err)
	}

	pins, err := actionpins.Load(path)
	if err != nil {
		t.Fatalf("Load() unexpected error: %v", err)
	}

	if _, err := pins.Lookup("unknown/action"); err == nil {
		t.Error("expected Lookup(unknown) to return error, got nil")
	}

	defer func() {
		if r := recover(); r == nil {
			t.Errorf("expected Resolve(unknown) to panic, but it did not")
		}
	}()
	_ = pins.Resolve("unknown/action")
}

func TestMustLoadDefault(t *testing.T) {
	pins := actionpins.MustLoadDefault()
	if pins == nil {
		t.Fatal("MustLoadDefault() returned nil")
	}
	all := pins.All()
	if len(all) == 0 {
		t.Fatal("MustLoadDefault() returned empty pins")
	}
	required := []string{
		"actions/checkout",
		"actions/upload-artifact",
		"actions/setup-go",
		"actions/cache",
		"actions/cache/restore",
		"actions/cache/save",
		"google-github-actions/setup-gcloud",
		"docker/setup-buildx-action",
		"azure/setup-helm",
		"astral-sh/setup-uv",
		"pulumi/actions",
	}
	for _, req := range required {
		if pin := pins.Resolve(req); pin == "" {
			t.Errorf("Resolve(%q) returned empty string", req)
		}
	}
}

func findWorkflowsDir() (string, error) {
	relPath := filepath.Join(".github", "workflows")
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
			if fi, err := os.Stat(c); err == nil && fi.IsDir() {
				return c, nil
			}
		}
	}
	if ws := os.Getenv("BUILD_WORKSPACE_DIRECTORY"); ws != "" {
		candidate := filepath.Join(ws, relPath)
		if fi, err := os.Stat(candidate); err == nil && fi.IsDir() {
			return candidate, nil
		}
	}
	dir, err := os.Getwd()
	if err == nil {
		for {
			candidate := filepath.Join(dir, relPath)
			if fi, err := os.Stat(candidate); err == nil && fi.IsDir() {
				return candidate, nil
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
			dir = parent
		}
	}
	return "", os.ErrNotExist
}

// TestGeneratedWorkflowsOnlyUseManifestPins proves that all third-party GitHub Actions
// referenced in generated workflow files (.github/workflows/delivery-*.yaml and
// .github/workflows/presubmit.yaml) are declared in .github/actions/pins/action.yml
// and match their exact pinned SHA and version comments.
func TestGeneratedWorkflowsOnlyUseManifestPins(t *testing.T) {
	pins := actionpins.MustLoadDefault()
	allPins := pins.All()

	wfDir, err := findWorkflowsDir()
	if err != nil {
		t.Fatalf("failed to find workflows dir: %v", err)
	}

	entries, err := os.ReadDir(wfDir)
	if err != nil {
		t.Fatalf("failed to read workflows dir: %v", err)
	}

	checkedCount := 0
	for _, entry := range entries {
		if entry.IsDir() || (!strings.HasSuffix(entry.Name(), ".yaml") && !strings.HasSuffix(entry.Name(), ".yml")) {
			continue
		}
		path := filepath.Join(wfDir, entry.Name())
		content, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("failed to read %s: %v", path, err)
		}
		text := string(content)
		// Only check GENERATED workflows (e.g. delivery-*.yaml and presubmit.yaml)
		if !strings.Contains(text, "# GENERATED by") {
			continue
		}

		checkedCount++
		scanner := bufio.NewScanner(strings.NewReader(text))
		lineNo := 0
		for scanner.Scan() {
			lineNo++
			line := scanner.Text()
			action, parsedPin, err := actionpins.ParsePinLine(line)
			if err != nil {
				t.Errorf("%s:%d: invalid action pin syntax: %v", entry.Name(), lineNo, err)
				continue
			}
			if action == "" {
				continue
			}
			// Skip local composite actions or reusable workflows
			if strings.HasPrefix(action, ".") || strings.HasPrefix(action, "/") {
				continue
			}

			manifestPin, ok := allPins[action]
			if !ok {
				t.Errorf("%s:%d: unpinned third-party action %q in generated workflow (must be added to .github/actions/pins/action.yml)", entry.Name(), lineNo, action)
				continue
			}

			if parsedPin != manifestPin {
				t.Errorf("%s:%d: mismatched pin for action %q in %s:\n  got:  %s\n  want: %s", entry.Name(), lineNo, action, entry.Name(), parsedPin, manifestPin)
			}
		}
	}

	if checkedCount == 0 {
		t.Fatal("no generated workflows were checked; expected at least delivery-*.yaml and presubmit.yaml")
	}
}
