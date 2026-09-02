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

// SchemaVersion defines the current JSON schema contract version.
const SchemaVersion = 1

// Persona defines the developer persona initiating the changeset.
type Persona string

const (
	PersonaFrontendDev     Persona = "frontend-dev"
	PersonaBackendDev      Persona = "backend-dev"
	PersonaInfraEng        Persona = "infra-eng"
	PersonaPlatformAdmin   Persona = "platform-admin"
	PersonaDocsAuthor      Persona = "docs-author"
	PersonaSecurityAuditor Persona = "security-auditor"
	PersonaFullStackDev    Persona = "fullstack-dev"
)

// Operation defines the semantic operation represented by the changeset.
type Operation string

const (
	OperationDocsOnly          Operation = "docs-only"
	OperationUIFeature         Operation = "ui-feature"
	OperationBackendAPI        Operation = "backend-api"
	OperationDatabaseMigration Operation = "database-migration"
	OperationInfraProvision    Operation = "infra-provision"
	OperationDepUpdate         Operation = "dep-update"
	OperationGlobalConfig      Operation = "global-config"
	OperationMultiDiscipline   Operation = "multi-discipline"
)

// ExecutionTier represents the CI tier for target execution.
type ExecutionTier string

const (
	TierL0 ExecutionTier = "L0" // Local / IDE inner loop
	TierL1 ExecutionTier = "L1" // Graph-scoped presubmit
	TierL2 ExecutionTier = "L2" // Merge queue verification
	TierL3 ExecutionTier = "L3" // Async soak & postsubmit
)

// MatrixEntry represents one execution unit for GitHub Actions dynamic matrix fan-out.
type MatrixEntry struct {
	Name             string            `json:"name"`
	Package          string            `json:"package"`
	Runner           string            `json:"runner"` // "ubuntu-latest" or "macos-latest"
	Tier             ExecutionTier     `json:"tier"`
	Persona          Persona           `json:"persona"`
	Targets          []string          `json:"targets,omitempty"`
	TestTargets      string            `json:"test_targets,omitempty"`
	TargetCount      int               `json:"target_count"`
	TimeoutMinutes   int               `json:"timeout_minutes,omitempty"`
	ConcurrencyGroup string            `json:"concurrency_group,omitempty"`
	Env              map[string]string `json:"env,omitempty"`
	Needs            []string          `json:"needs,omitempty"`
	IsRequired       bool              `json:"is_required"`
}

// Plan represents the complete output of the change detection engine.
type Plan struct {
	SchemaVersion    int           `json:"schema_version"`
	BaseRev          string        `json:"base_rev"`
	HeadRev          string        `json:"head_rev"`
	DurationMs       int64         `json:"duration_ms"`
	ChangedFiles     []string      `json:"changed_files"`
	AffectedPackages []string      `json:"affected_packages"`
	Persona          Persona       `json:"persona"`
	Operation        Operation     `json:"operation"`
	IsDocsOnly       bool          `json:"is_docs_only"`
	IsGlobalImpact   bool          `json:"is_global_impact"`
	SweepReason      string        `json:"sweep_reason,omitempty"`
	Targets          []string      `json:"targets"`
	TargetCount      int           `json:"target_count"`
	Matrix           []MatrixEntry `json:"matrix"`
}
