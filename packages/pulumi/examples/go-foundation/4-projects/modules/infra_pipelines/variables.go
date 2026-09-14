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
// 4-projects/modules/infra_pipelines/variables.tf (reduced to the subset that
// applies under the GitHub-Actions-WIF deploy model; see the package doc).

package infra_pipelines

import (
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
