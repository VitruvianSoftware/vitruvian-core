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
	OSSFloatingProjectID         pulumi.StringOutput
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
	result.OSSFloatingProjectID = emptyStr
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
			DefaultServiceAccount: "deprivilege",
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

		// CMEK Storage — KMS keyring + encrypted GCS bucket on the SVPC project
		if cfg.CMEKEnabled {
			cmekResult, err := deployCMEKStorage(ctx, cfg, svpcProject, kmsProjectID)
			if err != nil {
				return nil, err
			}
			result.CMEKBucket = &cmekResult.BucketName
			result.CMEKKeyring = &cmekResult.KeyringName
		}
	}

	// ========================================================================
	// 2. Floating Project (not attached to any VPC, toggle-gated)
	// ========================================================================
	if cfg.FloatingProjectEnabled {
		floatingProject, err := project.NewProject(ctx, "bu-floating-project", &project.ProjectArgs{
			DefaultServiceAccount: "deprivilege",
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
	// 2b. OSS Floating Project (not attached to any VPC, toggle-gated)
	// A second floating project in the same BU folder, dedicated to hosting the
	// monorepo's open-source applications (e.g. oauth-user-inspector) on
	// org-managed infrastructure instead of a personal-account project. Distinct
	// from the -sample-floating reference project above.
	// ========================================================================
	if cfg.OSSFloatingProjectEnabled {
		ossFloatingProject, err := project.NewProject(ctx, "bu-oss-floating-project", &project.ProjectArgs{
			DefaultServiceAccount: "deprivilege",
			ProjectID:             pulumi.String(fmt.Sprintf("%s-%s-%s-oss-floating", cfg.ProjectPrefix, cfg.EnvCode, cfg.BusinessCode)),
			Name:                  pulumi.String(fmt.Sprintf("%s-%s-%s-oss-floating", cfg.ProjectPrefix, cfg.EnvCode, cfg.BusinessCode)),
			FolderID:              folderID,
			BillingAccount:        pulumi.String(cfg.BillingAccount),
			RandomProjectID:       cfg.RandomSuffix,
			Labels:                projectLabels(cfg, "oss-application", "none"),
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
		result.OSSFloatingProjectID = ossFloatingProject.Project.ProjectId
	}

	// ========================================================================
	// 3. Peering Project — full VPC, subnet, DNS, peering, firewall (toggle-gated)
	// ========================================================================
	if cfg.PeeringProjectEnabled {
		peeringProject, err := project.NewProject(ctx, "bu-peering-project", &project.ProjectArgs{
			DefaultServiceAccount: "deprivilege",
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

// deployInfraPipelineProject creates the infrastructure pipeline project under
// the common folder. This project hosts the CI/CD pipeline for deploying
// application infrastructure (Stage 5).
func deployInfraPipelineProject(ctx *pulumi.Context, cfg *ProjectsConfig, commonFolderID pulumi.StringOutput) (pulumi.StringOutput, error) {
	infraProject, err := project.NewProject(ctx, "infra-pipeline-project", &project.ProjectArgs{
		ProjectID:       pulumi.String(fmt.Sprintf("%s-c-%s-infra-pipeline", cfg.ProjectPrefix, cfg.BusinessCode)),
		Name:            pulumi.String(fmt.Sprintf("%s-c-%s-infra-pipeline", cfg.ProjectPrefix, cfg.BusinessCode)),
		FolderID:        commonFolderID,
		BillingAccount:  pulumi.String(cfg.BillingAccount),
		RandomProjectID: cfg.RandomSuffix,
		Labels:          projectLabels(cfg, "app-infra-pipelines", "none"),
		Budget:          budgetConfig(cfg),
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
