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
	"foundation-4-projects/modules/infra_pipelines"

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

		// Exports (outputs.go)
		exportStackOutputs(ctx, cfg, pipeline)

		return nil
	})
}
