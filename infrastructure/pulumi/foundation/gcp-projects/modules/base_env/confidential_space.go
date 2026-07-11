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

package base_env

import (
	"fmt"

	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/accesscontextmanager"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/compute"
	gcpproject "github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/projects"
	"github.com/pulumi/pulumi-gcp/sdk/v9/go/gcp/serviceaccount"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-projects/modules/single_project"
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
		},
	})
	if err != nil {
		return nil, err
	}

	// 2. Attach as a Shared VPC service project
	if _, err := compute.NewSharedVPCServiceProject(ctx, "conf-space-svpc-attachment", &compute.SharedVPCServiceProjectArgs{
		HostProject:    args.NetworkProjectID,
		ServiceProject: confProject.Project.Project.ProjectId,
	}); err != nil {
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

	// 4. Workload Service Account for Confidential Space
	workloadSA, err := serviceaccount.NewAccount(ctx, "conf-space-workload-sa", &serviceaccount.AccountArgs{
		AccountId:   pulumi.String("confidential-space-workload-sa"),
		DisplayName: pulumi.String("Workload Service Account for confidential space"),
		Project:     confProject.Project.Project.ProjectId,
	})
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
