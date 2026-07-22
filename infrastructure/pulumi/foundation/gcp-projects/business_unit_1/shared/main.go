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

// Foundation stage 4 (projects) — the business unit's SHARED leaf, mirroring
// upstream terraform-example-foundation 4-projects/business_unit_1/shared:
// the once-per-BU, environment-independent resources — the app-infra pipeline
// project under the 1-org COMMON folder (environment=common/env_code=c). The
// per-env business-unit project sets live in the sibling
// business_unit_1/{development,nonproduction,production} leaves.
//
// Upstream's shared workspace deploys the pipeline via modules/single_project +
// modules/infra_pipelines (Cloud Build). Our port calls modules/infra_pipelines
// directly — under the GitHub-Actions-WIF deploy model it owns the pipeline
// project itself; see the module doc for the engine-difference note.
//
// File layout mirrors the upstream leaf: main.go (orchestration, upstream
// example_infra_pipeline.tf), config.go (variables.tf), remote.go (remote.tf),
// outputs.go (outputs.tf).
package main

import (
	"fmt"
	"foundation-projects/modules/app_build_space"
	"foundation-projects/modules/infra_pipelines"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// Environment identity pinned by this leaf — upstream's shared workspace
// labels its projects environment=common / env_code=c.
const (
	pinnedEnv     = "common"
	pinnedEnvCode = "c"
)

func main() {
	pulumi.Run(func(ctx *pulumi.Context) error {
		cfg := loadSharedConfig(ctx)

		// Cross-stage StackReferences (remote.go) — the 1-org COMMON folder.
		refs, err := loadStackReferences(ctx, cfg)
		if err != nil {
			return err
		}

		// Deploy the shared app-infra pipeline project (toggle-gated like
		// upstream's enable_cloudbuild_deploy; default true — deploying this leaf
		// means you want the BU's pipeline home).
		var pipeline *infra_pipelines.Result
		if cfg.InfraPipelineEnabled {
			pipeline, err = infra_pipelines.Deploy(ctx, &infra_pipelines.Args{
				ProjectPrefix:         cfg.ProjectPrefix,
				BusinessCode:          cfg.BusinessCode,
				BillingAccount:        cfg.BillingAccount,
				RandomSuffix:          cfg.RandomSuffix,
				CommonFolderID:        refs.CommonFolderID,
				Labels:                commonProjectLabels(cfg, "app-infra-pipelines"),
				Budget:                budgetConfig(cfg),
				ApiPropagationSeconds: cfg.ApiPropagationSeconds,
			})
			if err != nil {
				return err
			}
		}

		// Per-app build spaces: the Artifact Registry repository an app's
		// images live in, plus the identity allowed to push. Foundation-owned
		// because the repository sits in the BU's infra-pipeline project — an
		// app granting IAM there is the §3 test-4 inversion.
		//
		// Empty by default: these resources are LIVE under
		// oauth-user-inspector/infra/build, so listing an app is a cutover
		// step needing an import, not a fresh create.
		buildSpaces := map[string]*app_build_space.Result{}
		for _, bs := range cfg.AppBuildSpaces {
			if pipeline == nil {
				return fmt.Errorf("app_build_space %q: infra_pipeline_enabled must be true (the repository lives in that project)", bs.App)
			}
			res, err := app_build_space.Deploy(ctx, &app_build_space.Args{
				App:                  bs.App,
				BuildProjectID:       pipeline.ProjectID,
				Region:               cfg.Region,
				RepositoryID:         bs.RepositoryID,
				BuildAccountID:       bs.BuildAccountID,
				WorkloadIdentityPool: refs.WIFPoolName,
				GitHubEnvironment:    bs.GitHubEnvironment,
				KeepCount:            bs.KeepCount,
			})
			if err != nil {
				return err
			}
			buildSpaces[bs.App] = res
		}

		// Exports (outputs.go)
		exportStackOutputs(ctx, cfg, pipeline, buildSpaces)

		return nil
	})
}
