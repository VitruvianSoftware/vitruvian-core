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
	"strings"
	"testing"
)

func TestParseConfig(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		wantApps  int
		wantNoPar bool
		wantErr   bool
	}{
		{
			name: "valid yaml",
			input: `
approvers:
  - @VitruvianSoftware/devx-team
  - @alice
options:
  no_parent_owners: true
`,
			wantApps:  2,
			wantNoPar: true,
			wantErr:   false,
		},
		{
			name: "legacy line-based",
			input: `
set noparent
@VitruvianSoftware/platform-team
@bob
`,
			wantApps:  2,
			wantNoPar: true,
			wantErr:   false,
		},
		{
			name:    "empty input",
			input:   "   \n  ",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg, err := ParseConfig([]byte(tt.input))
			if (err != nil) != tt.wantErr {
				t.Fatalf("ParseConfig() error = %v, wantErr %v", err, tt.wantErr)
			}
			if err == nil {
				apps := cfg.EffectiveApprovers()
				if len(apps) != tt.wantApps {
					t.Errorf("EffectiveApprovers() len = %d, want %d", len(apps), tt.wantApps)
				}
				if cfg.Options.NoParentOwners != tt.wantNoPar {
					t.Errorf("NoParentOwners = %v, want %v", cfg.Options.NoParentOwners, tt.wantNoPar)
				}
			}
		})
	}
}

func TestValidateHandle(t *testing.T) {
	valid := []string{
		"@VitruvianSoftware/platform-team",
		"@VitruvianSoftware/devx-team",
		"@alice",
		"@bob-123",
		"charlie",
		"user@example.com",
	}
	invalid := []string{
		"",
		"@",
		"@/team",
		"@org/",
		"@invalid@user",
		"invalid user with spaces",
	}

	for _, h := range valid {
		if err := ValidateHandle(h); err != nil {
			t.Errorf("ValidateHandle(%q) unexpected error: %v", h, err)
		}
	}
	for _, h := range invalid {
		if err := ValidateHandle(h); err == nil {
			t.Errorf("ValidateHandle(%q) expected error, got nil", h)
		}
	}
}

func TestEngine_InheritanceAndCompilation(t *testing.T) {
	tmpDir := t.TempDir()

	// 1. Root OWNERS
	rootOwners := `
approvers:
  - @VitruvianSoftware/platform-team
`
	if err := os.WriteFile(filepath.Join(tmpDir, "OWNERS"), []byte(rootOwners), 0o644); err != nil {
		t.Fatal(err)
	}

	// 2. devx/OWNERS (inherits from root)
	if err := os.MkdirAll(filepath.Join(tmpDir, "devx"), 0o755); err != nil {
		t.Fatal(err)
	}
	devxOwners := `
approvers:
  - @VitruvianSoftware/devx-team
per_file:
  - pattern: "*.md"
    approvers:
      - @VitruvianSoftware/docs-team
`
	if err := os.WriteFile(filepath.Join(tmpDir, "devx", "OWNERS"), []byte(devxOwners), 0o644); err != nil {
		t.Fatal(err)
	}

	// 3. tabula/OWNERS (no_parent_owners: true)
	if err := os.MkdirAll(filepath.Join(tmpDir, "tabula"), 0o755); err != nil {
		t.Fatal(err)
	}
	tabulaOwners := `
approvers:
  - @VitruvianSoftware/tabula-team
options:
  no_parent_owners: true
`
	if err := os.WriteFile(filepath.Join(tmpDir, "tabula", "OWNERS"), []byte(tabulaOwners), 0o644); err != nil {
		t.Fatal(err)
	}

	engine := NewEngine(tmpDir)
	if err := engine.Discover(); err != nil {
		t.Fatalf("Discover() error: %v", err)
	}

	// Verify devx inherited platform-team
	devxNode := engine.Nodes["devx"]
	if devxNode == nil {
		t.Fatal("missing devx node")
	}
	if len(devxNode.Effective) != 2 {
		t.Errorf("devx Effective count = %d, want 2 (%v)", len(devxNode.Effective), devxNode.Effective)
	}

	// Verify tabula did NOT inherit platform-team
	tabulaNode := engine.Nodes["tabula"]
	if tabulaNode == nil {
		t.Fatal("missing tabula node")
	}
	if len(tabulaNode.Effective) != 1 || tabulaNode.Effective[0] != "@VitruvianSoftware/tabula-team" {
		t.Errorf("tabula Effective = %v, want [@VitruvianSoftware/tabula-team]", tabulaNode.Effective)
	}

	// Verify compilation
	compiled, err := engine.Compile()
	if err != nil {
		t.Fatalf("Compile() error: %v", err)
	}

	if !strings.Contains(compiled, "* @VitruvianSoftware/platform-team") {
		t.Errorf("compiled output missing catch-all default:\n%s", compiled)
	}
	if !strings.Contains(compiled, "/devx/ @VitruvianSoftware/devx-team @VitruvianSoftware/platform-team") {
		t.Errorf("compiled output missing devx rule:\n%s", compiled)
	}
	if !strings.Contains(compiled, "/devx/*.md @VitruvianSoftware/docs-team") {
		t.Errorf("compiled output missing devx per-file rule:\n%s", compiled)
	}
	if !strings.Contains(compiled, "/tabula/ @VitruvianSoftware/tabula-team") {
		t.Errorf("compiled output missing tabula rule:\n%s", compiled)
	}
}

func TestEngine_CoverageCheck(t *testing.T) {
	tmpDir := t.TempDir()

	// Only create devx and tabula dirs
	if err := os.MkdirAll(filepath.Join(tmpDir, "devx"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(tmpDir, "tabula"), 0o755); err != nil {
		t.Fatal(err)
	}

	engine := NewEngine(tmpDir)
	if err := engine.Discover(); err != nil {
		t.Fatal(err)
	}

	missing, err := engine.CheckCoverage()
	if err == nil || len(missing) == 0 {
		t.Fatalf("expected coverage failures for missing OWNERS, got err=%v missing=%v", err, missing)
	}

	// Now add OWNERS to all required dirs
	if err := os.WriteFile(filepath.Join(tmpDir, "OWNERS"), []byte("approvers:\n  - @VitruvianSoftware/platform-team\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "devx", "OWNERS"), []byte("approvers:\n  - @VitruvianSoftware/devx-team\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "tabula", "OWNERS"), []byte("approvers:\n  - @VitruvianSoftware/tabula-team\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	engine2 := NewEngine(tmpDir)
	if err := engine2.Discover(); err != nil {
		t.Fatal(err)
	}
	missing2, err2 := engine2.CheckCoverage()
	if err2 != nil || len(missing2) > 0 {
		t.Fatalf("expected coverage pass for existing dirs, got err=%v missing=%v", err2, missing2)
	}
}
