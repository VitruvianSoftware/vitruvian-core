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

package main

import (
	"fmt"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

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

// budgetConfig returns the standard budget configuration used for every
// project, matching the upstream TF project_budget variable.
func budgetConfig(cfg *ProjectsConfig) *project.BudgetConfig {
	return &project.BudgetConfig{
		Amount:             cfg.BudgetAmount,
		AlertSpentPercents: cfg.BudgetAlertPercents,
		AlertSpendBasis:    cfg.BudgetSpendBasis,
	}
}

// deployBusinessUnitProjects creates three project types per BU/env, matching
// the Terraform foundation's project factory pattern:
//   - SVPC-attached: connected to the Shared VPC host project w/ VPC-SC
//   - Floating: standalone project, not attached to any VPC
//   - Peering: project with its own VPC peered to the host network
func deployBusinessUnitProjects(ctx *pulumi.Context, cfg *ProjectsConfig, folderID, networkProjectID, perimeterName, kmsProjectID, acmPolicyID pulumi.StringOutput) (*BUProjects, error) {
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
	if cfg.SVPCProjectEnabled {
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
		}

		svpcProject, err := project.NewProject(ctx, "bu-svpc-project", &project.ProjectArgs{
			// "disable" turns the project's default compute SA OFF, matching upstream
			// 4-projects (which relies on project-factory's default
			// default_service_account = "disable"). "deprivilege" — the softer posture
			// we shipped first — would leave the SA active, only de-editored.
			DefaultServiceAccount: "disable",
			ProjectID:             pulumi.String(fmt.Sprintf("%s-%s-%s-sample-svpc", cfg.ProjectPrefix, cfg.EnvCode, cfg.BusinessCode)),
			Name:                  pulumi.String(fmt.Sprintf("%s-%s-%s-sample-svpc", cfg.ProjectPrefix, cfg.EnvCode, cfg.BusinessCode)),
			FolderID:              folderID,
			BillingAccount:        pulumi.String(cfg.BillingAccount),
			RandomProjectID:       cfg.RandomSuffix,
			Labels:                projectLabels(cfg, "sample-application", "svpc"),
			Budget:                budgetConfig(cfg),
			ActivateApis:          svpcApis,
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

		// Attach as a Shared VPC service project
		if _, err := compute.NewSharedVPCServiceProject(ctx, "svpc-attachment", &compute.SharedVPCServiceProjectArgs{
			HostProject:    networkProjectID,
			ServiceProject: svpcProject.Project.ProjectId,
		}); err != nil {
			return nil, err
		}

		// VPC-SC Perimeter attachment — attach the SVPC project to the perimeter
		// matching upstream's vpc_service_control_attach_enabled behavior.
		if cfg.EnforceVpcSc {
			_, err := accesscontextmanager.NewServicePerimeterResource(ctx, "svpc-vpcsc-attach", &accesscontextmanager.ServicePerimeterResourceArgs{
				PerimeterName: perimeterName,
				Resource: svpcProject.Project.Number.ApplyT(func(n string) string {
					return fmt.Sprintf("projects/%s", n)
				}).(pulumi.StringOutput),
			})
			if err != nil {
				return nil, err
			}
		} else {
			_, err := accesscontextmanager.NewServicePerimeterDryRunResource(ctx, "svpc-vpcsc-attach-dry-run", &accesscontextmanager.ServicePerimeterDryRunResourceArgs{
				PerimeterName: perimeterName,
				Resource: svpcProject.Project.Number.ApplyT(func(n string) string {
					return fmt.Sprintf("projects/%s", n)
				}).(pulumi.StringOutput),
			})
			if err != nil {
				return nil, err
			}
		}

		result.SVPCProjectID = svpcProject.Project.ProjectId
		result.SVPCProjectNumber = svpcProject.Project.Number

		// CMEK Storage — KMS keyring + crypto key in the env KMS project, encrypted
		// GCS bucket on the SVPC project.
		if cfg.CMEKEnabled {
			cmekResult, err := deployCMEKStorage(ctx, cfg, svpcProject, kmsProjectID)
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
	if cfg.FloatingProjectEnabled {
		floatingProject, err := project.NewProject(ctx, "bu-floating-project", &project.ProjectArgs{
			DefaultServiceAccount: "disable", // upstream default; see the svpc project above
			ProjectID:             pulumi.String(fmt.Sprintf("%s-%s-%s-sample-floating", cfg.ProjectPrefix, cfg.EnvCode, cfg.BusinessCode)),
			Name:                  pulumi.String(fmt.Sprintf("%s-%s-%s-sample-floating", cfg.ProjectPrefix, cfg.EnvCode, cfg.BusinessCode)),
			FolderID:              folderID,
			BillingAccount:        pulumi.String(cfg.BillingAccount),
			RandomProjectID:       cfg.RandomSuffix,
			Labels:                projectLabels(cfg, "sample-application", "none"),
			Budget:                budgetConfig(cfg),
			ActivateApis: []string{
				"compute.googleapis.com",
				"container.googleapis.com",
				"run.googleapis.com",
				"artifactregistry.googleapis.com",
				"billingbudgets.googleapis.com",
				"logging.googleapis.com",
			},
		})
		if err != nil {
			return nil, err
		}
		result.FloatingProjectID = floatingProject.Project.ProjectId
	}

	// ========================================================================
	// 3. Peering Project — full VPC, subnet, DNS, peering, firewall (toggle-gated)
	// ========================================================================
	if cfg.PeeringProjectEnabled {
		peeringProject, err := project.NewProject(ctx, "bu-peering-project", &project.ProjectArgs{
			DefaultServiceAccount: "disable", // upstream default; see the svpc project above
			ProjectID:             pulumi.String(fmt.Sprintf("%s-%s-%s-sample-peering", cfg.ProjectPrefix, cfg.EnvCode, cfg.BusinessCode)),
			Name:                  pulumi.String(fmt.Sprintf("%s-%s-%s-sample-peering", cfg.ProjectPrefix, cfg.EnvCode, cfg.BusinessCode)),
			FolderID:              folderID,
			BillingAccount:        pulumi.String(cfg.BillingAccount),
			RandomProjectID:       cfg.RandomSuffix,
			Labels:                projectLabels(cfg, "sample-peering", "none"),
			Budget:                budgetConfig(cfg),
			ActivateApis: []string{
				"compute.googleapis.com",
				"dns.googleapis.com",
				"billingbudgets.googleapis.com",
				"logging.googleapis.com",
			},
		})
		if err != nil {
			return nil, err
		}
		result.PeeringProjectID = peeringProject.Project.ProjectId

		// Deploy peering network infrastructure (VPC, subnet, DNS, peering, firewall)
		if cfg.PeeringEnabled {
			peeringResult, err := deployPeeringNetwork(ctx, cfg, peeringProject, networkProjectID)
			if err != nil {
				return nil, err
			}
			result.PeeringNetworkSelfLink = peeringResult.NetworkSelfLink
			result.PeeringSubnetSelfLink = peeringResult.SubnetSelfLink
			result.IAPFirewallTags = peeringResult.IAPFirewallTags
		}
	}

	// Populate TF-parity outputs
	// TODO(shared-VPC enablement): upstream's `subnets_self_links` output is the
	// SHARED-VPC HOST's subnets (local.subnets_self_links, from the 3-networks
	// remote state), consumed by 5-app-infra to place service-project resources.
	// We currently export the PEERING project's subnet here — the wrong network
	// (the peering subnet already has its own `peering_subnetwork_self_link`
	// export). When shared-VPC projects are enabled, read `subnets_self_links` from
	// the gcp-networks stack (it exports exactly that) and export that instead.
	if cfg.PeeringProjectEnabled && cfg.PeeringEnabled {
		result.SubnetsSelfLinks = pulumi.StringArray{result.PeeringSubnetSelfLink}.ToStringArrayOutput()
		result.PeeringComplete = pulumi.Bool(true).ToBoolOutput()
	} else {
		result.SubnetsSelfLinks = pulumi.ToStringArray([]string{}).ToStringArrayOutput()
		result.PeeringComplete = pulumi.Bool(false).ToBoolOutput()
	}
	result.VPCSCPerimeterName = perimeterName
	result.AccessContextManagerPolicyID = acmPolicyID

	return result, nil
}

// deployInfraPipelineProject creates the shared infrastructure-pipeline project
// under the COMMON folder. This project hosts the CI/CD pipeline for deploying
// application infrastructure (Stage 5).
//
// ⚠️ ONCE-PER-BU, NOT ONCE-PER-ENV. Upstream 4-projects creates this project a
// single time in the `shared` workspace (environment=common). Our foundation is
// split into per-env stacks (dev/nonprod/prod), so `infra_pipeline_enabled` MUST
// be true in EXACTLY ONE env's config — enabling it in more than one mints
// duplicate `prj-c-<bu>-infra-pipeline-*` projects (the random suffix dodges the
// ID collision but not the duplication). (A cleaner long-term shape is a dedicated
// common/shared stack; deferred until Stage-5 CI/CD.)
//
// NOTE (deploy-SA IAM — deliberately NOT here in our model): upstream
// `single_project` seeds the pipeline service accounts with `sa_roles` on each
// app project, `roles/compute.networkViewer` on the BU folder, and
// `roles/compute.networkUser` on the shared-VPC subnets — for its VM + Cloud-Build
// deploy model. We don't replicate that here: our stage-5 apps are serverless
// (Cloud Run) on FLOATING projects, deployed from GitHub Actions via Workload
// Identity Federation, so deploy permissions live in each APP's own deploy-identity
// stack — e.g. infrastructure/pulumi/apps/oauth-user-inspector-deploy-identity,
// which grants its deploy SA run.admin/artifactregistry.admin/iam.serviceAccountUser/…
// on the target project plus a WIF impersonation binding. This infra-pipeline
// project is NOT in that deploy path (nothing references it); it's a placeholder
// carried over from the upstream shape. When stage-5 moves an app onto the org's
// oss-floating projects, extend that app's deploy-identity stack to the target
// project per env, following the existing pattern — do NOT add upstream's
// Cloud-Build / shared-VPC pipeline-SA roles to this project.
func deployInfraPipelineProject(ctx *pulumi.Context, cfg *ProjectsConfig, commonFolderID pulumi.StringOutput) (pulumi.StringOutput, error) {
	infraProject, err := project.NewProject(ctx, "infra-pipeline-project", &project.ProjectArgs{
		ProjectID:       pulumi.String(fmt.Sprintf("%s-c-%s-infra-pipeline", cfg.ProjectPrefix, cfg.BusinessCode)),
		Name:            pulumi.String(fmt.Sprintf("%s-c-%s-infra-pipeline", cfg.ProjectPrefix, cfg.BusinessCode)),
		FolderID:        commonFolderID,
		BillingAccount:  pulumi.String(cfg.BillingAccount),
		RandomProjectID: cfg.RandomSuffix,
		// COMMON-folder project → environment=common/env_code=c labels + a raw
		// application_name, matching upstream (the per-env `projectLabels` would
		// mislabel it with this stack's dev/nonprod/prod identity).
		Labels: commonProjectLabels(cfg, "app-infra-pipelines"),
		Budget: budgetConfig(cfg),
		ActivateApis: []string{
			"cloudbuild.googleapis.com",
			"cloudkms.googleapis.com",
			"iam.googleapis.com",
			"artifactregistry.googleapis.com",
			"cloudresourcemanager.googleapis.com",
			"billingbudgets.googleapis.com",
			"confidentialcomputing.googleapis.com",
		},
	})
	if err != nil {
		return pulumi.StringOutput{}, err
	}

	return infraProject.Project.ProjectId, nil
}
