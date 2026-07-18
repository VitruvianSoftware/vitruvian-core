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

// Package base_env is the per-environment project orchestrator, the Pulumi port
// of upstream terraform-example-foundation 4-projects/modules/base_env. It
// creates the business-unit project set (SVPC-attached, floating, peering) plus
// their attached infrastructure (Shared-VPC attach, VPC-SC perimeter attach,
// CMEK storage, peering network + firewall) and — via a separate exported
// entrypoint — the Confidential Space project.
//
// Each project is created through single_project.New, whose logical names are
// passed through unchanged so this is a pure structural extraction of the former
// inline root code with a byte-identical resource graph.
package base_env

import (
	"fmt"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-4-projects/modules/single_project"
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

// BUProjects holds outputs from business unit project deployment.
type BUProjects struct {
	SVPCProjectID                pulumi.StringOutput
	SVPCProjectNumber            pulumi.StringOutput
	FloatingProjectID            pulumi.StringOutput
	PeeringProjectID             pulumi.StringOutput
	PeeringNetworkSelfLink       pulumi.StringOutput
	PeeringSubnetSelfLink        pulumi.StringOutput
	IAPFirewallTags              pulumi.MapOutput
	CMEKBucket                   *pulumi.StringOutput
	CMEKKeyring                  *pulumi.StringOutput
	CMEKKeys                     *pulumi.StringArrayOutput
	ConfSpaceProjectID           *pulumi.StringOutput
	ConfSpaceProjectNumber       *pulumi.StringOutput
	ConfSpaceWorkloadSA          *pulumi.StringOutput
	SubnetsSelfLinks             pulumi.StringArrayOutput
	VPCSCPerimeterName           pulumi.StringOutput
	PeeringComplete              pulumi.BoolOutput
	AccessContextManagerPolicyID pulumi.StringOutput
	RestrictedEnabledApis        []string
}

// New creates three project types per BU/env, matching the Terraform
// foundation's project factory pattern:
//   - SVPC-attached: connected to the Shared VPC host project w/ VPC-SC
//   - Floating: standalone project, not attached to any VPC
//   - Peering: project with its own VPC peered to the host network
func New(ctx *pulumi.Context, args *Args) (*BUProjects, error) {
	result := &BUProjects{}

	// Default every StringOutput to an empty string so exports remain well-typed
	// when a project type is disabled.
	emptyStr := pulumi.String("").ToStringOutput()
	result.SVPCProjectID = emptyStr
	result.SVPCProjectNumber = emptyStr
	result.FloatingProjectID = emptyStr
	result.PeeringProjectID = emptyStr
	result.PeeringNetworkSelfLink = emptyStr
	result.PeeringSubnetSelfLink = emptyStr
	result.IAPFirewallTags = pulumi.Map{}.ToMapOutput()

	// ========================================================================
	// 1. SVPC-attached Project (toggle-gated)
	// This project is attached as a service project to the environment's
	// Shared VPC host, enabling shared network resource access. CMEK storage,
	// the Shared-VPC attachment, and the VPC-SC perimeter attach all hang off
	// this project, so they live inside the same gate.
	// ========================================================================
	if args.SVPCProjectEnabled {
		// NOTE: this API set is intentionally BROADER than upstream 4-projects
		// (which enables only accesscontextmanager on the svpc project, dns on
		// peering, and nothing on floating). We pre-enable the common workload APIs
		// (compute/container/run/artifactregistry/logging) so applications deployed
		// into these projects don't each have to turn them on; this also widens the
		// `restricted_enabled_apis` export. The floating/peering blocks below share
		// this posture.
		svpcApis := []string{
			"compute.googleapis.com",
			"container.googleapis.com",
			"run.googleapis.com",
			"artifactregistry.googleapis.com",
			"billingbudgets.googleapis.com",
			"logging.googleapis.com",
			"accesscontextmanager.googleapis.com",
			// storage: the CMEK bucket (deployCMEKStorage) lands on this project and
			// its GCS service agent is looked up via the API — enable it explicitly
			// so the cold-deploy path doesn't depend on implicit activation.
			"storage.googleapis.com",
		}

		svpcProject, err := single_project.New(ctx, "bu-svpc-project", &single_project.Args{
			// "disable" turns the project's default compute SA OFF, matching upstream
			// 4-projects (which relies on project-factory's default
			// default_service_account = "disable"). "deprivilege" — the softer posture
			// we shipped first — would leave the SA active, only de-editored.
			DefaultServiceAccount: "disable",
			ProjectID:             fmt.Sprintf("%s-%s-%s-sample-svpc", args.ProjectPrefix, args.EnvCode, args.BusinessCode),
			FolderID:              args.FolderID,
			BillingAccount:        args.BillingAccount,
			RandomProjectID:       args.RandomSuffix,
			Labels:                args.Labels("sample-application", "svpc"),
			Budget:                args.Budget,
			ActivateApis:          svpcApis,
			ApiPropagationSeconds: args.ApiPropagationSeconds,
		})
		if err != nil {
			return nil, err
		}

		result.RestrictedEnabledApis = svpcApis

		// TODO(vpc-sc enablement): upstream project-factory serializes the perimeter
		// attach BEFORE the shared-VPC attach and waits vpc_service_control_sleep_
		// duration = "60s" between them, so the project is inside the perimeter
		// before it joins the shared VPC. Here the shared-VPC attach (below) and the
		// VPC-SC attach (further down) both hang only off the project and race. When
		// SVPC/VPC-SC are enabled for real, order them: DependsOn(perimeter-attach)
		// + a 60s propagation gate on this attach (the dependsOn+propagation-wait
		// pattern used elsewhere in the foundation).

		// Attach as a Shared VPC service project. DependsOn(ApisReady): the attach
		// requires compute.googleapis.com to be usable on the service project — on
		// a cold deploy it must wait out the API propagation gate.
		if _, err := compute.NewSharedVPCServiceProject(ctx, "svpc-attachment", &compute.SharedVPCServiceProjectArgs{
			HostProject:    args.NetworkProjectID,
			ServiceProject: svpcProject.Project.Project.ProjectId,
		}, pulumi.DependsOn([]pulumi.Resource{svpcProject.Project.ApisReady})); err != nil {
			return nil, err
		}

		// VPC-SC Perimeter attachment — attach the SVPC project to the perimeter
		// matching upstream's vpc_service_control_attach_enabled behavior.
		if args.EnforceVpcSc {
			_, err := accesscontextmanager.NewServicePerimeterResource(ctx, "svpc-vpcsc-attach", &accesscontextmanager.ServicePerimeterResourceArgs{
				PerimeterName: args.PerimeterName,
				Resource: svpcProject.Project.Project.Number.ApplyT(func(n string) string {
					return fmt.Sprintf("projects/%s", n)
				}).(pulumi.StringOutput),
			})
			if err != nil {
				return nil, err
			}
		} else {
			_, err := accesscontextmanager.NewServicePerimeterDryRunResource(ctx, "svpc-vpcsc-attach-dry-run", &accesscontextmanager.ServicePerimeterDryRunResourceArgs{
				PerimeterName: args.PerimeterName,
				Resource: svpcProject.Project.Project.Number.ApplyT(func(n string) string {
					return fmt.Sprintf("projects/%s", n)
				}).(pulumi.StringOutput),
			})
			if err != nil {
				return nil, err
			}
		}

		result.SVPCProjectID = svpcProject.ProjectID
		result.SVPCProjectNumber = svpcProject.ProjectNumber

		// CMEK Storage — KMS keyring + crypto key in the env KMS project, encrypted
		// GCS bucket on the SVPC project.
		if args.CMEKEnabled {
			cmekResult, err := deployCMEKStorage(ctx, args, svpcProject.Project, args.KMSProjectID)
			if err != nil {
				return nil, err
			}
			result.CMEKBucket = &cmekResult.BucketName
			result.CMEKKeyring = &cmekResult.KeyringName
			// Populate CMEKKeys so main.go's `keys` export is the crypto-key list
			// (upstream `keys(module.kms.keys)`), not the empty stub it was before.
			result.CMEKKeys = &cmekResult.Keys
		}
	}

	// ========================================================================
	// 2. Floating Project (not attached to any VPC, toggle-gated)
	// ========================================================================
	if args.FloatingProjectEnabled {
		floatingProject, err := single_project.New(ctx, "bu-floating-project", &single_project.Args{
			DefaultServiceAccount: "disable", // upstream default; see the svpc project above
			ProjectID:             fmt.Sprintf("%s-%s-%s-sample-floating", args.ProjectPrefix, args.EnvCode, args.BusinessCode),
			FolderID:              args.FolderID,
			BillingAccount:        args.BillingAccount,
			RandomProjectID:       args.RandomSuffix,
			Labels:                args.Labels("sample-application", "none"),
			Budget:                args.Budget,
			ActivateApis: []string{
				"compute.googleapis.com",
				"container.googleapis.com",
				"run.googleapis.com",
				"artifactregistry.googleapis.com",
				"billingbudgets.googleapis.com",
				"logging.googleapis.com",
			},
			ApiPropagationSeconds: args.ApiPropagationSeconds,
		})
		if err != nil {
			return nil, err
		}
		result.FloatingProjectID = floatingProject.ProjectID
	}

	// ========================================================================
	// 3. Peering Project — full VPC, subnet, DNS, peering, firewall (toggle-gated)
	// ========================================================================
	if args.PeeringProjectEnabled {
		peeringProject, err := single_project.New(ctx, "bu-peering-project", &single_project.Args{
			DefaultServiceAccount: "disable", // upstream default; see the svpc project above
			ProjectID:             fmt.Sprintf("%s-%s-%s-sample-peering", args.ProjectPrefix, args.EnvCode, args.BusinessCode),
			FolderID:              args.FolderID,
			BillingAccount:        args.BillingAccount,
			RandomProjectID:       args.RandomSuffix,
			Labels:                args.Labels("sample-peering", "none"),
			Budget:                args.Budget,
			ActivateApis: []string{
				"compute.googleapis.com",
				"dns.googleapis.com",
				"billingbudgets.googleapis.com",
				"logging.googleapis.com",
			},
			ApiPropagationSeconds: args.ApiPropagationSeconds,
		})
		if err != nil {
			return nil, err
		}
		result.PeeringProjectID = peeringProject.ProjectID

		// Deploy peering network infrastructure (VPC, subnet, DNS, peering, firewall)
		if args.PeeringEnabled {
			peeringResult, err := deployPeeringNetwork(ctx, args, peeringProject, args.NetworkProjectID)
			if err != nil {
				return nil, err
			}
			result.PeeringNetworkSelfLink = peeringResult.NetworkSelfLink
			result.PeeringSubnetSelfLink = peeringResult.SubnetSelfLink
			result.IAPFirewallTags = peeringResult.IAPFirewallTags
		}
	}

	// Populate TF-parity outputs
	//
	// TODO(shared-VPC enablement): upstream's `subnets_self_links` output is the
	// SHARED-VPC HOST's subnets (local.subnets_self_links, from the 3-networks
	// remote state), consumed by 5-app-infra to place service-project resources.
	// We currently export the PEERING project's subnet here — the wrong network
	// (the peering subnet already has its own `peering_subnetwork_self_link`
	// export). When shared-VPC projects are enabled, read `subnets_self_links` from
	// the gcp-networks stack (it exports exactly that) and export that instead.
	if args.PeeringProjectEnabled && args.PeeringEnabled {
		result.SubnetsSelfLinks = pulumi.StringArray{result.PeeringSubnetSelfLink}.ToStringArrayOutput()
		result.PeeringComplete = pulumi.Bool(true).ToBoolOutput()
	} else {
		result.SubnetsSelfLinks = pulumi.ToStringArray([]string{}).ToStringArrayOutput()
		result.PeeringComplete = pulumi.Bool(false).ToBoolOutput()
	}
	result.VPCSCPerimeterName = args.PerimeterName
	result.AccessContextManagerPolicyID = args.ACMPolicyID

	return result, nil
}
