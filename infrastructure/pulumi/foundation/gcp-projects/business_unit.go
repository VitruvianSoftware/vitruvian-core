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
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"foundation-projects/modules/base_env"
)

// The business-unit project set + its attached infrastructure (CMEK, peering,
// confidential space) now lives in the base_env module. These aliases keep the
// former root-package type names resolvable — for the stage's config_test.go and
// any other root references — without duplicating the definitions.
type (
	BUProjects              = base_env.BUProjects
	CMEKResult              = base_env.CMEKResult
	ConfidentialSpaceResult = base_env.ConfidentialSpaceResult
	PeeringResult           = base_env.PeeringResult
)

// budgetConfig returns the standard budget configuration used for every
// project, matching the upstream TF project_budget variable.
func budgetConfig(cfg *ProjectsConfig) *project.BudgetConfig {
	return &project.BudgetConfig{
		Amount:             cfg.BudgetAmount,
		AlertSpentPercents: cfg.BudgetAlertPercents,
		AlertSpendBasis:    cfg.BudgetSpendBasis,
	}
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
// ID collision but not the duplication). It is off in every env today. (A cleaner
// long-term shape is a dedicated common/shared stack; deferred until Stage-5 CI/CD.)
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
			// Stage-5 app-tier: iamcredentials so a WIF-federated CI job can mint
			// an access token by impersonating the per-app build SA homed in this
			// shared infra-pipeline project (monorepo/serverless-WIF specific).
			"iamcredentials.googleapis.com",
		},
	})
	if err != nil {
		return pulumi.StringOutput{}, err
	}

	return infraProject.Project.ProjectId, nil
}
