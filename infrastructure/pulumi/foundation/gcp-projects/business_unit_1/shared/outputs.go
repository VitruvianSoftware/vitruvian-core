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

// Stack exports for the shared leaf — the Pulumi analogue of upstream
// 4-projects/business_unit_1/shared/outputs.tf.

package main

import (
	"foundation-projects/modules/app_build_space"
	"foundation-projects/modules/infra_pipelines"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// exportStackOutputs registers the leaf's stack exports. pipeline is nil when
// the infra-pipeline project is toggled off.
func exportStackOutputs(ctx *pulumi.Context, cfg *SharedConfig, pipeline *infra_pipelines.Result, buildSpaces map[string]*app_build_space.Result) {
	// Per-app build space outputs. The env leaves consume these to grant their
	// own runtime/deploy identities READER on the repository — they cannot be
	// granted here because those identities live in stacks that apply later.
	for app, bs := range buildSpaces {
		ctx.Export(app+"_ar_repository_id", bs.RepositoryID)
		ctx.Export(app+"_build_service_account", bs.BuildServiceAccountEmail)
	}
	if pipeline != nil {
		// Upstream shared/outputs.tf exports cloudbuild_project_id; our WIF
		// port keeps the established export name (Stage 5 consumes it as the
		// shared build/artifact home).
		ctx.Export("infra_pipeline_project_id", pipeline.ProjectID)
	}

	ctx.Export("default_region", pulumi.String(cfg.Region))
}
