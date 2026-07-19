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

// Module inputs — the Pulumi analogue of upstream
// 4-projects/modules/base_env/variables.tf.

package base_env

import (
	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Args are the inputs to the base_env module. It carries the subset of the
// stage's ProjectsConfig that the moved code needs (kept in the root package for
// its config loader + tests), plus the cross-stage StackReference outputs.
//
// Labels and Budget are supplied as a builder closure and a precomputed value
// rather than re-derived here, so the tested root helpers (projectLabels /
// budgetConfig) remain the single source of truth and label/budget behaviour is
// preserved exactly.
type Args struct {
	// Project id components (upstream project_prefix / environment_code / business_code).
	ProjectPrefix  string
	EnvCode        string
	BusinessCode   string
	BillingAccount string
	RandomSuffix   bool

	// Project-type enablement toggles.
	SVPCProjectEnabled        bool
	FloatingProjectEnabled    bool
	OSSFloatingProjectEnabled bool
	PeeringProjectEnabled     bool

	// Feature toggles.
	EnforceVpcSc   bool
	CMEKEnabled    bool
	PeeringEnabled bool

	// ApiPropagationSeconds is forwarded to every single_project call so each
	// project's ApisReady gate (and gated project id) reflects the stage-level
	// api_propagation_seconds config. 0 disables the wait.
	ApiPropagationSeconds int

	// Peering network configuration.
	SubnetRegion           string
	SubnetIPRange          string
	PeeringIAPFWEnabled    bool
	FirewallEnableLogging  bool
	WindowsActivation      bool
	OptionalFWRulesEnabled bool

	// CMEK configuration.
	KeyringName         string
	KMSLocation         string
	KeyName             string
	KeyRotationPeriod   string
	GCSBucketPrefix     string
	GCSLocation         string
	GCSPlacementRegions []string

	// Cross-stage StackReference outputs.
	FolderID         pulumi.StringOutput
	NetworkProjectID pulumi.StringOutput
	PerimeterName    pulumi.StringOutput
	KMSProjectID     pulumi.StringOutput
	ACMPolicyID      pulumi.StringOutput

	// Labels builds the standard project label map for a given (suffix, vpc),
	// delegating to the root's tested projectLabels. Budget is the standard
	// per-project budget (budgetConfig), identical across every project.
	Labels func(suffix, vpc string) pulumi.StringMap
	Budget *project.BudgetConfig
}
