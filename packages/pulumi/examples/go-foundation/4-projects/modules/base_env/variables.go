/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

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
	SVPCProjectEnabled     bool
	FloatingProjectEnabled bool
	PeeringProjectEnabled  bool

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
