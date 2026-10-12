// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

package actionpins_test

import (
	"os"
	"path/filepath"
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

func TestResolveUnknownPanics(t *testing.T) {
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
