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
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

type mockQueryRunner struct {
	rdepsMap  map[string][]string
	units     []string
	shouldErr bool
}

func (m *mockQueryRunner) QueryTestRdeps(ctx context.Context, repoRoot string, packages []string) ([]string, error) {
	if m.shouldErr {
		return nil, errors.New("simulated query error")
	}
	var res []string
	for _, p := range packages {
		if targets, ok := m.rdepsMap[p]; ok {
			res = append(res, targets...)
		}
	}
	return res, nil
}

func (m *mockQueryRunner) QueryPipelineUnits(ctx context.Context, repoRoot string) ([]string, error) {
	if m.shouldErr {
		return nil, errors.New("simulated query error")
	}
	return m.units, nil
}

func TestDocsOnlyFastGate(t *testing.T) {
	tests := []struct {
		name     string
		files    []string
		expected bool
	}{
		{
			name:     "all markdown files",
			files:    []string{"docs/index.md", "README.md", "devx/docs/guide.md"},
			expected: true,
		},
		{
			name:     "gitops and agents",
			files:    []string{"gitops/argocd/app.yaml", ".agents/task.md"},
			expected: true,
		},
		{
			name:     "image assets in docs",
			files:    []string{"docs/arch.png", "docs/diagram.svg"},
			expected: true,
		},
		{
			name:     "code change mixed with docs",
			files:    []string{"docs/index.md", "tabula/api/src/app.ts"},
			expected: false,
		},
		{
			name:     "empty file list",
			files:    []string{},
			expected: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := IsDocsOnly(tc.files)
			if got != tc.expected {
				t.Errorf("IsDocsOnly(%v) = %v, expected %v", tc.files, got, tc.expected)
			}
		})
	}
}

func TestGlobalImpactCheck(t *testing.T) {
	tests := []struct {
		name         string
		files        []string
		isGlobal     bool
		reasonSubstr string
	}{
		{
			name:         "MODULE.bazel changed",
			files:        []string{"MODULE.bazel"},
			isGlobal:     true,
			reasonSubstr: "root build/toolchain",
		},
		{
			name:         ".bazelrc changed",
			files:        []string{".bazelrc"},
			isGlobal:     true,
			reasonSubstr: "root build/toolchain",
		},
		{
			name:         "root BUILD changed",
			files:        []string{"BUILD"},
			isGlobal:     true,
			reasonSubstr: "root build/toolchain",
		},
		{
			name:         "inert tools/ci script changed",
			files:        []string{"tools/ci/affected-targets.sh"},
			isGlobal:     false,
			reasonSubstr: "",
		},
		{
			name:         "inert tools/pipeline Starlark changed",
			files:        []string{"tools/pipeline/defs.bzl"},
			isGlobal:     false,
			reasonSubstr: "",
		},
		{
			name:         "inert tools/owners changed",
			files:        []string{"tools/owners/main.go"},
			isGlobal:     false,
			reasonSubstr: "",
		},
		{
			name:         "core toolchain directory changed",
			files:        []string{"tools/remote.bazelrc"},
			isGlobal:     true,
			reasonSubstr: "core toolchain directory",
		},
		{
			name:         "application code changed",
			files:        []string{"tabula/web/src/index.tsx"},
			isGlobal:     false,
			reasonSubstr: "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			gotGlobal, reason := CheckGlobalImpact(tc.files)
			if gotGlobal != tc.isGlobal {
				t.Errorf("CheckGlobalImpact(%v) = %v, expected %v", tc.files, gotGlobal, tc.isGlobal)
			}
			if tc.reasonSubstr != "" && !filepath.HasPrefix(reason, tc.reasonSubstr) && len(reason) == 0 {
				t.Errorf("expected reason to contain %q, got %q", tc.reasonSubstr, reason)
			}
		})
	}
}

func TestClassifyPersonaAndOperation(t *testing.T) {
	tests := []struct {
		name              string
		files             []string
		isDocs            bool
		isGlobal          bool
		expectedPersona   Persona
		expectedOperation Operation
	}{
		{
			name:              "docs only",
			files:             []string{"docs/index.md"},
			isDocs:            true,
			isGlobal:          false,
			expectedPersona:   PersonaDocsAuthor,
			expectedOperation: OperationDocsOnly,
		},
		{
			name:              "global config",
			files:             []string{"MODULE.bazel"},
			isDocs:            false,
			isGlobal:          true,
			expectedPersona:   PersonaPlatformAdmin,
			expectedOperation: OperationGlobalConfig,
		},
		{
			name:              "frontend ui feature",
			files:             []string{"tabula/web/app/page.tsx", "packages/design-system/src/Button.tsx"},
			isDocs:            false,
			isGlobal:          false,
			expectedPersona:   PersonaFrontendDev,
			expectedOperation: OperationUIFeature,
		},
		{
			name:              "backend api change",
			files:             []string{"tabula/api/src/server.ts", "tabula/api/src/routes/auth.ts"},
			isDocs:            false,
			isGlobal:          false,
			expectedPersona:   PersonaBackendDev,
			expectedOperation: OperationBackendAPI,
		},
		{
			name:              "database migration",
			files:             []string{"tabula/api/prisma/migrations/20260101_init/migration.sql"},
			isDocs:            false,
			isGlobal:          false,
			expectedPersona:   PersonaBackendDev,
			expectedOperation: OperationDatabaseMigration,
		},
		{
			name:              "dependency lockfile update",
			files:             []string{"pnpm-lock.yaml"},
			isDocs:            false,
			isGlobal:          false,
			expectedPersona:   PersonaBackendDev,
			expectedOperation: OperationDepUpdate,
		},
		{
			name:              "infrastructure pulumi change",
			files:             []string{"infrastructure/pulumi/platform/repo-config/main.go"},
			isDocs:            false,
			isGlobal:          false,
			expectedPersona:   PersonaInfraEng,
			expectedOperation: OperationInfraProvision,
		},
		{
			name:              "multi-discipline full-stack change",
			files:             []string{"tabula/web/app/page.tsx", "tabula/api/src/server.ts"},
			isDocs:            false,
			isGlobal:          false,
			expectedPersona:   PersonaFullStackDev,
			expectedOperation: OperationMultiDiscipline,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			p, op := ClassifyPersonaAndOperation(tc.files, tc.isDocs, tc.isGlobal)
			if p != tc.expectedPersona {
				t.Errorf("Persona = %v, expected %v", p, tc.expectedPersona)
			}
			if op != tc.expectedOperation {
				t.Errorf("Operation = %v, expected %v", op, tc.expectedOperation)
			}
		})
	}
}

