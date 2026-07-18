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

// Package infra_pipelines mirrors upstream terraform-example-foundation
// 4-projects/modules/infra_pipelines: the app-infra CI/CD home for a business
// unit, created ONCE per BU from the business_unit_1/shared leaf (upstream's
// `shared` workspace, environment=common).
//
// Engine-difference note (documented Pulumi workaround, per the port policy):
// upstream's module receives an existing cloudbuild_project_id (created in the
// shared leaf via modules/single_project) and fills it with Cloud Build
// triggers, CSRs, per-repo SAs, and state/log/artifact buckets. Our foundation
// deploys application infrastructure from GitHub Actions via Workload Identity
// Federation instead of Cloud Build, so this module owns the pipeline PROJECT
// (Cloud Build/Artifact Registry/IAM APIs enabled, WIF-ready via
// iamcredentials) and none of the Cloud Build machinery. The faithful Cloud
// Build port is kept as the build-tagged example in the go-foundation
// reference tree (modules/infra_pipelines/example_infra_pipelines.go).
package infra_pipelines

import (
	"fmt"

	project "github.com/VitruvianSoftware/pulumi-library/go/pkg/project_factory"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Args configures the shared app-infra pipeline project. It carries the subset
// of the upstream module variables that apply to the WIF model
// (billing_account, bucket/project prefixes, folder placement) plus the labels
// and budget the shared leaf computes for COMMON-folder projects.
type Args struct {
	// ProjectPrefix + BusinessCode form the project id:
	// {prefix}-c-{business_code}-infra-pipeline (upstream single_project with
	// environment "common" and project_suffix "infra-pipeline").
	ProjectPrefix  string
	BusinessCode   string
	BillingAccount string
	// RandomSuffix appends the project-factory random suffix to the project id.
	RandomSuffix bool

	// CommonFolderID is the 1-org common folder (upstream local.common_folder_name).
	CommonFolderID pulumi.StringInput

	// Labels are the COMMON-folder labels (environment=common, env_code=c, raw
	// application_name) computed by the shared leaf.
	Labels pulumi.StringMap
	// Budget mirrors the upstream project_budget variable.
	Budget *project.BudgetConfig

	// ApiPropagationSeconds is passed to the project factory. When >0 the
	// factory gates its ApisReady handle on a `sleep N` that depends on all
	// enabled Services, so consumers that DependsOn(ApisReady) (or read a gated
	// project id) don't race freshly-enabled APIs on a cold deploy. Mirrors
	// upstream project-factory's time_sleep. 0 disables the wait.
	ApiPropagationSeconds int
}

// Result holds the module outputs. Upstream outputs the Cloud Build plumbing
// (terraform_service_accounts, repos, buckets, trigger ids); under the WIF
// model the pipeline project id is the only output consumers need (upstream's
// cloudbuild_project_id analogue, exported by the shared leaf as
// infra_pipeline_project_id).
type Result struct {
	ProjectID pulumi.StringOutput
}

// Deploy creates the shared infrastructure-pipeline project under the COMMON
// folder. This project hosts the CI/CD pipeline for deploying application
// infrastructure (Stage 5): the build-once Artifact Registry plus the per-app
// build service accounts that GitHub-Actions WIF jobs impersonate.
//
// ONCE-PER-BU, structurally: upstream 4-projects creates this project a single
// time in the `shared` workspace (environment=common), and this module is
// called only from the business_unit_1/shared leaf — the per-env leaves never
// reference it, so the duplicate-project hazard of the old per-env
// infra_pipeline_enabled toggle is gone by construction.
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
// on the target project plus a WIF impersonation binding. When stage-5 moves an
// app onto the org's oss-floating projects, extend that app's deploy-identity
// stack to the target project per env, following the existing pattern — do NOT
// add upstream's Cloud-Build / shared-VPC pipeline-SA roles to this project.
func Deploy(ctx *pulumi.Context, args *Args) (*Result, error) {
	infraProject, err := project.NewProject(ctx, "infra-pipeline-project", &project.ProjectArgs{
		ProjectID:       pulumi.String(fmt.Sprintf("%s-c-%s-infra-pipeline", args.ProjectPrefix, args.BusinessCode)),
		Name:            pulumi.String(fmt.Sprintf("%s-c-%s-infra-pipeline", args.ProjectPrefix, args.BusinessCode)),
		FolderID:        args.CommonFolderID,
		BillingAccount:  pulumi.String(args.BillingAccount),
		RandomProjectID: args.RandomSuffix,
		Labels:          args.Labels,
		Budget:          args.Budget,
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
		ApiPropagationSeconds: args.ApiPropagationSeconds,
	})
	if err != nil {
		return nil, err
	}

	return &Result{ProjectID: infraProject.Project.ProjectId}, nil
}
