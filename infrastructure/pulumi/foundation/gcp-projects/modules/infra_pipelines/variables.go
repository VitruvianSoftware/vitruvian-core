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