func TestResolvePackages(t *testing.T) {
	// Create a temporary mock directory structure
	tmpDir := t.TempDir()
	pkg1 := filepath.Join(tmpDir, "app", "ui")
	pkg2 := filepath.Join(tmpDir, "app", "server", "nested")

	if err := os.MkdirAll(pkg1, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(pkg2, 0o755); err != nil {
		t.Fatal(err)
	}

	if err := os.WriteFile(filepath.Join(tmpDir, "app", "ui", "BUILD"), []byte(""), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmpDir, "app", "server", "BUILD.bazel"), []byte(""), 0o644); err != nil {
		t.Fatal(err)
	}

	files := []string{
		"app/ui/src/App.tsx",
		"app/ui/src/components/Header.tsx",
		"app/server/nested/handler.go",
	}

	packages, err := ResolvePackages(tmpDir, files)
	if err != nil {
		t.Fatalf("ResolvePackages error: %v", err)
	}

	expected := []string{"//app/server:all", "//app/ui:all"}
	if len(packages) != len(expected) {
		t.Fatalf("got %d packages (%v), expected %d (%v)", len(packages), packages, len(expected), expected)
	}
	for i, p := range packages {
		if p != expected[i] {
			t.Errorf("packages[%d] = %s, expected %s", i, p, expected[i])
		}
	}
}

func TestComputePlanHermetic(t *testing.T) {
	tmpDir := t.TempDir()

	// Create mock BUILD files declaring pipeline_unit
	tabulaDir := filepath.Join(tmpDir, "tabula", "web")
	if err := os.MkdirAll(tabulaDir, 0o755); err != nil {
		t.Fatal(err)
	}
	buildContent := `
pipeline_unit(
    name = "tabula-web",
    tier = "L1",
    persona = "frontend",
    runner = "ubuntu-latest",
    test_targets = [":unit_tests"],
)
`
	if err := os.WriteFile(filepath.Join(tabulaDir, "BUILD"), []byte(buildContent), 0o644); err != nil {
		t.Fatal(err)
	}

	runner := &mockQueryRunner{
		rdepsMap: map[string][]string{
			"//tabula/web:all": {"//tabula/web:unit_tests"},
		},
	}

	engine := NewEngine(tmpDir, runner)

	// Case 1: Frontend PR
	plan, err := engine.ComputePlan(context.Background(), []string{"tabula/web/src/App.tsx"}, "main", "HEAD")
	if err != nil {
		t.Fatalf("ComputePlan error: %v", err)
	}

	if plan.Persona != PersonaFrontendDev {
		t.Errorf("Persona = %v, expected %v", plan.Persona, PersonaFrontendDev)
	}
	if plan.Operation != OperationUIFeature {
		t.Errorf("Operation = %v, expected %v", plan.Operation, OperationUIFeature)
	}
	if len(plan.Targets) != 1 || plan.Targets[0] != "//tabula/web:unit_tests" {
		t.Errorf("Targets = %v, expected [//tabula/web:unit_tests]", plan.Targets)
	}
	if len(plan.Matrix) != 1 || plan.Matrix[0].Name != "tabula-web" {
		t.Errorf("Matrix = %v, expected 1 entry for tabula-web", plan.Matrix)
	}

	// Case 2: Docs-only PR
	planDocs, err := engine.ComputePlan(context.Background(), []string{"docs/index.md"}, "main", "HEAD")
	if err != nil {
		t.Fatalf("ComputePlan docs error: %v", err)
	}
	if !planDocs.IsDocsOnly {
		t.Errorf("expected IsDocsOnly=true, got false")
	}
	if len(planDocs.Targets) != 0 {
		t.Errorf("expected 0 targets for docs-only, got %v", planDocs.Targets)
	}

	// Case 3: Fail-closed fallback on query error
	runnerErr := &mockQueryRunner{shouldErr: true}
	engineErr := NewEngine(tmpDir, runnerErr)
	planErr, err := engineErr.ComputePlan(context.Background(), []string{"tabula/web/src/App.tsx"}, "main", "HEAD")
	if err != nil {
		t.Fatalf("expected graceful fail-closed fallback, got error: %v", err)
	}
	if !planErr.IsGlobalImpact {
		t.Errorf("expected IsGlobalImpact=true on query error, got false")
	}
	if len(planErr.Targets) != 1 || planErr.Targets[0] != "//..." {
		t.Errorf("expected Targets=[//...], got %v", planErr.Targets)
	}
}
