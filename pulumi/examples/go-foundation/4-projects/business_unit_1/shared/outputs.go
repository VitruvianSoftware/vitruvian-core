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

// Stack exports for the shared leaf — the Pulumi analogue of upstream
// 4-projects/business_unit_1/shared/outputs.tf.

package main

import (
	"foundation-4-projects/modules/infra_pipelines"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// exportStackOutputs registers the leaf's stack exports. pipeline is nil when
// the infra-pipeline project is toggled off.
func exportStackOutputs(ctx *pulumi.Context, cfg *SharedConfig, pipeline *infra_pipelines.Result) {
	if pipeline != nil {
		// Upstream shared/outputs.tf exports cloudbuild_project_id; our WIF
		// port keeps the established export name (Stage 5 consumes it as the
		// shared build/artifact home).
		ctx.Export("infra_pipeline_project_id", pipeline.ProjectID)
	}

	ctx.Export("default_region", pulumi.String(cfg.Region))
}
