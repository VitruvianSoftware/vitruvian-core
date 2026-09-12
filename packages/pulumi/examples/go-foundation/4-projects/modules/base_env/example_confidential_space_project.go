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

package base_env

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	gcpproject "github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-4-projects/modules/single_project"
)

// ConfidentialSpaceResult holds outputs from the Confidential Space project.
type ConfidentialSpaceResult struct {
	ProjectID       pulumi.StringOutput
	ProjectNumber   pulumi.StringOutput
	WorkloadSAEmail pulumi.StringOutput
}

// DeployConfidentialSpaceProject creates a Confidential Space project with a
// workload service account, matching upstream's example_confidential_space_project.tf.
//
// Unlike upstream, which gates this on enable_cloudbuild_deploy, we use a
// dedicated toggle (confidential_space_enabled) to keep the project independent
// of the CI/CD platform choice. The stage root calls this separately from New,
// so it is an exported entrypoint on the module.
//
// Creates:
//   - Project attached to Shared VPC host with VPC-SC perimeter
//   - Workload Service Account for Confidential Space
//   - IAM role bindings for the workload SA
func DeployConfidentialSpaceProject(
	ctx *pulumi.Context,
	args *Args,
) (*ConfidentialSpaceResult, error) {
	// 1. Create the Confidential Space project
	confProject, err := single_project.New(ctx, "bu-conf-space-project", &single_project.Args{
		// "disable" (off), matching upstream 4-projects' project-factory default —
		// not the softer "deprivilege". See base_env.go for the rationale.
		DefaultServiceAccount: "disable",
		ProjectID:             fmt.Sprintf("%s-%s-%s-conf-space", args.ProjectPrefix, args.EnvCode, args.BusinessCode),
		FolderID:              args.FolderID,
		BillingAccount:        args.BillingAccount,
		RandomProjectID:       args.RandomSuffix,
		Labels:                args.Labels("sample-instance", "svpc"),
		Budget:                args.Budget,
		ActivateApis: []string{
			"accesscontextmanager.googleapis.com",
			"artifactregistry.googleapis.com",
			"iamcredentials.googleapis.com",
			"compute.googleapis.com",
			"confidentialcomputing.googleapis.com",
			"cloudkms.googleapis.com",
			"billingbudgets.googleapis.com",
			// iam: the workload SA below is created IN this project — the IAM API
			// must be enabled (and propagated, via ApisReady) for that create.
			"iam.googleapis.com",
		},
		ApiPropagationSeconds: args.ApiPropagationSeconds,
	})
	if err != nil {
		return nil, err
	}

	// 2. Attach as a Shared VPC service project. DependsOn(ApisReady): the attach
	// needs compute.googleapis.com usable on the service project — wait out the
	// cold-deploy API propagation gate.
	if _, err := compute.NewSharedVPCServiceProject(ctx, "conf-space-svpc-attachment", &compute.SharedVPCServiceProjectArgs{
		HostProject:    args.NetworkProjectID,
		ServiceProject: confProject.Project.Project.ProjectId,
	}, pulumi.DependsOn([]pulumi.Resource{confProject.Project.ApisReady})); err != nil {
		return nil, err
	}

	// 3. VPC-SC Perimeter attachment
	if args.EnforceVpcSc {
		_, err := accesscontextmanager.NewServicePerimeterResource(ctx, "conf-space-vpcsc-attach", &accesscontextmanager.ServicePerimeterResourceArgs{
			PerimeterName: args.PerimeterName,
			Resource: confProject.Project.Project.Number.ApplyT(func(n string) string {
				return fmt.Sprintf("projects/%s", n)
			}).(pulumi.StringOutput),
		})
		if err != nil {
			return nil, err
		}
	} else {
		_, err := accesscontextmanager.NewServicePerimeterDryRunResource(ctx, "conf-space-vpcsc-attach-dry-run", &accesscontextmanager.ServicePerimeterDryRunResourceArgs{
			PerimeterName: args.PerimeterName,
			Resource: confProject.Project.Project.Number.ApplyT(func(n string) string {
				return fmt.Sprintf("projects/%s", n)
			}).(pulumi.StringOutput),
		})
		if err != nil {
			return nil, err
		}
	}

	// 4. Workload Service Account for Confidential Space. DependsOn(ApisReady):
	// the iam API (in ActivateApis above) must be usable before the SA create on
	// a cold deploy.
	workloadSA, err := serviceaccount.NewAccount(ctx, "conf-space-workload-sa", &serviceaccount.AccountArgs{
		AccountId:   pulumi.String("confidential-space-workload-sa"),
		DisplayName: pulumi.String("Workload Service Account for confidential space"),
		Project:     confProject.Project.Project.ProjectId,
	}, pulumi.DependsOn([]pulumi.Resource{confProject.Project.ApisReady}))
	if err != nil {
		return nil, err
	}

	// 5. IAM role bindings for the workload SA (matching upstream iam_roles local)
	workloadRoles := []string{
		"roles/iam.serviceAccountUser",
		"roles/confidentialcomputing.workloadUser",
		"roles/iam.workloadIdentityPoolAdmin",
		"roles/storage.admin",
		"roles/logging.logWriter",
	}
	for _, role := range workloadRoles {
		_, err := gcpproject.NewIAMMember(ctx, fmt.Sprintf("conf-space-sa-%s", role), &gcpproject.IAMMemberArgs{
			Project: confProject.Project.Project.ProjectId,
			Role:    pulumi.String(role),
			Member:  pulumi.Sprintf("serviceAccount:%s", workloadSA.Email),
		})
		if err != nil {
			return nil, err
		}
	}

	return &ConfidentialSpaceResult{
		ProjectID:       confProject.ProjectID,
		ProjectNumber:   confProject.ProjectNumber,
		WorkloadSAEmail: workloadSA.Email,
	}, nil
}
